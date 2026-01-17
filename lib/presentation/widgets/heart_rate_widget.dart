import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/heart_rate_service.dart';

/// Widget per mostrare il battito cardiaco durante il tracking
class HeartRateWidget extends StatefulWidget {
  final bool showConnectButton;
  final Function(int bpm)? onHeartRateUpdate;

  const HeartRateWidget({
    super.key,
    this.showConnectButton = true,
    this.onHeartRateUpdate,
  });

  @override
  State<HeartRateWidget> createState() => _HeartRateWidgetState();
}

class _HeartRateWidgetState extends State<HeartRateWidget>
    with SingleTickerProviderStateMixin {
  final HeartRateService _service = HeartRateService();

  HRConnectionState _connectionState = HRConnectionState.disconnected;
  int? _currentBpm;
  StreamSubscription? _hrSubscription;
  StreamSubscription? _stateSubscription;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _stateSubscription = _service.connectionStateStream.listen((state) {
      if (mounted) {
        setState(() => _connectionState = state);
      }
    });

    _hrSubscription = _service.heartRateStream.listen((data) {
      if (mounted) {
        setState(() => _currentBpm = data.bpm);
        widget.onHeartRateUpdate?.call(data.bpm);
        _animatePulse();
      }
    });
  }

  void _animatePulse() {
    _pulseController.forward().then((_) {
      _pulseController.reverse();
    });
  }

  @override
  void dispose() {
    _hrSubscription?.cancel();
    _stateSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.showConnectButton ? _handleTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _getBackgroundColor(),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _getBorderColor(),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeartIcon(),
            const SizedBox(width: 8),
            _buildBpmText(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeartIcon() {
    final isConnected = _connectionState == HRConnectionState.connected;

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: isConnected ? _pulseAnimation.value : 1.0,
          child: Icon(
            isConnected ? Icons.favorite : Icons.favorite_border,
            color: _getIconColor(),
            size: 24,
          ),
        );
      },
    );
  }

  Widget _buildBpmText() {
    String text;
    TextStyle style = const TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 16,
    );

    switch (_connectionState) {
      case HRConnectionState.connected:
        text = _currentBpm != null ? '$_currentBpm' : '--';
        style = style.copyWith(color: AppColors.danger);
        break;
      case HRConnectionState.connecting:
        text = '...';
        style = style.copyWith(color: AppColors.textMuted);
        break;
      case HRConnectionState.scanning:
        text = 'Cerca';
        style = style.copyWith(color: AppColors.textMuted, fontSize: 12);
        break;
      case HRConnectionState.bluetoothOff:
        text = 'BT Off';
        style = style.copyWith(color: AppColors.warning, fontSize: 12);
        break;
      case HRConnectionState.error:
        text = 'Errore';
        style = style.copyWith(color: AppColors.danger, fontSize: 12);
        break;
      case HRConnectionState.disconnected:
      default:
        text = 'HR';
        style = style.copyWith(color: AppColors.textMuted);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: style),
        if (_connectionState == HRConnectionState.connected)
          const Text(
            'BPM',
            style: TextStyle(fontSize: 10, color: AppColors.textMuted),
          ),
      ],
    );
  }

  Color _getBackgroundColor() {
    switch (_connectionState) {
      case HRConnectionState.connected:
        return AppColors.danger.withOpacity(0.1);
      case HRConnectionState.bluetoothOff:
      case HRConnectionState.error:
        return AppColors.warning.withOpacity(0.1);
      default:
        return Colors.grey.withOpacity(0.1);
    }
  }

  Color _getBorderColor() {
    switch (_connectionState) {
      case HRConnectionState.connected:
        return AppColors.danger.withOpacity(0.3);
      case HRConnectionState.bluetoothOff:
      case HRConnectionState.error:
        return AppColors.warning.withOpacity(0.3);
      default:
        return Colors.grey.withOpacity(0.3);
    }
  }

  Color _getIconColor() {
    switch (_connectionState) {
      case HRConnectionState.connected:
        return AppColors.danger;
      case HRConnectionState.bluetoothOff:
      case HRConnectionState.error:
        return AppColors.warning;
      default:
        return AppColors.textMuted;
    }
  }

  void _handleTap() {
    if (_connectionState == HRConnectionState.connected) {
      _showDisconnectDialog();
    } else {
      _showDeviceSelector();
    }
  }

  Future<void> _showDeviceSelector() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const HeartRateDeviceSelector(),
    );
  }

  Future<void> _showDisconnectDialog() async {
    final disconnect = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fascia cardio'),
        content: Text(
          'Connesso a: ${_service.connectedDevice?.platformName ?? "Dispositivo"}\n'
          'Battito attuale: ${_currentBpm ?? "--"} BPM',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Chiudi'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Disconnetti'),
          ),
        ],
      ),
    );

    if (disconnect == true) {
      await _service.disconnect();
    }
  }
}

