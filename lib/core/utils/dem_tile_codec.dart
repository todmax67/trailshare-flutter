library dem_tile_codec;

/// Codifica compatta di un tile DEM per l'archiviazione su disco.
///
/// Il formato precedente scriveva le quote come `Float32` grezzi: 256 KB per
/// tile. Va benissimo come cache opportunistica, ma rende impossibile
/// l'obiettivo vero — **portarsi il terreno in montagna, dove non c'è rete** —
/// perché coprire una zona alpina richiede centinaia di tile e supererebbe i
/// cento megabyte.
///
/// Qui si sfrutta il fatto che il terreno è liscio: due campioni adiacenti
/// differiscono di pochi metri. Si memorizzano quindi le **differenze** invece
/// dei valori, in varint zigzag (i numeri piccoli occupano un byte solo), e si
/// comprime il tutto. Su terreno reale si scende sotto i 40 KB per tile.
///
/// Tre scelte che vale la pena motivare:
/// - **interi, non virgola mobile**: il dato di partenza è in metri interi, e i
///   decimali erano rumore che occupava metà dello spazio;
/// - **varint e non delta a larghezza fissa**: un dislivello può superare i
///   32767 metri di escursione fra due campioni solo in teoria, ma un formato
///   che si corrompe "solo in teoria" è un formato rotto. Il varint regge
///   qualunque valore senza costare nulla nei casi normali;
/// - **magic in testa**: la cache esistente sui telefoni è nel vecchio formato,
///   e va continuata a leggere invece di costringere a riscaricare tutto.

import 'dart:io' show ZLibCodec;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'dart:typed_data';

/// Firma del formato compatto. Il vecchio formato iniziava con la larghezza in
/// uint32 little-endian (256 → `00 01 00 00`), quindi non può collidere.
const List<int> demTileMagic = [0x54, 0x53, 0x44, 0x31]; // 'TSD1'

final ZLibCodec _zlib = ZLibCodec(level: 6);

/// Un tile DEM decodificato: griglia di quote in metri + bbox.
class DemTileData {
  final int width;
  final int height;
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
  final Float32List elevations;

  const DemTileData({
    required this.width,
    required this.height,
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
    required this.elevations,
  });
}

/// Serializza un tile nel formato compatto.
Uint8List encodeDemTile(DemTileData tile) {
  final count = tile.width * tile.height;
  final payload = BytesBuilder(copy: false);

  // Differenze rispetto al campione precedente, riga per riga: la prima colonna
  // fa da riferimento per la sua riga.
  int previous = 0;
  for (var i = 0; i < count; i++) {
    if (i % tile.width == 0) previous = 0;
    final value = _toMeters(tile.elevations[i]);
    _writeZigZagVarint(payload, value - previous);
    previous = value;
  }

  final compressed = _zlib.encode(payload.toBytes());

  final header = ByteData(4 + 4 + 32);
  for (var i = 0; i < 4; i++) {
    header.setUint8(i, demTileMagic[i]);
  }
  header.setUint16(4, tile.width, Endian.little);
  header.setUint16(6, tile.height, Endian.little);
  // Float64 e non Float32: i bordi di un tile a zoom alto differiscono alla
  // sesta cifra decimale, e in Float32 due tile adiacenti finirebbero per
  // dichiarare lo stesso confine con valori diversi.
  header.setFloat64(8, tile.minLat, Endian.little);
  header.setFloat64(16, tile.maxLat, Endian.little);
  header.setFloat64(24, tile.minLng, Endian.little);
  header.setFloat64(32, tile.maxLng, Endian.little);

  final out = BytesBuilder(copy: false)
    ..add(header.buffer.asUint8List())
    ..add(compressed);
  return out.toBytes();
}

