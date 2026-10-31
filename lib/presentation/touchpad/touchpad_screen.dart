import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/repositories/local_network_repository.dart';

class TouchpadScreen extends StatefulWidget {
  final LocalNetworkRepository networkRepository;

  const TouchpadScreen({super.key, required this.networkRepository});

  @override
  State<TouchpadScreen> createState() => _TouchpadScreenState();
}

class _TouchpadScreenState extends State<TouchpadScreen> {
  double _sensitivity = 2.2;
  bool _leftButtonDown = false;
  bool _rightButtonDown = false;
  bool _isDragSelectMode = false;

  bool _isLandscape = false;
  bool _isFullScreen = false;

  double _remainderX = 0.0;
  double _remainderY = 0.0;

  // Layout Settings
  bool _buttonsOnTop = false;
  bool _swapLeftRightButtons = false;
  String _scrollPosition = 'bottom_right';

  // Robust Gesture Tracker
  double _lastScale = 1.0;
  int _activePointers = 0; // Raw tracker for accurate finger count
  int _maxPointerCount = 0;
  bool _hasMovedSignificantly = false;
  DateTime _lastMultiSwipeTime = DateTime.now();

  bool _showInlineKeyboard = false;
  final TextEditingController _liveTextController = TextEditingController();
  final FocusNode _keyboardFocusNode = FocusNode();
  String _previousText = '';

  Timer? _scrollTimer;

