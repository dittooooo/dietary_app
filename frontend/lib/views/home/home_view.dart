import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../color/app_colors.dart';
import '../records/elf_feeding_page.dart';

class HomeView extends StatefulWidget {
  final bool initialOpenChat;
  const HomeView({super.key, this.initialOpenChat = false});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with TickerProviderStateMixin {
  final TextEditingController _inputController = TextEditingController();
  final AuthService _authService = AuthService();
  
  late bool _isChatOpen;
  late double _chatPanelX; 
  String _userNickname = '使用者';
  String _petType = '奶油皮丘';
  
  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _isChatOpen = widget.initialOpenChat;
    _chatPanelX = widget.initialOpenChat ? 0.0 : 1.0;
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
      case '奶油皮丘': return const Color(0xFFD4A373); // Muted orange (retro)
      case '薄荷兔兔': return const Color(0xFF8A9A5B); // Muted sage (retro)
      case '草莓狐狸': return const Color(0xFFB07D62); // Muted terracotta (retro)
      default: return AppColors.secondary;
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
        if (text.contains("早午餐")) {
          _messages.add({
            'isElf': true, 
            'text': '嗨 $_userNickname！考慮到您目前的「減脂健康」目標，我為您挑選了幾項附近的早午餐推薦，這些選項的蛋白質含量較高且負擔相對較小喔：',
            'options': [
              {
                'name': '卡拉雞腿堡', 
                'nutrients': {'calories': 450, 'protein': 22, 'fat': 18, 'carbs': 48}
              },
              {
                'name': '鐵板麵', 
                'nutrients': {'calories': 520, 'protein': 14, 'fat': 22, 'carbs': 65}
              },
              {
                'name': '烏龍麵', 
                'nutrients': {'calories': 380, 'protein': 12, 'fat': 8, 'carbs': 60}
              },
            ]
          });
        } else if (text.contains("推薦")) {
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
                            BoxShadow(color: AppColors.primary.withOpacity(0.1), blurRadius: 5.85, spreadRadius: 1.95)
                          ],
                        ),
                        child: Icon(
                          _getPetIcon(_petType), 
                          size: 180, 
                          color: Colors.black
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
                        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.1), blurRadius: 1.95)],
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
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.05), blurRadius: 2.925, offset: const Offset(0, 0.975))],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        decoration: const InputDecoration(
                          hintText: "輸入訊息...", 
                          border: InputBorder.none,
                          hintStyle: TextStyle(color: AppColors.textPrimary)
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
                  return _buildChatMessage(msg['isElf'], msg['text'], options: msg['options']);
                },
              ),
            ),
            // 面板內也提供輸入框 (包含小精靈站位符)
            Stack(
              clipBehavior: Clip.none,
              children: [
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
                              hintStyle: TextStyle(color: AppColors.textPrimary)
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
                // 小精靈站位符 (趴在輸入框上方，放大並置中)
                Positioned(
                  top: -65,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _getPetColor(_petType).withOpacity(0.9),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.background, width: 3),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 4))
                        ],
                      ),
                      child: Icon(_getPetIcon(_petType), size: 64, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatMessage(bool isElf, String text, {List<dynamic>? options}) {
    return Align(
      alignment: isElf ? Alignment.centerLeft : Alignment.centerRight,
      child: Column(
        crossAxisAlignment: isElf ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            decoration: BoxDecoration(
              color: isElf ? AppColors.background : AppColors.secondary,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.05), blurRadius: 0.975)],
              border: isElf ? Border.all(color: AppColors.border) : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(color: isElf ? AppColors.textPrimary : AppColors.background, fontSize: 15),
                ),
                if (isElf && options != null) ...[
                  const SizedBox(height: 15),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  ...options.map((opt) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _showNutrientDetail(opt['name'], opt['nutrients']),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surface,
                          foregroundColor: AppColors.textPrimary,
                          elevation: 0,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(opt['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  )).toList(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showNutrientDetail(String name, Map<String, dynamic> nutrients) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.45,
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 25),
            Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            Text("預估攝取熱量: ${nutrients['calories']} kcal", style: const TextStyle(fontSize: 16, color: AppColors.secondary, fontWeight: FontWeight.w600)),
            const Divider(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NutrientInfo(label: "蛋白質", value: "${nutrients['protein']}", unit: "g"),
                _NutrientInfo(label: "脂肪", value: "${nutrients['fat']}", unit: "g"),
                _NutrientInfo(label: "碳水", value: "${nutrients['carbs']}", unit: "g"),
              ],
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // 關閉彈窗
                _toggleChat(false); // 關閉對話框
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ElfFeedingPage(
                      imagePath: "", 
                      items: [{'name': name, 'portion': '1份', 'calories': '${nutrients['calories']} kcal'}],
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 2,
              ),
              child: const Text("確認食用", style: TextStyle(color: AppColors.background, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
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
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.05), blurRadius: 1.95)],
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
          const Text("點擊查看詳細地址與評價", style: TextStyle(color: AppColors.textPrimary, fontSize: 12)),
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
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2.925)],
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
        Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        Text(unit, style: const TextStyle(fontSize: 10, color: AppColors.textPrimary)),
      ],
    );
  }
}