/// Bottom sheet per selezionare il dispositivo
class HeartRateDeviceSelector extends StatefulWidget {
  const HeartRateDeviceSelector({super.key});

  @override
  State<HeartRateDeviceSelector> createState() => _HeartRateDeviceSelectorState();
}

class _HeartRateDeviceSelectorState extends State<HeartRateDeviceSelector> {
  final HeartRateService _service = HeartRateService();

  List<ScanResult> _devices = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  String? _error;

  StreamSubscription? _scanSubscription;
  StreamSubscription? _stateSubscription;

  @override
  void initState() {
    super.initState();
    _startScan();

    _scanSubscription = _service.scanResultsStream.listen((results) {
      if (mounted) {
        setState(() => _devices = results);
      }
    });

    _stateSubscription = _service.connectionStateStream.listen((state) {
      if (mounted) {
        setState(() {
          _isScanning = state == HRConnectionState.scanning;
          _isConnecting = state == HRConnectionState.connecting;

          if (state == HRConnectionState.connected) {
            Navigator.pop(context);
          } else if (state == HRConnectionState.bluetoothOff) {
            _error = 'Bluetooth non attivo';
          } else if (state == HRConnectionState.error) {
            _error = 'Errore connessione';
            _isConnecting = false;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _stateSubscription?.cancel();
    _service.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _error = null;
      _devices = [];
    });
    await _service.startScan();
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _isConnecting = true;
      _error = null;
    });

    final success = await _service.connect(device);

    if (!success && mounted) {
      setState(() {
        _error = 'Connessione fallita';
        _isConnecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.favorite, color: AppColors.danger),
                  const SizedBox(width: 8),
                  const Text(
                    'Fascia Cardio',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (_isScanning)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _startScan,
                    ),
                ],
              ),
            ),
            if (_error != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: AppColors.warning),
                    const SizedBox(width: 8),
                    Text(_error!),
                  ],
                ),
              ),
            Expanded(
              child: _devices.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _devices.length,
                      itemBuilder: (context, index) {
                        final result = _devices[index];
                        return _DeviceListTile(
                          device: result.device,
                          rssi: result.rssi,
                          onTap: _isConnecting
                              ? null
                              : () => _connectToDevice(result.device),
                          isConnecting: _isConnecting,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState() {
    if (_isScanning) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Ricerca dispositivi...'),
            SizedBox(height: 8),
            Text(
              'Assicurati che la fascia sia accesa\ne il Bluetooth attivo',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth_searching, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text('Nessun dispositivo trovato'),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _startScan,
            child: const Text('Riprova'),
          ),
        ],
      ),
    );
  }
}

class _DeviceListTile extends StatelessWidget {
  final BluetoothDevice device;
  final int rssi;
  final VoidCallback? onTap;
  final bool isConnecting;

  const _DeviceListTile({
    required this.device,
    required this.rssi,
    this.onTap,
    this.isConnecting = false,
  });

  @override
  Widget build(BuildContext context) {
    final name = device.platformName.isNotEmpty
        ? device.platformName
        : 'Dispositivo sconosciuto';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.danger.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.favorite, color: AppColors.danger),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('Segnale: ${_rssiToQuality(rssi)}'),
        trailing: isConnecting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.bluetooth),
        onTap: onTap,
      ),
    );
  }

  String _rssiToQuality(int rssi) {
    if (rssi >= -50) return 'Eccellente';
    if (rssi >= -60) return 'Buono';
    if (rssi >= -70) return 'Medio';
    return 'Debole';
  }
}
