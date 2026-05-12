import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

/// Smoke test del codec disk-cache (encode/decode Uint8List ↔ Float32List + header).
///
/// Replica la logica di [TerrainTileService._tileToBytes]/_bytesToTile senza
/// dipendere dal singleton (che richiederebbe Hive init). Verifica solo
/// che il roundtrip sia lossless e che l'allineamento funzioni.
void main() {
  test('tile codec roundtrip preserves header + elevations', () {
    const w = 256;
    const h = 256;
    const minLat = 45.0;
    const maxLat = 45.1;
    const minLng = 8.5;
    const maxLng = 8.6;

    // Synthesize una griglia di elevazioni (gradiente).
    final ele = Float32List(w * h);
    for (int i = 0; i < ele.length; i++) {
      ele[i] = (i % 1000).toDouble();
    }

    // Encode
    final out = BytesBuilder();
    final header = ByteData(16 + 4 * 4);
    header.setUint32(0, w, Endian.little);
    header.setUint32(4, h, Endian.little);
    header.setFloat32(8, minLat, Endian.little);
    header.setFloat32(12, maxLat, Endian.little);
    header.setFloat32(16, minLng, Endian.little);
    header.setFloat32(20, maxLng, Endian.little);
    out.add(header.buffer.asUint8List());
    out.add(ele.buffer.asUint8List());
    final bytes = out.toBytes();

    expect(bytes.length, 32 + w * h * 4);

    // Decode (copia safe, no Float32List.view direttamente)
    final bd = ByteData.sublistView(bytes, 0, 32);
    final dw = bd.getUint32(0, Endian.little);
    final dh = bd.getUint32(4, Endian.little);
    final dminLat = bd.getFloat32(8, Endian.little);
    final dmaxLat = bd.getFloat32(12, Endian.little);
    final dminLng = bd.getFloat32(16, Endian.little);
    final dmaxLng = bd.getFloat32(20, Endian.little);

    expect(dw, w);
    expect(dh, h);
    expect(dminLat, closeTo(minLat, 0.001));
    expect(dmaxLat, closeTo(maxLat, 0.001));
    expect(dminLng, closeTo(minLng, 0.001));
    expect(dmaxLng, closeTo(maxLng, 0.001));

    final eleBytes = ByteData.sublistView(bytes, 32, 32 + dw * dh * 4);
    final eleOut = Float32List(dw * dh);
    for (int i = 0; i < dw * dh; i++) {
      eleOut[i] = eleBytes.getFloat32(i * 4, Endian.little);
    }

    expect(eleOut.length, ele.length);
    expect(eleOut[0], ele[0]);
    expect(eleOut[12345], ele[12345]);
    expect(eleOut[ele.length - 1], ele[ele.length - 1]);
  });
}
