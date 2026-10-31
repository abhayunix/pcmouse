import 'package:flutter/material.dart';
import '../../data/repositories/local_network_repository.dart';

class RemoteKeyboardScreen extends StatefulWidget {
  final LocalNetworkRepository networkRepository;

  const RemoteKeyboardScreen({super.key, required this.networkRepository});

  @override
  State<RemoteKeyboardScreen> createState() => _RemoteKeyboardScreenState();
}

class _RemoteKeyboardScreenState extends State<RemoteKeyboardScreen> {
  final TextEditingController _textController = TextEditingController();

  void _sendText() {
    if (_textController.text.isNotEmpty) {
      widget.networkRepository.sendKeyboardEvent(
        action: 'TEXT',
        text: _textController.text,
      );
      _textController.clear();
    }
  }

  void _sendVirtualKey(int vkCode) {
    widget.networkRepository.sendKeyboardEvent(
      action: 'KEY_PRESS',
      keyCode: vkCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote Keyboard'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // IME Text Dispatch Field
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        decoration: const InputDecoration(
                          hintText: 'Type text to send to PC...',
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendText(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: Color(0xFF00E5FF)),
                      onPressed: _sendText,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Functional Keys Row
            const Text('Special Functional Keys', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildKeyButton('ENTER ↵', 0x0D, color: Colors.cyanAccent),
                _buildKeyButton('BACKSPACE ⌫', 0x08, color: Colors.orangeAccent),
                _buildKeyButton('TAB ⇥', 0x09),
                _buildKeyButton('ESC ⎋', 0x1B, color: Colors.redAccent),
                _buildKeyButton('SPACE ␣', 0x20),
                _buildKeyButton('WIN ❖', 0x5B, color: Colors.purpleAccent),
              ],
            ),
            const SizedBox(height: 20),

            // Shortcuts Row
            const Text('Quick Shortcuts', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildShortcutButton('Ctrl + C', () {
                  _sendVirtualKey(0x11); // Ctrl
                  _sendVirtualKey(0x43); // C
                }),
                _buildShortcutButton('Ctrl + V', () {
                  _sendVirtualKey(0x11);
                  _sendVirtualKey(0x56);
                }),
                _buildShortcutButton('Alt + Tab', () {
                  _sendVirtualKey(0x12);
                  _sendVirtualKey(0x09);
                }),
                _buildShortcutButton('Win + D (Show Desktop)', () {
                  _sendVirtualKey(0x5B);
                  _sendVirtualKey(0x44);
                }),
              ],
            ),
            const SizedBox(height: 20),

            // Function Keys Grid F1 - F12
            const Text('Function Keys (F1 - F12)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 12,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 2.2,
              ),
              itemBuilder: (context, index) {
                int fKeyIndex = index + 1;
                int vkCode = 0x70 + index; // F1 is 0x70
                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF252526),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => _sendVirtualKey(vkCode),
                  child: Text('F$fKeyIndex', style: const TextStyle(fontWeight: FontWeight.bold)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyButton(String label, int vkCode, {Color color = Colors.white}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF252526),
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onPressed: () => _sendVirtualKey(vkCode),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildShortcutButton(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
      backgroundColor: const Color(0xFF1E1E1E),
      side: const BorderSide(color: Colors.cyanAccent),
      onPressed: onTap,
    );
  }
}
