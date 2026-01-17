import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Servizio per connessione a fasce cardio Bluetooth Low Energy
class HeartRateService {
  static final HeartRateService _instance = HeartRateService._internal();
  factory HeartRateService() => _instance;
  HeartRateService._internal();

  // UUID standard BLE Heart Rate Service
  static const String HEART_RATE_SERVICE_UUID = '0000180d-0000-1000-8000-00805f9b34fb';
  static const String HEART_RATE_MEASUREMENT_UUID = '00002a37-0000-1000-8000-00805f9b34fb';

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _heartRateCharacteristic;
  StreamSubscription? _heartRateSubscription;
  StreamSubscription? _connectionSubscription;

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
        withServices: [Guid(HEART_RATE_SERVICE_UUID)],
        timeout: timeout,
      );

      FlutterBluePlus.scanResults.listen((results) {
        _scanResultsController.add(results);
      });

      FlutterBluePlus.isScanning.listen((isScanning) {
        if (!isScanning && _connectedDevice == null) {
          _connectionStateController.add(HRConnectionState.disconnected);
        }
      });
    } catch (e) {
      print('[HeartRate] Errore scansione: $e');
      _connectionStateController.add(HRConnectionState.error);
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      print('[HeartRate] Errore stop scan: $e');
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

      final services = await device.discoverServices();

      BluetoothService? hrService;
      for (final service in services) {
        if (service.uuid.toString().toLowerCase() == HEART_RATE_SERVICE_UUID) {
          hrService = service;
          break;
        }
      }

      if (hrService == null) {
        print('[HeartRate] Servizio Heart Rate non trovato');
        await disconnect();
        return false;
      }

      for (final char in hrService.characteristics) {
        if (char.uuid.toString().toLowerCase() == HEART_RATE_MEASUREMENT_UUID) {
          _heartRateCharacteristic = char;
          break;
        }
      }

      if (_heartRateCharacteristic == null) {
        print('[HeartRate] Caratteristica Heart Rate non trovata');
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
      print('[HeartRate] Connesso a ${device.platformName}');

      return true;
    } catch (e) {
      print('[HeartRate] Errore connessione: $e');
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
        } catch (e) {}
      }
      _heartRateCharacteristic = null;

      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
      }
      _connectedDevice = null;

      _connectionStateController.add(HRConnectionState.disconnected);
    } catch (e) {
      print('[HeartRate] Errore disconnessione: $e');
    }
  }

  void _handleDisconnection() {
    print('[HeartRate] Dispositivo disconnesso');
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
      print('[HeartRate] Errore parsing: $e');
      return null;
    }
  }

  void dispose() {
    _heartRateSubscription?.cancel();
    _connectionSubscription?.cancel();
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
