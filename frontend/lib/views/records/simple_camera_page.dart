import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../color/app_colors.dart';
import '../../utils/friendly_error_message.dart';

/// 簡易相機拍攝頁面 - 提供即時相機預覽、拍照上傳與精靈互動對話
class SimpleCameraPage extends StatefulWidget {
  const SimpleCameraPage({super.key});

  @override
  State<SimpleCameraPage> createState() => _SimpleCameraPageState();
}

class _SimpleCameraPageState extends State<SimpleCameraPage>
    with SingleTickerProviderStateMixin {
  // === 狀態宣告與相機/動畫控制器 ===
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  bool _isInitializing = true;
  String _errorMessage = '';
  String _petType = '米粒(Mili)';
  String _dietGoal = '養生';

  late AnimationController _hoverController;
  late Animation<double> _hoverScaleAnimation;
  late Animation<double> _hoverOffsetAnimation;

  // === 生命週期與動畫初始化 ===
  @override
  void initState() {
    super.initState();
    _loadPetData();
    _initCamera();

    // 柴犬頭像漂浮與呼吸微動畫
    _hoverController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _hoverScaleAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _hoverController, curve: Curves.easeInOut),
    );

    _hoverOffsetAnimation = Tween<double>(begin: -4.0, end: 4.0).animate(
      CurvedAnimation(parent: _hoverController, curve: Curves.easeInOut),
    );
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
    _hoverController.dispose();
    super.dispose();
  }

  // === 讀取使用者設定檔 ===
  Future<void> _loadPetData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _petType = '米粒(Mili)';
        _dietGoal = prefs.getString('user_diet_goal') ?? '養生';
      });
    }
  }

  // === 輔助方法：依據目標與心情取得精靈圖檔與對話文字 ===
  String _getPetImagePath(String petType, String dietGoal) {
    String path = 'assets/images/shiba_normal.png';
    if (dietGoal.contains('減脂')) {
      path = 'assets/images/shiba_fat.png';
    } else if (dietGoal.contains('增肌')) {
      path = 'assets/images/shiba_muscular.png';
    } else if (dietGoal.contains('養生')) {
      path = 'assets/images/shiba_thin.png';
    }
    return path;
  }

  String _getElfMood(String dietGoal) {
    if (dietGoal.contains('減脂')) {
      return "【今日心情：輕盈活力】\n加油！今天也要吃得健康輕盈喔！";
    } else if (dietGoal.contains('增肌')) {
      return "【今日心情：能量滿滿】\n衝啊！蛋白質補滿，肌肉長高高！";
    } else {
      return "【今日心情：悠然舒暢】\n溫補養生，吃出自然好氣色！";
    }
  }

  // === 右下角精靈對話框與頭像 Widget ===
  Widget _buildElfOverlay() {
    final String moodMsg = _getElfMood(_dietGoal);

    return Positioned(
      bottom: 140,
      right: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 今日心情對話框
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              // Flutter 3.27+ 官方推薦寫法，替代已棄用的 withOpacity(0.9)
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(15),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 3,
                  offset: Offset(0, 1.5),
                ),
              ],
            ),
            child: Text(
              moodMsg,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 小精靈頭像框 (呼吸浮動動畫)
          AnimatedBuilder(
            animation: _hoverController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _hoverOffsetAnimation.value),
                child: Transform.scale(
                  scale: _hoverScaleAnimation.value,
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      // Flutter 3.27+ 官方推薦寫法，替代已棄用的 withOpacity(0.8)
                      border: Border.all(
                        color: AppColors.secondary.withValues(alpha: 0.8),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          // Flutter 3.27+ 官方推薦寫法，替代已棄用的 withOpacity(0.2)
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Image.asset(
                          _getPetImagePath(_petType, _dietGoal),
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
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
        title: const Text('相機拍攝', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('重試', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        Column(
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
        ),
        _buildElfOverlay(),
      ],
    );
  }
}

