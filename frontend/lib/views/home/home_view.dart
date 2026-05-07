import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../color/app_colors.dart';
import '../records/elf_feeding_page.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with TickerProviderStateMixin {
  final TextEditingController _inputController = TextEditingController();
  final AuthService _authService = AuthService();
  
  bool _isChatOpen = false;
  double _chatPanelX = 1.0; 
  String _userNickname = '使用者';
  String _petType = '奶油皮丘';
  
  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadHomeData();
  }

  Future<void> _loadHomeData() async {
    // 1. 先從本地快取讀取 (前端輔助，速度快)
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userNickname = prefs.getString('user_nickname') ?? '使用者';
      _petType = prefs.getString('user_pet_type') ?? '奶油皮丘';
      _messages = [
        {'isElf': true, 'text': '嗨 $_userNickname！\n我是您的$_petType助理。\n可以在下方輸入框輸入\n你需要我提供的飲食建議喔！'},
      ];
    });

    // 2. 向後端請求最新資料 (後端為主，保持同步)
    final result = await _authService.getUserProfile();
    if (result['success'] == true) {
      final userData = result['data'];
      setState(() {
        _userNickname = userData['nickname'] ?? '使用者';
        _petType = userData['petType'] ?? '奶油皮丘';
        // 更新歡迎詞
        if (_messages.isNotEmpty && _messages[0]['isElf'] == true) {
          _messages[0]['text'] = '嗨 $_userNickname！\n我是您的$_petType助理。\n可以在下方輸入框輸入\n你需要我提供的飲食建議喔！';
        }
      });
    }
  }

  // 根據小精靈名稱獲取對應圖標
  IconData _getPetIcon(String petType) {
    switch (petType) {
      case '奶油皮丘': return Icons.pets;
      case '薄荷兔兔': return Icons.eco;
      case '草莓狐狸': return Icons.star;
      default: return Icons.pets;
    }
  }

  // 根據小精靈名稱獲取對應顏色
  Color _getPetColor(String petType) {
    switch (petType) {
      case '奶油皮丘': return Colors.orangeAccent;
      case '薄荷兔兔': return Colors.greenAccent;
      case '草莓狐狸': return Colors.pinkAccent;
      default: return Colors.blueGrey;
    }
  }

  void _toggleChat(bool open) {
    setState(() {
      _isChatOpen = open;
      _chatPanelX = open ? 0.0 : 1.0;
    });
  }

  void _handleMessage(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _messages.add({'isElf': false, 'text': text});
      _inputController.clear();
      _isChatOpen = true;
      _chatPanelX = 0.0;
    });

    // 模擬回覆
    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        if (text.contains("推薦")) {
          _messages.add({
            'isElf': true, 
            'text': '已為您搜尋附近的店家向您推薦：\n1. 佳佳\n2. 麥軒\n3. 日初',
            'type': 'restaurant'
          });
        } else if (text.contains("薯條")) {
          _messages.add({
            'isElf': true,
            'text': '薯條的營養成分如下：\n熱量: 380 kcal\n蛋白質: 4g\n脂肪: 20g',
            'type': 'nutrient'
          });
        } else {
          _messages.add({'isElf': true, 'text': '收到！我會根據您的需求提供最好的建議。'});
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx < -5) _toggleChat(true); // 左滑開啟
        if (details.delta.dx > 5) _toggleChat(false); // 右滑關閉
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Stack(
          children: [
            // 1. 背景與標題 (毛玻璃效果)
            Positioned(
              top: 0, left: 0, right: 0,
              child: SafeArea(
                child: Container(
                  height: 80,
                  alignment: Alignment.center,
                  child: const Text(
                    "精靈助手",
                    style: TextStyle(
                      fontSize: 22, 
                      fontWeight: FontWeight.bold, 
                      letterSpacing: 1.5,
                      color: AppColors.textPrimary
                    ),
                  ),
                ),
              ),
            ),

            // 2. 中央大精靈
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => _toggleChat(true),
                    child: Hero(
                      tag: 'elf',
                      child: Container(
                        width: 280, height: 280,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.background,
                          boxShadow: [
                            BoxShadow(color: AppColors.primary.withOpacity(0.1), blurRadius: 30, spreadRadius: 10)
                          ],
                        ),
                        child: Icon(
                          _getPetIcon(_petType), 
                          size: 180, 
                          color: AppColors.secondary
                        ), // 這裡之後換成完整精靈圖片
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 精靈說話框 (初始狀態)
                  if (!_isChatOpen)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.1), blurRadius: 10)],
                      ),
                      child: Text(
                        _messages.isNotEmpty ? _messages[0]['text'] : "載入中...",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16, 
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 3. 底部輸入框
            Positioned(
              bottom: 20, left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        decoration: const InputDecoration(
                          hintText: "輸入訊息...", 
                          border: InputBorder.none,
                          hintStyle: TextStyle(color: AppColors.textSecondary)
                        ),
                        onSubmitted: _handleMessage,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: AppColors.primary),
                      onPressed: () => _handleMessage(_inputController.text),
                    ),
                  ],
                ),
              ),
            ),

            // 4. 右側滑出的對話面板
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(
                MediaQuery.of(context).size.width * _chatPanelX, 0, 0
              ),
              child: _buildChatPanel(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatPanel() {
    return Container(
      width: MediaQuery.of(context).size.width,
      color: AppColors.background.withOpacity(0.98),
      child: SafeArea(
        child: Column(
          children: [
            // 對話面板頭部
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
                    onPressed: () => _toggleChat(false),
                  ),
                  const Text("與精靈對話", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(20),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final msg = _messages[index];
                  if (msg['type'] == 'restaurant') {
                    return _buildRestaurantCard(msg['text']);
                  } else if (msg['type'] == 'nutrient') {
                    return _buildNutrientCard();
                  }
                  return _buildChatMessage(msg['isElf'], msg['text']);
                },
              ),
            ),
            // 面板內也提供輸入框
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
                      child: TextField(
                        controller: _inputController,
                        decoration: const InputDecoration(
                          hintText: "詢問建議...", 
                          border: InputBorder.none,
                          hintStyle: TextStyle(color: AppColors.textSecondary)
                        ),
                        onSubmitted: _handleMessage,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: AppColors.background, size: 20),
                      onPressed: () => _handleMessage(_inputController.text),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatMessage(bool isElf, String text) {
    return Align(
      alignment: isElf ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        decoration: BoxDecoration(
          color: isElf ? AppColors.background : AppColors.secondary,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.05), blurRadius: 5)],
          border: isElf ? Border.all(color: AppColors.border) : null,
        ),
        child: Text(
          text,
          style: TextStyle(color: isElf ? AppColors.textPrimary : AppColors.background, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildRestaurantCard(String text) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant, color: AppColors.secondary),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary))),
            ],
          ),
          const SizedBox(height: 10),
          const Text("點擊查看詳細地址與評價", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildNutrientCard() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15)],
      ),
      child: Column(
        children: [
          const Text("薯條 (大份)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Divider(height: 30),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _NutrientInfo(label: "熱量", value: "380", unit: "kcal"),
              _NutrientInfo(label: "蛋白質", value: "4", unit: "g"),
              _NutrientInfo(label: "脂肪", value: "20", unit: "g"),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ElfFeedingPage(
                    imagePath: "", // 這裡可以用預設圖片
                    items: [{'name': '薯條', 'portion': '大份', 'calories': '380 kcal'}],
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              minimumSize: const Size(double.infinity, 45),
            ),
            child: const Text("進行餵食", style: TextStyle(color: AppColors.background, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _NutrientInfo extends StatelessWidget {
  final String label, value, unit;
  const _NutrientInfo({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(unit, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}