/// Deserializza un tile dal formato compatto. `null` se i byte non sono in
/// questo formato (per esempio perché appartengono alla cache vecchia).
DemTileData? decodeDemTile(Uint8List bytes) {
  if (bytes.length < 40) return null;
  for (var i = 0; i < 4; i++) {
    if (bytes[i] != demTileMagic[i]) return null;
  }
  try {
    final header = ByteData.sublistView(bytes, 0, 40);
    final width = header.getUint16(4, Endian.little);
    final height = header.getUint16(6, Endian.little);
    if (width <= 0 || height <= 0) return null;

    final raw = _zlib.decode(Uint8List.sublistView(bytes, 40));
    final reader = _VarintReader(raw is Uint8List ? raw : Uint8List.fromList(raw));

    final count = width * height;
    final elevations = Float32List(count);
    int previous = 0;
    for (var i = 0; i < count; i++) {
      if (i % width == 0) previous = 0;
      previous += reader.readZigZagVarint();
      elevations[i] = previous.toDouble();
    }

    return DemTileData(
      width: width,
      height: height,
      minLat: header.getFloat64(8, Endian.little),
      maxLat: header.getFloat64(16, Endian.little),
      minLng: header.getFloat64(24, Endian.little),
      maxLng: header.getFloat64(32, Endian.little),
      elevations: elevations,
    );
  } catch (_) {
    // Byte corrotti o troncati: meglio far riscaricare il tile che restituire
    // un terreno inventato, che il viewshed userebbe per decidere cosa si vede.
    return null;
  }
}

/// Legge un tile nel **formato precedente**: header di 32 byte
/// (uint32 larghezza, uint32 altezza, quattro float32 di bbox) seguito dalle
/// quote come `Float32` grezzi.
///
/// Serve perché i telefoni hanno già una cache popolata, e cambiare formato non
/// deve significare riscaricare tutto: è un costo che pagherebbe l'utente per
/// una nostra decisione. Alla prima riscrittura il tile passa da solo al
/// formato compatto.
DemTileData? decodeLegacyDemTile(Uint8List bytes) {
  if (bytes.length < 32) return null;
  try {
    final bd = ByteData.sublistView(bytes, 0, 32);
    final w = bd.getUint32(0, Endian.little);
    final h = bd.getUint32(4, Endian.little);
    if (w <= 0 || h <= 0 || w > 8192 || h > 8192) return null;
    final needed = 32 + w * h * 4;
    if (bytes.length < needed) return null;

    // Copia elemento per elemento: la `Uint8List` che arriva da Hive non
    // garantisce l'allineamento a 4 byte, e una vista diretta esploderebbe.
    final ele = Float32List(w * h);
    final eleBytes = ByteData.sublistView(bytes, 32, needed);
    for (var i = 0; i < w * h; i++) {
      ele[i] = eleBytes.getFloat32(i * 4, Endian.little);
    }
    return DemTileData(
      width: w,
      height: h,
      minLat: bd.getFloat32(8, Endian.little),
      maxLat: bd.getFloat32(12, Endian.little),
      minLng: bd.getFloat32(16, Endian.little),
      maxLng: bd.getFloat32(20, Endian.little),
      elevations: ele,
    );
  } catch (_) {
    return null;
  }
}

/// Serializza nel **formato precedente**. Serve solo ai test: l'app scrive
/// sempre e solo quello compatto.
@visibleForTesting
Uint8List encodeLegacyDemTile(DemTileData t) {
  final header = ByteData(32);
  header.setUint32(0, t.width, Endian.little);
  header.setUint32(4, t.height, Endian.little);
  header.setFloat32(8, t.minLat, Endian.little);
  header.setFloat32(12, t.maxLat, Endian.little);
  header.setFloat32(16, t.minLng, Endian.little);
  header.setFloat32(20, t.maxLng, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(t.elevations.buffer.asUint8List()))
      .toBytes();
}

/// Quota in metri interi. I valori non finiti diventano zero: nei tile scaricati
/// non esistono (il NaN nasce solo nel mosaico), ma un formato che propaga NaN
/// silenziosamente sarebbe peggio di uno che sbaglia in modo evidente.
int _toMeters(double v) {
  if (!v.isFinite) return 0;
  return v.round();
}

void _writeZigZagVarint(BytesBuilder out, int value) {
  // ZigZag: i negativi piccoli diventano interi piccoli invece che enormi.
  var v = (value << 1) ^ (value >> 63);
  while (true) {
    if ((v & ~0x7F) == 0) {
      out.addByte(v);
      return;
    }
    out.addByte((v & 0x7F) | 0x80);
    v = v >>> 7;
  }
}

class _VarintReader {
  final Uint8List _bytes;
  int _pos = 0;
  _VarintReader(this._bytes);

  int readZigZagVarint() {
    var result = 0;
    var shift = 0;
    while (true) {
      if (_pos >= _bytes.length) {
        throw StateError('varint troncato');
      }
      final b = _bytes[_pos++];
      result |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
      if (shift > 63) throw StateError('varint troppo lungo');
    }
    return (result >>> 1) ^ -(result & 1);
  }
}
