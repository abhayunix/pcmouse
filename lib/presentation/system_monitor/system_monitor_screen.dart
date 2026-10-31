import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/repositories/local_network_repository.dart';

class SystemMonitorScreen extends StatefulWidget {
  final LocalNetworkRepository networkRepository;

  const SystemMonitorScreen({super.key, required this.networkRepository});

  @override
  State<SystemMonitorScreen> createState() => _SystemMonitorScreenState();
}

class _SystemMonitorScreenState extends State<SystemMonitorScreen> {
  StreamSubscription? _subscription;
  Map<String, dynamic>? _metrics;
  List<dynamic> _processes = [];

  @override
  void initState() {
    super.initState();
    _subscription = widget.networkRepository.messageStream.listen((data) {
      final type = data['type'] as String?;
      if (type == 'SYSTEM_METRICS_RESP') {
        setState(() {
          _metrics = data['payload'] as Map<String, dynamic>?;
        });
      } else if (type == 'PROCESS_LIST_RESP') {
        setState(() {
          _processes = (data['payload'] as List<dynamic>?) ?? [];
        });
      }
    });

    _refreshData();
  }

  void _refreshData() {
    widget.networkRepository.sendFrame(type: 'SYSTEM_METRICS_REQ', payload: {});
    widget.networkRepository.sendFrame(type: 'PROCESS_LIST_REQ', payload: {});
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('System & Process Monitor'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshData,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Hardware Telemetry', icon: Icon(Icons.analytics)),
              Tab(text: 'Process Manager', icon: Icon(Icons.apps)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildTelemetryTab(),
            _buildProcessManagerTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryTab() {
    if (_metrics == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final cpu = ((_metrics!['cpuUsagePercent'] ?? _metrics!['CpuUsagePercent']) as num?)?.toDouble() ?? 0.0;
    final ramUsedMb = ((_metrics!['ramUsedMb'] ?? _metrics!['RamUsedMb']) as num?)?.toInt() ?? 0;
    final ramTotalMb = ((_metrics!['ramTotalMb'] ?? _metrics!['RamTotalMb']) as num?)?.toInt() ?? 1;
    final battery = ((_metrics!['batteryPercent'] ?? _metrics!['BatteryPercent']) as num?)?.toInt() ?? 100;
    final isCharging = ((_metrics!['isCharging'] ?? _metrics!['IsCharging']) as bool?) ?? false;

    double ramUsedGb = ramUsedMb / 1024.0;
    double ramTotalGb = ramTotalMb / 1024.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          _buildMetricBar('Processor (CPU)', '${cpu.toStringAsFixed(1)}%', cpu / 100, Colors.cyanAccent),
          const SizedBox(height: 16),
          _buildMetricBar('Memory (RAM)', '${ramUsedGb.toStringAsFixed(1)} GB / ${ramTotalGb.toStringAsFixed(1)} GB', ramUsedMb / ramTotalMb, Colors.purpleAccent),
          const SizedBox(height: 16),
          _buildMetricBar('Power / Battery', '$battery% ${isCharging ? '[Charging]' : ''}', battery / 100, Colors.greenAccent),
        ],
      ),
    );
  }

  Widget _buildMetricBar(String label, String valueText, double factor, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    valueText,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: factor.clamp(0.0, 1.0),
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProcessManagerTab() {
    if (_processes.isEmpty) {
      return const Center(child: Text('No active GUI windows running or loading...'));
    }

    return ListView.builder(
      itemCount: _processes.length,
      itemBuilder: (context, index) {
        final proc = _processes[index] as Map<String, dynamic>;
        final pid = (proc['id'] ?? proc['Id'] ?? 0) as int;
        final name = (proc['name'] ?? proc['Name'] ?? 'Unknown') as String;
        final title = (proc['windowTitle'] ?? proc['WindowTitle'] ?? '') as String;
        final mem = (proc['memoryMb'] ?? proc['MemoryMb'] ?? 0) as int;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF252526),
              child: Icon(Icons.window, color: Colors.cyanAccent, size: 20),
            ),
            title: Text(title.isNotEmpty ? title : name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
            subtitle: Text('PID: $pid | Memory: ${mem}MB', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        );
      },
    );
  }
}
