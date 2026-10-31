import 'dart:async';
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

  // Sub-pixel Accumulator
  double _remainderX = 0.0;
  double _remainderY = 0.0;

  // Settings
  bool _buttonsOnTop = false;
  bool _swapLeftRightButtons = false;
  String _scrollPosition = 'bottom_right';

  // Pointer & Gesture Engine
  int _activePointers = 0;
  int _maxPointerCount = 0;
  double _lastScale = 1.0;
  Offset _accumulatedDelta = Offset.zero;

  // Live Keyboard
  bool _showInlineKeyboard = false;
  final TextEditingController _liveTextController = TextEditingController();
  final FocusNode _keyboardFocusNode = FocusNode();
  String _previousText = '';

  Timer? _scrollTimer;
  StreamSubscription? _clipboardSubscription;

  static const bgColor = Color(0xFF0D1117);
  static const surfaceColor = Color(0xFF161B22);
  static const accentColor = Color(0xFF00E5FF);

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();

    _clipboardSubscription = widget.networkRepository.messageStream.listen((data) {
      if (data['type'] == 'CLIPBOARD_GET_RESP') {
        final payload = data['payload'] as Map<String, dynamic>?;
        if (payload != null && mounted) {
          String pcText = payload['text'] as String? ?? '';
          if (pcText.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: pcText));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Copied from PC Clipboard: "$pcText"'), backgroundColor: Colors.green),
            );
          }
        }
      }
    });
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
    if (_isLandscape) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    if (_isDragSelectMode) {
      widget.networkRepository.sendMouseEvent(action: 'BUTTON', button: 'LEFT', isDown: false);
    }
    _scrollTimer?.cancel();
    _clipboardSubscription?.cancel();
    _liveTextController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _toggleScreenOrientation() {
    setState(() => _isLandscape = !_isLandscape);
    SystemChrome.setPreferredOrientations(
      _isLandscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp],
    );
  }

  void _toggleFullScreen() {
    setState(() => _isFullScreen = !_isFullScreen);
    SystemChrome.setEnabledSystemUIMode(
      _isFullScreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  void _toggleDragSelectMode() {
    setState(() => _isDragSelectMode = !_isDragSelectMode);
    widget.networkRepository.sendMouseEvent(action: 'BUTTON', button: 'LEFT', isDown: _isDragSelectMode);
  }

  void _startContinuousScroll({int dirY = 0, int dirX = 0}) {
    _send2DScrollStep(dirY: dirY, dirX: dirX);
    _scrollTimer?.cancel();
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 90), (timer) {
      _send2DScrollStep(dirY: dirY, dirX: dirX);
    });
  }

  void _stopContinuousScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }

  void _send2DScrollStep({int dirY = 0, int dirX = 0}) {
    widget.networkRepository.sendMouseEvent(
      action: 'SCROLL',
      scrollDeltaY: dirY > 0 ? -160 : (dirY < 0 ? 160 : 0),
      scrollDeltaX: dirX > 0 ? 160 : (dirX < 0 ? -160 : 0),
    );
  }

  // --- WINDOWS 11 PRECISION GESTURE ENGINE ---
  void _onScaleStart(ScaleStartDetails details) {
    _lastScale = 1.0;
    _maxPointerCount = details.pointerCount;
    _accumulatedDelta = Offset.zero;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    int pointers = details.pointerCount > _maxPointerCount ? details.pointerCount : _maxPointerCount;

    // 1-FINGER: MOUSE MOVEMENT
    if (pointers == 1) {
      double rawDx = details.focalPointDelta.dx;
      double rawDy = details.focalPointDelta.dy;

      double speedSq = rawDx * rawDx + rawDy * rawDy;
      double accelFactor = 1.0 + (speedSq * 0.012).clamp(0.0, 2.5);

      double targetDx = rawDx * _sensitivity * accelFactor + _remainderX;
      double targetDy = rawDy * _sensitivity * accelFactor + _remainderY;

      int sendDx = targetDx.round();
      int sendDy = targetDy.round();

      _remainderX = targetDx - sendDx;
      _remainderY = targetDy - sendDy;

      if (sendDx != 0 || sendDy != 0) {
        widget.networkRepository.sendMouseEvent(action: 'MOVE', dx: sendDx, dy: sendDy);
      }
    }
    // 2-FINGERS: 2D SCROLLING OR PINCH ZOOM
    else if (pointers == 2) {
      double scaleDelta = details.scale - _lastScale;
      if (scaleDelta.abs() > 0.12) {
        int scrollY = scaleDelta > 0 ? 120 : -120;
        widget.networkRepository.sendKeyboardEvent(action: 'KEY_DOWN', keyCode: 0x11);
        widget.networkRepository.sendMouseEvent(action: 'SCROLL', scrollDeltaY: scrollY);
        widget.networkRepository.sendKeyboardEvent(action: 'KEY_UP', keyCode: 0x11);
        _lastScale = details.scale;
      } else {
        int scrollX = (details.focalPointDelta.dx * 16.0).round();
        int scrollY = (-details.focalPointDelta.dy * 16.0).round();

        if (scrollX != 0 || scrollY != 0) {
          widget.networkRepository.sendMouseEvent(action: 'SCROLL', scrollDeltaY: scrollY, scrollDeltaX: scrollX);
        }
      }
    }
    // 3-FINGERS: TRACK ACCUMULATED SWIPE DISPLACEMENT
    else if (pointers == 3) {
      _accumulatedDelta += details.focalPointDelta;
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    // TRIGGER 3-FINGER SWIPE ACTIONS ON GESTURE RELEASE
    if (_maxPointerCount == 3) {
      if (_accumulatedDelta.dy < -25) {
        // 3-Finger Swipe UP -> Task View (Win + Tab)
        _sendVirtualKey(0x5B);
        _sendVirtualKey(0x09);
      } else if (_accumulatedDelta.dy > 25) {
        // 3-Finger Swipe DOWN -> Show Desktop (Win + D)
        _sendVirtualKey(0x5B);
        _sendVirtualKey(0x44);
      } else if (_accumulatedDelta.dx < -25 || _accumulatedDelta.dx > 25) {
        // 3-Finger Swipe LEFT/RIGHT -> Switch Active Apps (Alt + Tab)
        _sendVirtualKey(0x12);
        _sendVirtualKey(0x09);
      }
    }
    _maxPointerCount = 0;
  }

  void _onTap() {
    if (_maxPointerCount <= 1) {
      widget.networkRepository.sendMouseEvent(action: 'CLICK');
    } else if (_maxPointerCount == 2) {
      widget.networkRepository.sendMouseEvent(action: 'RIGHT_CLICK');
    }
  }

  void _onDoubleTap() {
    widget.networkRepository.sendMouseEvent(action: 'RIGHT_CLICK');
  }

  void _onLongPress() {
    widget.networkRepository.sendMouseEvent(action: 'RIGHT_CLICK');
  }

  void _sendVirtualKey(int vkCode) {
    widget.networkRepository.sendKeyboardEvent(action: 'KEY_PRESS', keyCode: vkCode);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: _isFullScreen
          ? null
          : AppBar(
              backgroundColor: bgColor,
              elevation: 0,
              title: const Text('Touchpad', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              actions: [
                IconButton(icon: Icon(Icons.pan_tool, color: _isDragSelectMode ? accentColor : Colors.white70), onPressed: _toggleDragSelectMode),
                IconButton(icon: Icon(_isLandscape ? Icons.screen_lock_rotation : Icons.screen_rotation, color: Colors.white70), onPressed: _toggleScreenOrientation),
                IconButton(icon: const Icon(Icons.fullscreen, color: Colors.white70), onPressed: _toggleFullScreen),
                IconButton(
                  icon: Icon(Icons.keyboard, color: _showInlineKeyboard ? accentColor : Colors.white70),
                  onPressed: () {
                    setState(() => _showInlineKeyboard = !_showInlineKeyboard);
                    if (_showInlineKeyboard) {
                      _keyboardFocusNode.requestFocus();
                    } else {
                      _keyboardFocusNode.unfocus();
                    }
                  },
                ),
                IconButton(icon: const Icon(Icons.settings, color: Colors.white70), onPressed: _showSettingsDialog),
              ],
            ),
      body: Column(
        children: [
          if (_isDragSelectMode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.cyan.withValues(alpha: 0.2),
              child: const Text('Drag Select Active! Slide to select text/windows.', textAlign: TextAlign.center, style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
            ),

          if (_showInlineKeyboard)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _liveTextController,
                focusNode: _keyboardFocusNode,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Type here...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  filled: true,
                  fillColor: surfaceColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onChanged: (text) {
                  if (text.length > _previousText.length) {
                    widget.networkRepository.sendKeyboardEvent(action: 'TEXT', text: text.substring(_previousText.length));
                  } else if (text.length < _previousText.length) {
                    for (int i = 0; i < (_previousText.length - text.length); i++) {
                      _sendVirtualKey(0x08);
                    }
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
                    if (_activePointers > _maxPointerCount) {
                      _maxPointerCount = _activePointers;
                    }
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
                            Icon(Icons.touch_app, size: 40, color: Colors.white.withValues(alpha: 0.1)),
                            const SizedBox(height: 10),
                            Text('Precision Touchpad Area', style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // FULL SCREEN EXIT BUTTON
                if (_isFullScreen)
                  Positioned(
                    left: 20,
                    top: 20,
                    child: SafeArea(
                      child: FloatingActionButton(
                        mini: true,
                        backgroundColor: const Color(0xFF252526).withValues(alpha: 0.8),
                        onPressed: _toggleFullScreen,
                        child: const Icon(Icons.fullscreen_exit, color: Colors.cyanAccent),
                      ),
                    ),
                  ),

                // THE D-PAD SCROLL CLUSTER
                _buildPositionedScrollCluster(),
              ],
            ),
          ),

          if (!_buttonsOnTop && !_isFullScreen) _buildMouseButtonBar(),
        ],
      ),
    );
  }

  // --- D-PAD WIDGET ---
  Widget _buildPositionedScrollCluster() {
    double? left = _scrollPosition == 'bottom_left' ? 24 : null;
    double? right = _scrollPosition != 'bottom_left' ? 24 : null;
    double? top = _scrollPosition == 'top_right' ? 24 : null;
    double? bottom = _scrollPosition != 'top_right' ? 24 : null;

    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF252526).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 1.5),
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

  Widget _buildScrollBtn(IconData icon, VoidCallback onTapDown, VoidCallback onTapUp) {
    return Listener(
      onPointerDown: (_) => onTapDown(),
      onPointerUp: (_) => onTapUp(),
      onPointerCancel: (_) => onTapUp(),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF333333),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: accentColor, size: 22),
      ),
    );
  }

  Widget _buildMouseButtonBar() {
    Widget leftBtn = Expanded(
      child: Listener(
        onPointerDown: (_) {
          setState(() => _leftButtonDown = true);
          widget.networkRepository.sendMouseEvent(action: 'BUTTON', button: 'LEFT', isDown: true);
        },
        onPointerUp: (_) {
          setState(() => _leftButtonDown = false);
          widget.networkRepository.sendMouseEvent(action: 'BUTTON', button: 'LEFT', isDown: false);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _leftButtonDown ? accentColor : surfaceColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              'LEFT CLICK',
              style: TextStyle(
                color: _leftButtonDown ? Colors.black : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );

    Widget rightBtn = Expanded(
      child: Listener(
        onPointerDown: (_) {
          setState(() => _rightButtonDown = true);
          widget.networkRepository.sendMouseEvent(action: 'BUTTON', button: 'RIGHT', isDown: true);
        },
        onPointerUp: (_) {
          setState(() => _rightButtonDown = false);
          widget.networkRepository.sendMouseEvent(action: 'BUTTON', button: 'RIGHT', isDown: false);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: _rightButtonDown ? accentColor : surfaceColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              'RIGHT CLICK',
              style: TextStyle(
                color: _rightButtonDown ? Colors.black : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: _swapLeftRightButtons
            ? [rightBtn, const SizedBox(width: 12), leftBtn]
            : [leftBtn, const SizedBox(width: 12), rightBtn],
      ),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sensitivity: ${_sensitivity.toStringAsFixed(1)}x', style: const TextStyle(color: Colors.white70)),
              Slider(
                value: _sensitivity,
                min: 0.8,
                max: 4.5,
                divisions: 10,
                activeColor: accentColor,
                onChanged: (val) {
                  setDialogState(() => _sensitivity = val);
                  setState(() => _sensitivity = val);
                  _saveSettings();
                },
              ),
              const Divider(color: Colors.white24),
              const Text('Scroll Buttons Position', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              DropdownButton<String>(
                value: _scrollPosition,
                isExpanded: true,
                dropdownColor: surfaceColor,
                style: const TextStyle(color: Colors.white),
                items: const [
                  DropdownMenuItem(value: 'bottom_right', child: Text('Bottom Right Corner')),
                  DropdownMenuItem(value: 'top_right', child: Text('Top Right Corner')),
                  DropdownMenuItem(value: 'bottom_left', child: Text('Bottom Left Corner')),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() => _scrollPosition = val);
                    setState(() => _scrollPosition = val);
                    _saveSettings();
                  }
                },
              ),
              const Divider(color: Colors.white24),
              SwitchListTile(
                title: const Text('Click Buttons on Top', style: TextStyle(color: Colors.white, fontSize: 14)),
                value: _buttonsOnTop,
                activeThumbColor: accentColor,
                onChanged: (val) {
                  setDialogState(() => _buttonsOnTop = val);
                  setState(() => _buttonsOnTop = val);
                  _saveSettings();
                },
              ),
              SwitchListTile(
                title: const Text('Swap Left / Right Click', style: TextStyle(color: Colors.white, fontSize: 14)),
                value: _swapLeftRightButtons,
                activeThumbColor: accentColor,
                onChanged: (val) {
                  setDialogState(() => _swapLeftRightButtons = val);
                  setState(() => _swapLeftRightButtons = val);
                  _saveSettings();
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done', style: TextStyle(color: accentColor)),
          ),
        ],
      ),
    );
  }
}
