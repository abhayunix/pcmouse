import 'package:flutter/material.dart';
import '../../data/repositories/local_network_repository.dart';

class PowerControlDialog extends StatelessWidget {
  final LocalNetworkRepository networkRepository;

  const PowerControlDialog({super.key, required this.networkRepository});

  void _confirmAndExecute(BuildContext context, String actionTitle, String action) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm $actionTitle'),
        content: Text('Are you sure you want to $actionTitle the PC?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              networkRepository.sendSystemCommand(action);
              Navigator.pop(context); // Close confirm
              Navigator.pop(context); // Close power panel
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Executing $actionTitle on PC...')),
              );
            },
            child: Text(actionTitle),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PC Power Management',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.lock, color: Colors.amberAccent),
              title: const Text('Lock PC Workstation'),
              onTap: () {
                networkRepository.sendSystemCommand('LOCK');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.bedtime, color: Colors.purpleAccent),
              title: const Text('Sleep / Standby'),
              onTap: () => _confirmAndExecute(context, 'Sleep', 'SLEEP'),
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt, color: Colors.orangeAccent),
              title: const Text('Restart PC'),
              onTap: () => _confirmAndExecute(context, 'Restart', 'RESTART'),
            ),
            ListTile(
              leading: const Icon(Icons.power_settings_new, color: Colors.redAccent),
              title: const Text('Shutdown PC'),
              onTap: () => _confirmAndExecute(context, 'Shutdown', 'SHUTDOWN'),
            ),
          ],
        ),
      ),
    );
  }
}
