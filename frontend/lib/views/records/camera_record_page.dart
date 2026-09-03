import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'elf_feeding_page.dart';

/// 進階 AI 相機紀錄頁面 - 包含即時相機掃描、模擬 AI 食物辨識與結果確認
class CameraRecordPage extends StatefulWidget {
  const CameraRecordPage({super.key});

  @override
  State<CameraRecordPage> createState() => _CameraRecordPageState();
}

enum RecordStage { shooting, recognizing, result }

class _CameraRecordPageState extends State<CameraRecordPage>
    with TickerProviderStateMixin {
  // === 狀態宣告與相機/動畫控制器 ===
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  RecordStage _currentStage = RecordStage.shooting;
  XFile? _capturedImage;
  String _petType = '米粒(Mili)';
  String _dietGoal = '養生';

  // 動畫相關
  late AnimationController _elfAnimController;
  late AnimationController _scanningController;
  late AnimationController _hoverController;
  late Animation<double> _hoverScaleAnimation;
  late Animation<double> _hoverOffsetAnimation;

  // 辨識結果模擬數據
  final List<Map<String, dynamic>> _detectedItems = [
    {'name': '茶葉蛋', 'x': 0.3, 'y': 0.4, 'portion': '1 顆', 'calories': '75 kcal'},
    {'name': '豆漿', 'x': 0.7, 'y': 0.5, 'portion': '300 ml', 'calories': '120 kcal'},
  ];

  // === 生命週期與動畫初始化 ===

  @override
  void initState() {
    super.initState();
    _loadPetData();
    _initCamera();

    _elfAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scanningController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // 漂浮與呼吸微動畫
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

    _elfAnimController.forward();
  }

  Future<void> _loadPetData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _petType = '米粒(Mili)';
        _dietGoal = prefs.getString('user_diet_goal') ?? '養生';
      });
    }
  }

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

  // === 相機硬體初始化 ===
  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    _initializeControllerFuture = _controller!.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    _elfAnimController.dispose();
    _scanningController.dispose();
    _hoverController.dispose();
    super.dispose();
  }

  // === 輔助標籤與時間計算 ===
  String _getTimeLabel() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 11) return "早餐";
    if (hour >= 11 && hour < 17) return "中餐";
    return "晚餐";
  }

  String _getCurrentTime() {
    final now = DateTime.now();
    return "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
  }

  // === 拍照與模擬 AI 辨識流程 ===
  void _onCapture() async {
    try {
      await _initializeControllerFuture;
      final image = await _controller!.takePicture();
      setState(() {
        _capturedImage = image;
        _currentStage = RecordStage.recognizing;
      });

      // 模擬辨識過程 (加速至 0.3 秒)
      Timer(const Duration(milliseconds: 300), () {
        setState(() {
          _currentStage = RecordStage.result;
        });
      });
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  // 重構：暫留此方法供未來編輯功能使用 (標註 ignore: unused_element 避免 Flutter Analyze 警告)
  // ignore: unused_element
  void _showEditDialog(int index) {
    final item = _detectedItems[index];
    final nameController = TextEditingController(text: item['name']);
    final portionController = TextEditingController(text: item['portion']);
    final calorieController = TextEditingController(text: item['calories']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("編輯餐點資訊", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: "名稱")),
            TextField(controller: portionController, decoration: const InputDecoration(labelText: "份量")),
            TextField(controller: calorieController, decoration: const InputDecoration(labelText: "熱量")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _detectedItems[index] = {
                  'name': nameController.text,
                  'portion': portionController.text,
                  'calories': calorieController.text,
                  'x': item['x'],
                  'y': item['y'],
                };
              });
              Navigator.pop(context);
            },
            child: const Text("儲存"),
          ),
        ],
      ),
    );
  }

  // 重構：暫留此方法供未來新增餐點功能使用 (標註 ignore 避免分析警告)
  // ignore: unused_element
  void _addNewItem() {
    final nameController = TextEditingController();
    final portionController = TextEditingController();
    final calorieController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("新增餐點", style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: "名稱")),
            TextField(controller: portionController, decoration: const InputDecoration(labelText: "份量")),
            TextField(controller: calorieController, decoration: const InputDecoration(labelText: "熱量")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("取消")),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _detectedItems.add({
                  'name': nameController.text,
                  'portion': portionController.text,
                  'calories': calorieController.text,
                  'x': 0.5,
                  'y': 0.5,
                });
              });
              Navigator.pop(context);
            },
            child: const Text("新增"),
          ),
        ],
      ),
    );
  }

  // 重構：暫留此方法供未來刪除餐點功能使用 (標註 ignore 避免分析警告)
  // ignore: unused_element
  void _deleteItem(int index) {
    setState(() {
      _detectedItems.removeAt(index);
    });
  }

  // === UI 主畫面構建 ===
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 相機預覽或已拍攝圖片
          _buildCameraView(),

          // 2. 頂部狀態列
          _buildTopOverlay(),

          // 4. 小精靈與對話框
          _buildElfOverlay(),

          // 6. 底部功能卡片或按鈕
          _buildBottomAction(),
        ],
      ),
    );
  }

  // === 1. 相機預覽 / 照片預覽區域 ===
  Widget _buildCameraView() {
    if (_currentStage == RecordStage.shooting) {
      return FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Center(
              child: AspectRatio(
                aspectRatio: 1.0,
                child: CameraPreview(_controller!),
              ),
            );
          } else {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
        },
      );
    } else {
      return Center(
        child: AspectRatio(
          aspectRatio: 1.0,
          child: kIsWeb
              ? Image.network(_capturedImage!.path, fit: BoxFit.cover)
              : Image.file(File(_capturedImage!.path), fit: BoxFit.cover),
        ),
      );
    }
  }

  // === 2. 頂部狀態列 (時間、餐點標籤、返回按鈕) ===
  Widget _buildTopOverlay() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 28),
              ),
              Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.wb_sunny, color: Colors.orange, size: 20),
                      const SizedBox(width: 5),
                      Text(
                        _getTimeLabel(),
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Text(
                    _getCurrentTime(),
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  // 重構：暫留掃描動畫效果 Widget (標註 ignore 避免分析警告)
  // ignore: unused_element
  Widget _buildScanningEffect() {
    return Center(
      child: AspectRatio(
        aspectRatio: 1.0,
        child: AnimatedBuilder(
          animation: _scanningController,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                // Flutter 3.27+ 官方推薦寫法，替代已棄用的 withOpacity(0.3)
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3), width: 2),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: _scanningController.value * 300,
                    left: 0, right: 0,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        boxShadow: [
                          // Flutter 3.27+ 官方推薦寫法，替代已棄用的 withOpacity(0.8)
                          BoxShadow(color: Colors.blue.withValues(alpha: 0.8), blurRadius: 1.95, spreadRadius: 0.39),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // === 4. 小精靈對話框與動態頭像 ===
  Widget _buildElfOverlay() {
    String moodPrefix = "";
    if (_dietGoal.contains('減脂')) {
      moodPrefix = "【今日心情：輕盈活力】\n";
    } else if (_dietGoal.contains('增肌')) {
      moodPrefix = "【今日心情：能量滿滿】\n";
    } else {
      moodPrefix = "【今日心情：悠然舒暢】\n";
    }

    // 重構：補齊流程控制大括號 {}，並簡化字串插值 (移除多餘的大括號)
    String msg = "";
    if (_currentStage == RecordStage.shooting) {
      msg = "$moodPrefix我已經好多天\n沒吃蔬菜了";
    } else if (_currentStage == RecordStage.recognizing) {
      msg = "$moodPrefix聞...好香\n好像是茶葉蛋";
    } else {
      msg = "$moodPrefix這份子不錯，補充蛋白質";
    }

    final bottomOffset = _currentStage == RecordStage.result ? 140.0 : 120.0;

    return Positioned(
      bottom: bottomOffset,
      right: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 對話框
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            decoration: BoxDecoration(
              // Flutter 3.27+ 官方推薦寫法，替代已棄用的 withOpacity(0.9)
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 1.95)],
            ),
            child: Text(
              msg,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // 小精靈圖片 (高品質 3D 渲染圖 + 呼吸浮動微動畫)
          AnimatedBuilder(
            animation: _hoverController,
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, _hoverOffsetAnimation.value),
                child: Transform.scale(
                  scale: _hoverScaleAnimation.value,
                  child: Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.blue.shade100, width: 3),
                      boxShadow: [
                        BoxShadow(
                          // Flutter 3.27+ 官方推薦寫法，替代已棄用的 withOpacity(0.15)
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: ClipOval(
                      child: Padding(
                        padding: const EdgeInsets.all(5.0),
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

  // 重構：暫留辨識結果標籤 Widget (標註 ignore 避免分析警告)
  // ignore: unused_element
  List<Widget> _buildResultLabels() {
    return _detectedItems.map((item) {
      return Positioned(
        left: MediaQuery.of(context).size.width * item['x'],
        top: MediaQuery.of(context).size.height * 0.3 + (MediaQuery.of(context).size.width * item['y']),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            // Flutter 3.27+ 官方推薦寫法，替代已棄用的 withOpacity(0.8)
            color: Colors.blue.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white70),
          ),
          child: Text(item['name'], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      );
    }).toList();
  }

  // === 6. 底部操作區 (快門按鈕 / 重拍與確認按鈕) ===
  Widget _buildBottomAction() {
    if (_currentStage == RecordStage.result) {
      return Positioned(
        bottom: 40, left: 0, right: 0,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. 重拍按鈕 (維持原本相機按鈕樣式)
            GestureDetector(
              onTap: () {
                setState(() {
                  _currentStage = RecordStage.shooting;
                  _capturedImage = null;
                });
              },
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 5),
                ),
                child: Container(
                  margin: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt, color: Colors.black, size: 35),
                ),
              ),
            ),
            // 2. 確認按鈕 (在右側)
            Positioned(
              right: MediaQuery.of(context).size.width * 0.15,
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ElfFeedingPage(
                        imagePath: _capturedImage!.path,
                        items: _detectedItems,
                        recordDate: DateTime.now(),
                      ),
                    ),
                  );
                },
                child: Container(
                  width: 65, height: 65,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.blue.shade400, width: 4),
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.blue.shade400, shape: BoxShape.circle),
                    child: const Icon(Icons.check, color: Colors.white, size: 35),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Positioned(
      bottom: 40, left: 0, right: 0,
      child: Center(
        child: GestureDetector(
          onTap: _onCapture,
          child: Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 5),
            ),
            child: Container(
              margin: const EdgeInsets.all(5),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const Icon(Icons.camera_alt, color: Colors.black, size: 35),
            ),
          ),
        ),
      ),
    );
  }

  // 重構：暫留營養資訊圖表 Widget (標註 ignore 避免分析警告)
  // ignore: unused_element
  Widget _buildNutritionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text("營養資訊", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildCircularNutrient("195", "總熱量", Colors.blue, 0.45),
            _buildCircularNutrient("15.9g", "碳水", Colors.orange, 0.6),
            _buildCircularNutrient("21.2g", "蛋白質", Colors.green, 0.8),
            _buildCircularNutrient("8.5g", "脂肪", Colors.redAccent, 0.4),
          ],
        ),
      ],
    );
  }

  Widget _buildCircularNutrient(String value, String label, Color color, double percent) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 60, height: 60,
              child: CircularProgressIndicator(
                value: percent,
                strokeWidth: 5,
                // Flutter 3.27+ 官方推薦寫法，替代已棄用的 withOpacity(0.1)
                backgroundColor: color.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
} // 程式碼區塊或元件結構結束