  // Premium Dark Theme Colors
  final Color bgColor = const Color(0xFF09090B);
  final Color surfaceColor = const Color(0xFF18181B);
  final Color accentColor = const Color(0xFF00E5FF);

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _sensitivity = prefs.getDouble('trackpad_sensitivity') ?? 2.2;
        _buttonsOnTop = prefs.getBool('buttons_on_top') ?? false;
        _swapLeftRightButtons = prefs.getBool('swap_left_right_buttons') ?? false;
        _scrollPosition = prefs.getString('scroll_position') ?? 'bottom_right';
      });
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('trackpad_sensitivity', _sensitivity);
    await prefs.setBool('buttons_on_top', _buttonsOnTop);
    await prefs.setBool('swap_left_right_buttons', _swapLeftRightButtons);
    await prefs.setString('scroll_position', _scrollPosition);
  }

  @override
  void dispose() {
    if (_isLandscape) SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    if (_isFullScreen) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (_isDragSelectMode) widget.networkRepository.sendMouseEvent(action: 'BUTTON', button: 'LEFT', isDown: false);
    _scrollTimer?.cancel();
    _liveTextController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _sendVirtualKey(int vkCode) {
    widget.networkRepository.sendKeyboardEvent(action: 'KEY_PRESS', keyCode: vkCode);
  }

  void _sendVirtualKeyCombo(int key1, int key2) {
    widget.networkRepository.sendKeyboardEvent(action: 'KEY_DOWN', keyCode: key1);
    widget.networkRepository.sendKeyboardEvent(action: 'KEY_PRESS', keyCode: key2);
    widget.networkRepository.sendKeyboardEvent(action: 'KEY_UP', keyCode: key1);
  }

  void _sendVirtualKeyCombo3(int key1, int key2, int key3) {
    widget.networkRepository.sendKeyboardEvent(action: 'KEY_DOWN', keyCode: key1);
    widget.networkRepository.sendKeyboardEvent(action: 'KEY_DOWN', keyCode: key2);
    widget.networkRepository.sendKeyboardEvent(action: 'KEY_PRESS', keyCode: key3);
    widget.networkRepository.sendKeyboardEvent(action: 'KEY_UP', keyCode: key2);
    widget.networkRepository.sendKeyboardEvent(action: 'KEY_UP', keyCode: key1);
  }

  // --- GESTURE LOGIC (FIXED for Multi-Touch accuracy) ---
  void _onScaleStart(ScaleStartDetails details) {
    _hasMovedSignificantly = false;
    _lastScale = 1.0;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.focalPointDelta.distance > 1.0) _hasMovedSignificantly = true;

    // Use max of tracked active pointers to avoid glitchy 1-finger snaps
    int count = math.max(_activePointers, details.pointerCount);

    if (count == 1) {
      double rawDx = details.focalPointDelta.dx;
      double rawDy = details.focalPointDelta.dy;
      double accelFactor = 1.0 + ((rawDx * rawDx + rawDy * rawDy) * 0.012).clamp(0.0, 2.5);

      double targetDx = rawDx * _sensitivity * accelFactor + _remainderX;
      double targetDy = rawDy * _sensitivity * accelFactor + _remainderY;

      int sendDx = targetDx.round();
      int sendDy = targetDy.round();

      _remainderX = targetDx - sendDx;
      _remainderY = targetDy - sendDy;

      if (sendDx != 0 || sendDy != 0) {
        widget.networkRepository.sendMouseEvent(action: 'MOVE', dx: sendDx, dy: sendDy);
      }
    } else if (count == 2) {
      double scaleDelta = details.scale - _lastScale;
      if (scaleDelta.abs() > 0.12) {
        int scrollY = scaleDelta > 0 ? 120 : -120;
        widget.networkRepository.sendKeyboardEvent(action: 'KEY_DOWN', keyCode: 0x11);
        widget.networkRepository.sendMouseEvent(action: 'SCROLL', scrollDeltaY: scrollY);
        widget.networkRepository.sendKeyboardEvent(action: 'KEY_UP', keyCode: 0x11);
        _lastScale = details.scale;
      } else {
        int scrollX = (details.focalPointDelta.dx * 12.0).round();
        int scrollY = (-details.focalPointDelta.dy * 12.0).round();
        if (scrollX != 0 || scrollY != 0) {
          widget.networkRepository.sendMouseEvent(action: 'SCROLL', scrollDeltaY: scrollY, scrollDeltaX: scrollX);
        }
      }
    } else if (count >= 3) {
      if (_hasMovedSignificantly && DateTime.now().difference(_lastMultiSwipeTime).inMilliseconds > 450) {
        double dy = details.focalPointDelta.dy;
        double dx = details.focalPointDelta.dx;

        if (dy < -8) {
          _sendVirtualKeyCombo(0x5B, 0x09); // Win + Tab (Task View)
          _lastMultiSwipeTime = DateTime.now();
        } else if (dy > 8) {
          _sendVirtualKeyCombo(0x5B, 0x44); // Win + D (Desktop)
          _lastMultiSwipeTime = DateTime.now();
        } else if (dx.abs() > 10) {
          if (count == 4) {
            dx < 0 ? _sendVirtualKeyCombo3(0x5B, 0x11, 0x27) : _sendVirtualKeyCombo3(0x5B, 0x11, 0x25); // Virtual Desktops
          } else {
            _sendVirtualKeyCombo(0x12, 0x09); // Alt + Tab
          }
          _lastMultiSwipeTime = DateTime.now();
        }
      }
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (!_hasMovedSignificantly) {
      if (_maxPointerCount == 2) {
        widget.networkRepository.sendMouseEvent(action: 'RIGHT_CLICK');
      } else if (_maxPointerCount == 3) {
        _sendVirtualKeyCombo(0x5B, 0x53); // Win + S
      } else if (_maxPointerCount == 4) {
        _sendVirtualKeyCombo(0x5B, 0x4E); // Win + N
      }
    }
    // Reset max pointer count after gestures
    Future.delayed(const Duration(milliseconds: 100), () => _maxPointerCount = 0);
  }

  void _onTap() => widget.networkRepository.sendMouseEvent(action: 'CLICK');
  void _onDoubleTap() {
    widget.networkRepository.sendMouseEvent(action: 'CLICK');
    Future.delayed(const Duration(milliseconds: 50), () => widget.networkRepository.sendMouseEvent(action: 'CLICK'));
  }
  void _onLongPress() => widget.networkRepository.sendMouseEvent(action: 'RIGHT_CLICK');

  // --- D-PAD CONTINUOUS SCROLL ---
  void _startContinuousScroll({int dirY = 0, int dirX = 0}) {
    _send2DScrollStep(dirY: dirY, dirX: dirX);
    _scrollTimer?.cancel();
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 80), (_) => _send2DScrollStep(dirY: dirY, dirX: dirX));
  }
  void _stopContinuousScroll() => _scrollTimer?.cancel();
  void _send2DScrollStep({int dirY = 0, int dirX = 0}) {
    int scrollY = dirY > 0 ? -120 : (dirY < 0 ? 120 : 0);
    int scrollX = dirX > 0 ? 120 : (dirX < 0 ? -120 : 0);
    widget.networkRepository.sendMouseEvent(action: 'SCROLL', scrollDeltaY: scrollY, scrollDeltaX: scrollX);
  }

  // --- UI TOGGLES ---
  void _toggleScreenOrientation() {
    setState(() => _isLandscape = !_isLandscape);
    SystemChrome.setPreferredOrientations(_isLandscape ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] : [DeviceOrientation.portraitUp]);
  }
  void _toggleFullScreen() {
    setState(() => _isFullScreen = !_isFullScreen);
    SystemChrome.setEnabledSystemUIMode(_isFullScreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }
  void _toggleDragSelectMode() {
    setState(() => _isDragSelectMode = !_isDragSelectMode);
    widget.networkRepository.sendMouseEvent(action: 'BUTTON', button: 'LEFT', isDown: _isDragSelectMode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: _isFullScreen ? null : AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        title: const Text('Touchpad', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: Icon(Icons.pan_tool, color: _isDragSelectMode ? accentColor : Colors.white70), onPressed: _toggleDragSelectMode),
          IconButton(icon: Icon(_isLandscape ? Icons.screen_lock_rotation : Icons.screen_rotation, color: Colors.white70), onPressed: _toggleScreenOrientation),
          IconButton(icon: Icon(Icons.fullscreen, color: Colors.white70), onPressed: _toggleFullScreen),
          IconButton(
            icon: Icon(Icons.keyboard, color: _showInlineKeyboard ? accentColor : Colors.white70),
            onPressed: () {
              setState(() => _showInlineKeyboard = !_showInlineKeyboard);
              if (_showInlineKeyboard) _keyboardFocusNode.requestFocus(); else _keyboardFocusNode.unfocus();
            },
          ),
          IconButton(icon: const Icon(Icons.settings, color: Colors.white70), onPressed: _showSettingsDialog),
        ],
      ),
      body: Column(
        children: [
          if (_isDragSelectMode)
            Container(
              width: double.infinity, padding: const EdgeInsets.all(8), color: Colors.cyan.withOpacity(0.2),
              child: const Text('Drag Select Active! Slide to select text/windows.', textAlign: TextAlign.center, style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
            ),

          if (_showInlineKeyboard)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _liveTextController, focusNode: _keyboardFocusNode, style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Type here...', hintStyle: const TextStyle(color: Colors.white54),
                  filled: true, fillColor: surfaceColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (text) {
                  if (text.length > _previousText.length) {
                    widget.networkRepository.sendKeyboardEvent(action: 'TEXT', text: text.substring(_previousText.length));
                  } else if (text.length < _previousText.length) {
                    for (int i = 0; i < (_previousText.length - text.length); i++) _sendVirtualKey(0x08);
                  }
                  _previousText = text;
                },
              ),
            ),

          if (_buttonsOnTop && !_isFullScreen) _buildMouseButtonBar(),

          // MAIN TRACKPAD & D-PAD SCROLL BUTTONS
          Expanded(
            child: Stack(
              children: [
                // Trackpad Area with Raw Listener for exact pointer tracking
                Listener(
                  onPointerDown: (_) {
                    _activePointers++;
                    if (_activePointers > _maxPointerCount) _maxPointerCount = _activePointers;
                  },
                  onPointerUp: (_) => _activePointers--,
                  onPointerCancel: (_) => _activePointers--,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: _onScaleEnd,
                    onTap: _onTap,
                    onDoubleTap: _onDoubleTap,
                    onLongPress: _onLongPress,
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: surfaceColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white12, width: 1.5),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.touch_app, size: 40, color: Colors.white.withOpacity(0.1)),
                            const SizedBox(height: 10),
                            Text('Precision Touchpad Area', style: TextStyle(color: Colors.white.withOpacity(0.2), fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // FULL SCREEN EXIT BUTTON (Restored)
                if (_isFullScreen)
                  Positioned(
                    left: 20, top: 20,
                    child: SafeArea(
                      child: FloatingActionButton(
                        mini: true,
                        backgroundColor: const Color(0xFF252526).withOpacity(0.8),
                        onPressed: _toggleFullScreen,
                        child: const Icon(Icons.fullscreen_exit, color: Colors.cyanAccent),
                      ),
                    ),
                  ),

                // THE D-PAD SCROLL CLUSTER (Fixed using Listener)
                _buildPositionedScrollCluster(),
              ],
            ),
          ),

          if (!_buttonsOnTop && !_isFullScreen) _buildMouseButtonBar(),
        ],
      ),
    );
  }

  // --- D-PAD WIDGET (Fixed with raw Listener to avoid gesture overlap) ---
  Widget _buildPositionedScrollCluster() {
    double? left = _scrollPosition == 'bottom_left' ? 24 : null;
    double? right = _scrollPosition != 'bottom_left' ? 24 : null;
    double? top = _scrollPosition == 'top_right' ? 24 : null;
    double? bottom = _scrollPosition != 'top_right' ? 24 : null;

    return Positioned(
      left: left, right: right, top: top, bottom: bottom,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF252526).withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentColor.withOpacity(0.4), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildScrollBtn(Icons.arrow_drop_up, () => _startContinuousScroll(dirY: -1), _stopContinuousScroll),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildScrollBtn(Icons.arrow_left, () => _startContinuousScroll(dirX: -1), _stopContinuousScroll),
                const SizedBox(width: 6),
                _buildScrollBtn(Icons.arrow_drop_down, () => _startContinuousScroll(dirY: 1), _stopContinuousScroll),
                const SizedBox(width: 6),
                _buildScrollBtn(Icons.arrow_right, () => _startContinuousScroll(dirX: 1), _stopContinuousScroll),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollBtn(IconData icon, VoidCallback onDown, VoidCallback onUp) {
    // Listener is used here so it overrides parent gestures immediately
    return Listener(
      onPointerDown: (_) => onDown(),
      onPointerUp: (_) => onUp(),
      onPointerCancel: (_) => onUp(),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0xFF333333), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: accentColor, size: 24),
      ),
    );
  }

  // --- LEFT/RIGHT CLICK BUTTONS ---
  Widget _buildMouseButtonBar() {
    Widget leftBtn = Expanded(
      child: Listener(
        onPointerDown: (_) { setState(() => _leftButtonDown = true); widget.networkRepository.sendMouseEvent(action: 'BUTTON', button: 'LEFT', isDown: true); },
        onPointerUp: (_) { setState(() => _leftButtonDown = false); widget.networkRepository.sendMouseEvent(action: 'BUTTON', button: 'LEFT', isDown: false); },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(color: _leftButtonDown ? accentColor : const Color(0xFF2D2D2D), borderRadius: BorderRadius.circular(12)),
          child: Center(child: Text('LEFT CLICK', style: TextStyle(color: _leftButtonDown ? Colors.black : Colors.white, fontWeight: FontWeight.bold))),
        ),
      ),
    );

    Widget rightBtn = Expanded(
      child: Listener(
        onPointerDown: (_) { setState(() => _rightButtonDown = true); widget.networkRepository.sendMouseEvent(action: 'BUTTON', button: 'RIGHT', isDown: true); },
        onPointerUp: (_) { setState(() => _rightButtonDown = false); widget.networkRepository.sendMouseEvent(action: 'BUTTON', button: 'RIGHT', isDown: false); },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(color: _rightButtonDown ? accentColor : const Color(0xFF2D2D2D), borderRadius: BorderRadius.circular(12)),
          child: Center(child: Text('RIGHT CLICK', style: TextStyle(color: _rightButtonDown ? Colors.black : Colors.white, fontWeight: FontWeight.bold))),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Row(children: _swapLeftRightButtons ? [rightBtn, const SizedBox(width: 12), leftBtn] : [leftBtn, const SizedBox(width: 12), rightBtn]),
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: surfaceColor,
        title: const Text('Trackpad Settings', style: TextStyle(color: Colors.white)),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Sensitivity', style: TextStyle(color: Colors.white70)),
              Slider(
                value: _sensitivity, min: 0.8, max: 4.5, divisions: 10,
                onChanged: (val) {
                  setDialogState(() => _sensitivity = val);
                  setState(() => _sensitivity = val);
                  _saveSettings();
                },
              ),
              DropdownButton<String>(
                value: _scrollPosition,
                dropdownColor: const Color(0xFF252526),
                style: const TextStyle(color: Colors.white),
                items: const [
                  DropdownMenuItem(value: 'bottom_right', child: Text('D-Pad: Bottom Right')),
                  DropdownMenuItem(value: 'top_right', child: Text('D-Pad: Top Right')),
                  DropdownMenuItem(value: 'bottom_left', child: Text('D-Pad: Bottom Left')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() => _scrollPosition = val);
                    setState(() => _scrollPosition = val);
                    _saveSettings();
                  }
                },
              ),
              SwitchListTile(
                title: const Text('Swap Left/Right Click', style: TextStyle(color: Colors.white)),
                value: _swapLeftRightButtons,
                onChanged: (val) {
                  setDialogState(() => _swapLeftRightButtons = val);
                  setState(() => _swapLeftRightButtons = val);
                  _saveSettings();
                },
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done', style: TextStyle(color: Colors.cyanAccent)))],
      ),
    );
  }
}