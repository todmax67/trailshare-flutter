import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Servizio per connessione a fasce cardio Bluetooth Low Energy
class HeartRateService {
  static final HeartRateService _instance = HeartRateService._internal();
  factory HeartRateService() => _instance;
  HeartRateService._internal();

  // UUID standard BLE Heart Rate Service
  static const String heartRateServiceUuid = '0000180d-0000-1000-8000-00805f9b34fb';
  static const String heartRateMeasurementUuid = '00002a37-0000-1000-8000-00805f9b34fb';

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _heartRateCharacteristic;
  StreamSubscription? _heartRateSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _scanResultsSubscription;
  StreamSubscription? _isScanningSubscription;

  final _heartRateController = StreamController<HeartRateData>.broadcast();
  final _connectionStateController = StreamController<HRConnectionState>.broadcast();
  final _scanResultsController = StreamController<List<ScanResult>>.broadcast();

  Stream<HeartRateData> get heartRateStream => _heartRateController.stream;
  Stream<HRConnectionState> get connectionStateStream => _connectionStateController.stream;
  Stream<List<ScanResult>> get scanResultsStream => _scanResultsController.stream;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  Future<bool> isBluetoothAvailable() async {
    try {
      return await FlutterBluePlus.isSupported;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isBluetoothOn() async {
    try {
      final state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (e) {
      return false;
    }
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    try {
      if (!await isBluetoothOn()) {
        _connectionStateController.add(HRConnectionState.bluetoothOff);
        return;
      }

      _connectionStateController.add(HRConnectionState.scanning);
      await FlutterBluePlus.stopScan();

      await FlutterBluePlus.startScan(
        withServices: [Guid(heartRateServiceUuid)],
        timeout: timeout,
      );

      await _scanResultsSubscription?.cancel();
      _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
        _scanResultsController.add(results);
      });

      await _isScanningSubscription?.cancel();
      _isScanningSubscription = FlutterBluePlus.isScanning.listen((isScanning) {
        if (!isScanning && _connectedDevice == null) {
          _connectionStateController.add(HRConnectionState.disconnected);
        }
      });
    } catch (e) {
      debugPrint('[HeartRate] Errore scansione: $e');
      _connectionStateController.add(HRConnectionState.error);
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
      await _scanResultsSubscription?.cancel();
      _scanResultsSubscription = null;
      await _isScanningSubscription?.cancel();
      _isScanningSubscription = null;
    } catch (e) {
      debugPrint('[HeartRate] Errore stop scan: $e');
    }
  }

  Future<bool> connect(BluetoothDevice device) async {
    try {
      _connectionStateController.add(HRConnectionState.connecting);
      await stopScan();

      // Connetti senza parametro license
      await device.connect(mtu: null);

      _connectedDevice = device;

      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnection();
        }
      });

      final hrServiceGuid = Guid(heartRateServiceUuid);
      final hrMeasurementGuid = Guid(heartRateMeasurementUuid);

      // Discovery robusta: confronto per Guid (NON per stringa: i UUID
      // standard a 16 bit si stampano come "180d", non in forma estesa →
      // il vecchio confronto falliva anche col servizio presente) + retry
      // perché su Android i servizi a volte non sono pronti al 1° tentativo.
      BluetoothService? hrService;
      for (int attempt = 0; attempt < 3 && hrService == null; attempt++) {
        if (attempt > 0) {
          await Future.delayed(const Duration(milliseconds: 700));
        }
        final services = await device.discoverServices();
        debugPrint('[HeartRate] Discovery #${attempt + 1}: '
            '${services.length} servizi → '
            '${services.map((s) => s.uuid.toString()).join(", ")}');
        for (final service in services) {
          if (service.uuid == hrServiceGuid) {
            hrService = service;
            break;
          }
        }
      }

      if (hrService == null) {
        debugPrint('[HeartRate] Servizio Heart Rate non trovato dopo 3 tentativi');
        await disconnect();
        return false;
      }

      for (final char in hrService.characteristics) {
        if (char.uuid == hrMeasurementGuid) {
          _heartRateCharacteristic = char;
          break;
        }
      }

      if (_heartRateCharacteristic == null) {
        debugPrint('[HeartRate] Caratteristica Heart Rate non trovata');
        await disconnect();
        return false;
      }

      await _heartRateCharacteristic!.setNotifyValue(true);

      _heartRateSubscription = _heartRateCharacteristic!.onValueReceived.listen((value) {
        final hrData = _parseHeartRateData(value);
        if (hrData != null) {
          _heartRateController.add(hrData);
        }
      });

      _connectionStateController.add(HRConnectionState.connected);
      debugPrint('[HeartRate] Connesso a ${device.platformName}');

      return true;
    } catch (e) {
      debugPrint('[HeartRate] Errore connessione: $e');
      _connectionStateController.add(HRConnectionState.error);
      await disconnect();
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _heartRateSubscription?.cancel();
      _heartRateSubscription = null;

      await _connectionSubscription?.cancel();
      _connectionSubscription = null;

      if (_heartRateCharacteristic != null) {
        try {
          await _heartRateCharacteristic!.setNotifyValue(false);
        } catch (_) {
          // ignore: errore non bloccante
        }
      }
      _heartRateCharacteristic = null;

      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
      }
      _connectedDevice = null;

      _connectionStateController.add(HRConnectionState.disconnected);
    } catch (e) {
      debugPrint('[HeartRate] Errore disconnessione: $e');
    }
  }

  void _handleDisconnection() {
    debugPrint('[HeartRate] Dispositivo disconnesso');
    _connectedDevice = null;
    _heartRateCharacteristic = null;
    _heartRateSubscription?.cancel();
    _heartRateSubscription = null;
    _connectionStateController.add(HRConnectionState.disconnected);
  }

  HeartRateData? _parseHeartRateData(List<int> data) {
    if (data.isEmpty) return null;

    try {
      final flags = data[0];
      final isUint16 = (flags & 0x01) != 0;
      final hasRRInterval = (flags & 0x10) != 0;

      int offset = 1;
      int heartRate;

      if (isUint16) {
        heartRate = data[offset] | (data[offset + 1] << 8);
        offset += 2;
      } else {
        heartRate = data[offset];
        offset += 1;
      }

      List<int>? rrIntervals;
      if (hasRRInterval && offset < data.length) {
        rrIntervals = [];
        while (offset + 1 < data.length) {
          final rr = data[offset] | (data[offset + 1] << 8);
          rrIntervals.add((rr * 1000 / 1024).round());
          offset += 2;
        }
      }

      return HeartRateData(
        bpm: heartRate,
        timestamp: DateTime.now(),
        rrIntervals: rrIntervals,
      );
    } catch (e) {
      debugPrint('[HeartRate] Errore parsing: $e');
      return null;
    }
  }

  void dispose() {
    _heartRateSubscription?.cancel();
    _connectionSubscription?.cancel();
    _scanResultsSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _heartRateController.close();
    _connectionStateController.close();
    _scanResultsController.close();
  }
}

class HeartRateData {
  final int bpm;
  final DateTime timestamp;
  final List<int>? rrIntervals;

  const HeartRateData({
    required this.bpm,
    required this.timestamp,
    this.rrIntervals,
  });
}

enum HRConnectionState {
  disconnected,
  bluetoothOff,
  scanning,
  connecting,
  connected,
  error,
}
