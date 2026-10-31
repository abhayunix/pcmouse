import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/repositories/local_network_repository.dart';

class TerminalScreen extends StatefulWidget {
  final LocalNetworkRepository networkRepository;

  const TerminalScreen({super.key, required this.networkRepository});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  StreamSubscription? _subscription;
  String _selectedShell = 'powershell'; // 'powershell' or 'cmd'
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _history = [];
  bool _isExecuting = false;

  static const bgColor = Color(0xFF0D1117);
  static const surfaceColor = Color(0xFF161B22);
  static const accentColor = Color(0xFF00E5FF);

  @override
  void initState() {
    super.initState();
    _subscription = widget.networkRepository.messageStream.listen((data) {
      if (data['type'] == 'TERMINAL_CMD_RESP') {
        final payload = data['payload'] as Map<String, dynamic>?;
        if (payload != null && mounted) {
          String cmd = payload['command'] as String? ?? '';
          String shell = payload['shell'] as String? ?? 'powershell';
          String result = payload['result'] as String? ?? 'No output.';

          setState(() {
            _history.add({
              'cmd': cmd,
              'shell': shell,
              'result': result,
            });
            _isExecuting = false;
          });

          _scrollToBottom();
        }
      }
    });
  }

  void _sendCommand(String command) {
    if (command.trim().isEmpty || _isExecuting) return;

    if (command.trim().toLowerCase() == 'cls' || command.trim().toLowerCase() == 'clear') {
      setState(() {
        _history.clear();
        _commandController.clear();
      });
      return;
    }

    setState(() => _isExecuting = true);
    widget.networkRepository.sendFrame(
      type: 'TERMINAL_CMD_REQ',
      payload: {
        'command': command,
        'shell': _selectedShell,
      },
    );

    _commandController.clear();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _commandController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: surfaceColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Icon(Icons.terminal_rounded, color: accentColor, size: 22),
            const SizedBox(width: 8),
            Text(
              _selectedShell == 'powershell' ? 'PowerShell Terminal' : 'CMD Command Prompt',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        actions: [
          // Shell Switcher Toggle
          Container(
            margin: const EdgeInsets.only(right: 12),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'powershell', label: Text('PS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                ButtonSegment(value: 'cmd', label: Text('CMD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
              ],
              selected: {_selectedShell},
              onSelectionChanged: (newSelection) {
                setState(() => _selectedShell = newSelection.first);
              },
              style: SegmentedButton.styleFrom(
                backgroundColor: bgColor,
                selectedBackgroundColor: accentColor,
                selectedForegroundColor: Colors.black,
                foregroundColor: Colors.white70,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Quick Command Shortcut Chips Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            color: const Color(0xFF161616),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildQuickCmdChip('dir', () => _sendCommand('dir')),
                  _buildQuickCmdChip('ipconfig', () => _sendCommand('ipconfig')),
                  _buildQuickCmdChip('systeminfo', () => _sendCommand('systeminfo')),
                  _buildQuickCmdChip('get-process', () => _sendCommand('get-process')),
                  _buildQuickCmdChip('ping 8.8.8.8', () => _sendCommand('ping 8.8.8.8')),
                  _buildQuickCmdChip('Clear (cls)', () {
                    setState(() => _history.clear());
                  }, color: Colors.amberAccent),
                ],
              ),
            ),
          ),

          // Scrollable Console Terminal Output Area
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF05080C),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: _history.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.terminal_rounded, size: 48, color: accentColor.withValues(alpha: 0.3)),
                          const SizedBox(height: 12),
                          Text(
                            'Remote ${_selectedShell.toUpperCase()} Ready\nType a command below to execute on PC',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white38, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final item = _history[index];
                        final cmd = item['cmd'] ?? '';
                        final shell = item['shell'] ?? 'ps';
                        final result = item['result'] ?? '';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Command Prompt Header Line
                              Row(
                                children: [
                                  Text(
                                    '[PC:${shell.toUpperCase()}]> ',
                                    style: const TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
                                  ),
                                  Expanded(
                                    child: Text(
                                      cmd,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              // Command Result Output
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D1117),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: SelectableText(
                                  result,
                                  style: TextStyle(
                                    color: result.contains('[ERROR') ? Colors.redAccent : Colors.lightGreenAccent,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),

          // Execution Progress Indicator
          if (_isExecuting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: accentColor)),
                  SizedBox(width: 10),
                  Text('Executing command on Windows PC...', style: TextStyle(color: accentColor, fontSize: 12)),
                ],
              ),
            ),

          // Command Input Field & Send Button
          Container(
            padding: const EdgeInsets.all(8),
            color: surfaceColor,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commandController,
                    style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                    textInputAction: TextInputAction.send,
                    onSubmitted: _sendCommand,
                    decoration: InputDecoration(
                      hintText: 'Enter ${_selectedShell.toUpperCase()} command (e.g. dir, ipconfig)...',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      filled: true,
                      fillColor: const Color(0xFF0D1117),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.black),
                  icon: const Icon(Icons.send_rounded),
                  tooltip: 'Execute Command',
                  onPressed: () => _sendCommand(_commandController.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickCmdChip(String label, VoidCallback onTap, {Color color = accentColor}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: ActionChip(
        label: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
        backgroundColor: const Color(0xFF21262D),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        onPressed: onTap,
      ),
    );
  }
}
