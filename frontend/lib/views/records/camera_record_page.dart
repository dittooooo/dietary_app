import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'elf_feeding_page.dart';

class CameraRecordPage extends StatefulWidget {
  const CameraRecordPage({super.key});

  @override
  State<CameraRecordPage> createState() => _CameraRecordPageState();
}

enum RecordStage { shooting, recognizing, result }

class _CameraRecordPageState extends State<CameraRecordPage> with TickerProviderStateMixin {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;
  RecordStage _currentStage = RecordStage.shooting;
  XFile? _capturedImage;
  
  // 動畫相關
  late AnimationController _elfAnimController;
  late Animation<Offset> _elfPosition;
  late AnimationController _scanningController;

  // 辨識結果模擬數據
  final List<Map<String, dynamic>> _detectedItems = [
    {'name': '茶葉蛋', 'x': 0.3, 'y': 0.4, 'portion': '1 顆', 'calories': '75 kcal'},
    {'name': '豆漿', 'x': 0.7, 'y': 0.5, 'portion': '300 ml', 'calories': '120 kcal'},
  ];

  @override
  void initState() {
    super.initState();
    _initCamera();
    
    _elfAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _elfPosition = Tween<Offset>(
      begin: const Offset(1.5, 0.0), // 從右側外面進來
      end: const Offset(0.0, 0.0),
    ).animate(CurvedAnimation(parent: _elfAnimController, curve: Curves.elasticOut));

    _scanningController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _elfAnimController.forward();
  }

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
    super.dispose();
  }

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

  void _onCapture() async {
    try {
      await _initializeControllerFuture;
      final image = await _controller!.takePicture();
      setState(() {
        _capturedImage = image;
        _currentStage = RecordStage.recognizing;
      });
      
      // 模擬辨識過程
      Timer(const Duration(seconds: 3), () {
        setState(() {
          _currentStage = RecordStage.result;
        });
      });
    } catch (e) {
      debugPrint(e.toString());
    }
  }

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
                  'x': 0.5, // 默認位置
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

  void _deleteItem(int index) {
    setState(() {
      _detectedItems.removeAt(index);
    });
  }

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

          // 3. 掃描動畫 (僅在辨識階段顯示)
          if (_currentStage == RecordStage.recognizing) _buildScanningEffect(),

          // 4. 小精靈與對話框
          _buildElfOverlay(),

          // 5. 辨識標籤 (僅在結果階段顯示)
          if (_currentStage == RecordStage.result) ..._buildResultLabels(),

          // 6. 底部功能卡片或按鈕
          _buildBottomAction(),
        ],
      ),
    );
  }

  Widget _buildCameraView() {
    if (_currentStage == RecordStage.shooting) {
      return FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return Center(
              child: AspectRatio(
                aspectRatio: 1.0, // 正方形預覽
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
              const SizedBox(width: 48), // 平衡返回鍵
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanningEffect() {
    return Center(
      child: AspectRatio(
        aspectRatio: 1.0,
        child: AnimatedBuilder(
          animation: _scanningController,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue.withOpacity(0.3), width: 2),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: _scanningController.value * 300, // 模擬掃描線
                    left: 0, right: 0,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(color: Colors.blue.withOpacity(0.8), blurRadius: 10, spreadRadius: 2),
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

  Widget _buildElfOverlay() {
    String msg = "";
    if (_currentStage == RecordStage.shooting) msg = "我已經好多天\n沒吃蔬菜了";
    else if (_currentStage == RecordStage.recognizing) msg = "聞...好香\n好像是茶葉蛋";
    else msg = "這份子不錯，補充蛋白質";

    final screenHeight = MediaQuery.of(context).size.height;
    final bottomOffset = _currentStage == RecordStage.result ? (screenHeight * 0.5 + 10) : 120.0;

    return Positioned(
      bottom: bottomOffset,
      right: 20,
      child: SlideTransition(
        position: _elfPosition,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 對話框
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
              ),
              child: Text(msg, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 10),
            // 小精靈圖片 (目前用 Icon 代替，之後可換成 Image)
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.blue.shade100, width: 3),
              ),
              child: const Icon(Icons.pets, size: 50, color: Colors.blueGrey),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildResultLabels() {
    return _detectedItems.map((item) {
      return Positioned(
        left: MediaQuery.of(context).size.width * item['x'],
        top: MediaQuery.of(context).size.height * 0.3 + (MediaQuery.of(context).size.width * item['y']),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.8),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white70),
          ),
          child: Text(item['name'], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      );
    }).toList();
  }

  Widget _buildBottomAction() {
    if (_currentStage == RecordStage.result) {
      return Positioned(
        bottom: 0, left: 0, right: 0,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.5,
          decoration: const BoxDecoration(
            color: Color(0xFFF9F9F9),
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20)],
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 15),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 120), // 為下方按鈕留空間
                        child: Column(
                          children: [
                            // 原先的食物清單
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: EdgeInsets.zero,
                              itemCount: _detectedItems.length,
                              itemBuilder: (context, index) {
                                final item = _detectedItems[index];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text("份量: ${item['portion']} | 熱量: ${item['calories']}"),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _showEditDialog(index)),
                                      IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent), onPressed: () => _deleteItem(index)),
                                    ],
                                  ),
                                );
                              },
                            ),
                            // 新增按鈕
                            OutlinedButton.icon(
                              onPressed: _addNewItem,
                              icon: const Icon(Icons.add),
                              label: const Text("新增品項"),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 45),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              ),
                            ),
                            const SizedBox(height: 25),
                            // 營養資訊區
                            _buildNutritionSection(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 固定在底部的確認按鈕
              Positioned(
                bottom: 30, left: 0, right: 0,
                child: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ElfFeedingPage(
                            imagePath: _capturedImage!.path,
                            items: _detectedItems,
                          ),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(20),
                      elevation: 10,
                    ),
                    child: const Icon(Icons.check, color: Colors.white, size: 30),
                  ),
                ),
              ),
            ],
          ),
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
                backgroundColor: color.withOpacity(0.1),
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
}
