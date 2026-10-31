import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/repositories/local_network_repository.dart';
import '../touchpad/touchpad_screen.dart';
import '../system_monitor/system_monitor_screen.dart';
import '../file_manager/file_manager_screen.dart';
import '../power_control/power_control_dialog.dart';
import '../pairing/qr_scanner_screen.dart';

enum ConnectionMode { bluetooth, localWifi, mobileHotspot, internet, disconnected }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final LocalNetworkRepository _networkRepository = LocalNetworkRepository();
  bool _isConnected = false;
  String _pcName = "WORKSTATION-WIN11";
  String _connectedIp = "192.168.1.100";

  double _cpuUsage = 0.0;
  double _ramUsage = 0.0;
  double _diskUsage = 0.0;

  Timer? _metricsTimer;

  @override
  void initState() {
    super.initState();

    _networkRepository.stateStream.listen((state) {
      if (mounted) {
        bool connectedNow = state == WsConnectionState.connected;
        setState(() {
          _isConnected = connectedNow;
        });

        if (connectedNow) {
          _startMetricsPolling();
        } else {
          _stopMetricsPolling();
        }
      }
    });

    _networkRepository.messageStream.listen((data) {
      final type = data['type'] as String?;
      if (type == 'SYSTEM_METRICS_RESP') {
        final payload = data['payload'] as Map<String, dynamic>?;
        if (payload != null && mounted) {
          setState(() {
            _cpuUsage = (payload['cpuUsagePercent'] as num?)?.toDouble() ?? _cpuUsage;

            final ramUsed = (payload['ramUsedMb'] as num?)?.toDouble() ?? 0.0;
            final ramTotal = (payload['ramTotalMb'] as num?)?.toDouble() ?? 1.0;
            _ramUsage = ramTotal > 0 ? (ramUsed / ramTotal) * 100.0 : 0.0;

            final disks = payload['disks'] as List<dynamic>?;
            if (disks != null && disks.isNotEmpty) {
              final firstDisk = disks.first as Map<String, dynamic>;
              _diskUsage = (firstDisk['usagePercent'] as num?)?.toDouble() ?? _diskUsage;
            }
          });
        }
      }
    });
  }

  void _startMetricsPolling() {
    _metricsTimer?.cancel();
    _metricsTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_isConnected) {
        _networkRepository.sendFrame(type: 'SYSTEM_METRICS_REQ', payload: {});
      }
    });
    _networkRepository.sendFrame(type: 'SYSTEM_METRICS_REQ', payload: {});
  }

  void _stopMetricsPolling() {
    _metricsTimer?.cancel();
    _metricsTimer = null;
  }

  @override
  void dispose() {
    _stopMetricsPolling();
    _networkRepository.disconnect();
    super.dispose();
  }

  void _openQrScanner() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    if (!mounted) return;

    if (result != null && result is Map<String, dynamic>) {
      final ip = result['ip'] as String;
      final port = result['port'] as int;
      final code = result['code'] as String;

      setState(() {
        _connectedIp = ip;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connecting to $ip:$port...')),
      );

      bool ok = await _networkRepository.connect(ip, port);
      if (!mounted) return;

      if (ok) {
        bool authOk = await _networkRepository.sendHandshake(code);
        if (!mounted) return;

        if (authOk) {
          setState(() {
            _pcName = "PC ($ip)";
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Authorized & Connected!'), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pairing PIN rejected! Check code on PC.'), backgroundColor: Colors.red),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connection failed. Ensure phone & PC are on same Wi-Fi / Hotspot and PC Firewall allows port 8443.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _handleGridTap(String title) {
    if (!_isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please connect and pair with a PC first! Tap the QR Scanner icon in the top app bar.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (title.contains('Touchpad')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => TouchpadScreen(networkRepository: _networkRepository)),
      );
    } else if (title == 'System Monitor') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => SystemMonitorScreen(networkRepository: _networkRepository)),
      );
    } else if (title == 'File Manager') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => FileManagerScreen(networkRepository: _networkRepository)),
      );
    } else if (title == 'Power Controls') {
      showDialog(
        context: context,
        builder: (context) => PowerControlDialog(networkRepository: _networkRepository),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/images/logo.png', height: 32, errorBuilder: (_, __, ___) => const Icon(Icons.mouse, color: Color(0xFF00E5FF))),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('pc', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF00E5FF), fontSize: 18)),
                    Text('mouse', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00B0FF), fontSize: 18)),
                  ],
                ),
                Text('PRECISE. CONNECTED.', style: TextStyle(color: Color(0xFF00E5FF), fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF00E5FF)),
            tooltip: 'Pair New PC',
            onPressed: _openQrScanner,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDeviceStatusCard(),
            const SizedBox(height: 20),
            const Text(
              'System Monitoring',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            _buildMetricsOverview(),
            const SizedBox(height: 24),
            const Text(
              'Remote Controls',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 12),
            _buildControlGrid(),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isConnected ? Colors.green.withAlpha(50) : Colors.red.withAlpha(50),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.desktop_windows,
                    color: _isConnected ? Colors.greenAccent : Colors.redAccent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _pcName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isConnected ? 'Connected ($_connectedIp)' : 'Disconnected (Tap QR icon to connect)',
                        style: TextStyle(
                          fontSize: 13,
                          color: _isConnected ? Colors.greenAccent : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsOverview() {
    return Row(
      children: [
        Expanded(child: _buildMetricMiniCard('CPU', '${_cpuUsage.toStringAsFixed(1)}%', _cpuUsage / 100, Colors.cyanAccent)),
        const SizedBox(width: 10),
        Expanded(child: _buildMetricMiniCard('RAM', '${_ramUsage.toStringAsFixed(1)}%', _ramUsage / 100, Colors.purpleAccent)),
        const SizedBox(width: 10),
        Expanded(child: _buildMetricMiniCard('Disk', '${_diskUsage.toStringAsFixed(1)}%', _diskUsage / 100, Colors.orangeAccent)),
      ],
    );
  }

  Widget _buildMetricMiniCard(String title, String value, double percent, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: percent.clamp(0.0, 1.0),
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 4,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlGrid() {
    final controls = [
      {'title': 'Touchpad & Gestures', 'icon': Icons.touch_app, 'color': Colors.cyanAccent},
      {'title': 'System Monitor', 'icon': Icons.analytics, 'color': Colors.purpleAccent},
      {'title': 'File Manager', 'icon': Icons.folder_special, 'color': Colors.amberAccent},
      {'title': 'Power Controls', 'icon': Icons.power_settings_new, 'color': Colors.redAccent},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.3,
      ),
      itemCount: controls.length,
      itemBuilder: (context, index) {
        final item = controls[index];
        final title = item['title'] as String;
        final icon = item['icon'] as IconData;
        final color = item['color'] as Color;

        return Card(
          elevation: 2,
          child: InkWell(
            onTap: () => _handleGridTap(title),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 36, color: color),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
