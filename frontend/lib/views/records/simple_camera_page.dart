import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../color/app_colors.dart';
import '../../utils/friendly_error_message.dart';

/// 簡易相機拍攝頁面 - 提供即時相機預覽與拍照上傳
class SimpleCameraPage extends StatefulWidget {
  const SimpleCameraPage({super.key});

  @override
  State<SimpleCameraPage> createState() => _SimpleCameraPageState();
}

class _SimpleCameraPageState extends State<SimpleCameraPage> {
  // === 狀態宣告與相機控制器 ===
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  bool _isInitializing = true;
  String _errorMessage = '';

  // === 生命週期與相機初始化 ===
  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  // === 相機設備初始化 (優先選用後置鏡頭) ===
  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _errorMessage = '找不到相機設備';
          _isInitializing = false;
        });
        return;
      }

      CameraDescription selectedCamera = cameras.first;
      for (var camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.back) {
          selectedCamera = camera;
          break;
        }
      }

      _controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      _initializeControllerFuture = _controller!.initialize();
      await _initializeControllerFuture;

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = FriendlyErrorMessage.camera;
          _isInitializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // === 拍照動作邏輯 ===
  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      final XFile image = await _controller!.takePicture();
      if (mounted) {
        Navigator.pop(context, image);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(FriendlyErrorMessage.camera)),
        );
      }
    }
  }

  // === UI 主畫面構建 ===
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '相機拍攝',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  // === 相機預覽區域與快門按鈕卡片 ===
  Widget _buildBody() {
    if (_isInitializing) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.danger, size: 60),
              const SizedBox(height: 15),
              Text(
                _errorMessage,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isInitializing = true;
                    _errorMessage = '';
                  });
                  _initCamera();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('重試', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio / 2,
              child: CameraPreview(_controller!),
            ),
          ),
        ),
        Container(
          height: 120,
          color: Colors.black,
          child: Center(
            child: GestureDetector(
              onTap: _takePicture,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                ),
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

