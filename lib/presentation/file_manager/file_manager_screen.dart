import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import '../../data/repositories/local_network_repository.dart';

class FileManagerScreen extends StatefulWidget {
  final LocalNetworkRepository networkRepository;

  const FileManagerScreen({super.key, required this.networkRepository});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  StreamSubscription? _subscription;
  String _currentPath = '';
  final List<String> _navigationStack = [];
  List<dynamic> _fileItems = [];
  bool _isLoading = false;

  bool _isTransferring = false;
  double _uploadProgress = 0.0;
  String _transferStatus = '';

  // Theme Constants matching pcmouse brand
  static const backgroundColor = Color(0xFF0D1117);
  static const surfaceColor = Color(0xFF161B22);
  static const cardColor = Color(0xFF21262D);
  static const accentColor = Color(0xFF00E5FF);
  static const folderColor = Color(0xFFFFB74D);
  static const fileColor = Color(0xFF80D8FF);

  @override
  void initState() {
    super.initState();
    _subscription = widget.networkRepository.messageStream.listen((data) {
      final type = data['type'] as String?;
      if (type == 'FILE_LIST_RESP') {
        final payload = data['payload'] as Map<String, dynamic>?;
        if (payload != null && mounted) {
          setState(() {
            _currentPath = (payload['path'] ?? payload['Path'] ?? '') as String;
            _fileItems = (payload['items'] ?? payload['Items'] as List<dynamic>?) ?? [];
            _isLoading = false;
          });
        }
      }
    });

    _loadDirectory('');
  }

  void _loadDirectory(String path, {bool pushToStack = false}) {
    if (pushToStack && _currentPath.isNotEmpty) {
      _navigationStack.add(_currentPath);
    }
    setState(() => _isLoading = true);
    widget.networkRepository.sendFrame(
      type: 'FILE_LIST_REQ',
      payload: {'path': path},
    );
  }

  bool _navigateBack() {
    if (_navigationStack.isNotEmpty) {
      String previousPath = _navigationStack.removeLast();
      _loadDirectory(previousPath, pushToStack: false);
      return true;
    }
    return false;
  }

  Future<void> _pickAndUploadFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.single.path == null) return;

    File file = File(result.files.single.path!);
    String fileName = result.files.single.name;
    int fileSize = await file.length();

    setState(() {
      _isTransferring = true;
      _uploadProgress = 0.0;
      _transferStatus = 'Computing SHA-256 hash...';
    });

    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes);
    String checksum = digest.toString().toUpperCase();

    setState(() {
      _transferStatus = 'Starting transfer to PC...';
    });

    final startCompleter = Completer<String>();
    late StreamSubscription startSub;
    startSub = widget.networkRepository.messageStream.listen((msg) {
      if (msg['type'] == 'FILE_TRANSFER_START_RESP') {
        final payload = msg['payload'] as Map<String, dynamic>?;
        if (payload != null && (payload['success'] == true || payload['Success'] == true)) {
          startCompleter.complete((payload['transferId'] ?? payload['TransferId'] ?? '') as String);
        } else {
          startCompleter.complete('');
        }
        startSub.cancel();
      }
    });

    widget.networkRepository.sendFrame(
      type: 'FILE_TRANSFER_START',
      payload: {
        'fileName': fileName,
        'destFolder': _currentPath,
        'fileSizeBytes': fileSize,
        'checksum': checksum,
      },
    );

    String transferId = await startCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        startSub.cancel();
        return '';
      },
    );

    if (transferId.isEmpty) {
      if (mounted) {
        setState(() => _isTransferring = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File upload start rejected by PC.'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    const chunkSize = 64 * 1024;
    int totalChunks = (fileSize / chunkSize).ceil();
    if (totalChunks == 0) totalChunks = 1;

    for (int i = 0; i < totalChunks; i++) {
      int start = i * chunkSize;
      int end = (start + chunkSize < fileSize) ? start + chunkSize : fileSize;

      List<int> chunkBytes = bytes.sublist(start, end);
      String base64Chunk = base64Encode(chunkBytes);

      widget.networkRepository.sendFrame(
        type: 'FILE_TRANSFER_CHUNK',
        payload: {
          'transferId': transferId,
          'chunkBase64': base64Chunk,
        },
      );

      if (mounted) {
        setState(() {
          _uploadProgress = (i + 1) / totalChunks;
          _transferStatus = 'Uploading... ${(_uploadProgress * 100).toInt()}%';
        });
      }

      await Future.delayed(const Duration(milliseconds: 10));
    }

    widget.networkRepository.sendFrame(
      type: 'FILE_TRANSFER_COMPLETE',
      payload: {'transferId': transferId},
    );

    if (mounted) {
      setState(() {
        _isTransferring = false;
        _transferStatus = 'File transfer complete!';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Uploaded $fileName successfully!'), backgroundColor: Colors.green),
      );

      _loadDirectory(_currentPath);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String folderTitle = _currentPath.isEmpty
        ? 'PC Drives'
        : _currentPath.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).last;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        bool handledLocally = _navigateBack();
        if (!handledLocally) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: surfaceColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
            onPressed: () {
              bool handledLocally = _navigateBack();
              if (!handledLocally) {
                Navigator.of(context).pop();
              }
            },
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                folderTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              if (_currentPath.isNotEmpty)
                Text(
                  _currentPath,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.upload_file_rounded, color: accentColor),
              tooltip: 'Upload File to PC',
              onPressed: _isTransferring ? null : _pickAndUploadFile,
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              onPressed: () => _loadDirectory(_currentPath),
            ),
          ],
        ),
        body: Column(
          children: [
            // Breadcrumb Bar
            if (_currentPath.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: cardColor,
                child: Row(
                  children: [
                    const Icon(Icons.folder_copy_rounded, color: folderColor, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentPath,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

            // Animated Upload Card
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: _isTransferring ? 80 : 0,
              curve: Curves.easeInOut,
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _transferStatus,
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                          Text(
                            '${(_uploadProgress * 100).toInt()}%',
                            style: const TextStyle(color: accentColor, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _uploadProgress,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation<Color>(accentColor),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // File List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
                      ),
                    )
                  : _fileItems.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: _fileItems.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            final item = _fileItems[index] as Map<String, dynamic>;
                            final name = (item['name'] ?? item['Name'] ?? 'Unknown') as String;
                            final path = (item['path'] ?? item['Path'] ?? '') as String;
                            final isDir = (item['isDirectory'] ?? item['IsDirectory'] ?? false) as bool;
                            final sizeBytes = (item['sizeBytes'] ?? item['SizeBytes'] ?? 0) as int;

                            return _buildFileItem(
                              name: name,
                              isDir: isDir,
                              sizeBytes: sizeBytes,
                              onTap: () {
                                if (isDir) _loadDirectory(path, pushToStack: true);
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileItem({
    required String name,
    required bool isDir,
    required int sizeBytes,
    required VoidCallback onTap,
  }) {
    String sizeStr = isDir
        ? '--'
        : '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';

    return Material(
      color: Colors.transparent,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: Colors.transparent,
        hoverColor: Colors.white10,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDir ? folderColor.withValues(alpha: 0.15) : fileColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isDir ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
            color: isDir ? folderColor : fileColor,
            size: 24,
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          sizeStr,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open_rounded, size: 64, color: Colors.white24),
          SizedBox(height: 16),
          Text(
            'This folder is empty',
            style: TextStyle(color: Colors.white38, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
