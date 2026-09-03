import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../home/home_page.dart';
import 'diary_page.dart';
import '../../core/api_client.dart';
import '../../controllers/dog_state_controller.dart';
import '../../widgets/dog_avatar.dart';
import '../../color/app_colors.dart';

/// 精靈餵食動畫頁面 - 當使用者新增飲食紀錄後，展示小精靈用餐動畫與動態對話
class ElfFeedingPage extends StatefulWidget {
  final String imagePath;
  final List<Map<String, dynamic>> items;
  final DateTime? recordDate;

  const ElfFeedingPage({
    super.key,
    required this.imagePath,
    required this.items,
    this.recordDate,
  });

  @override
  State<ElfFeedingPage> createState() => _ElfFeedingPageState();
}

class _ElfFeedingPageState extends State<ElfFeedingPage>
    with TickerProviderStateMixin {
  // === 狀態宣告與動畫控制器 ===
  late AnimationController _elfController;
  late Animation<double> _elfScale;
  late Animation<Offset> _elfMove;
  bool _isEaten = false;
  final DogStateController _dogController = DogStateController.instance;

  // === 生命週期初始化與動畫設定 ===
  @override
  void initState() {
    super.initState();
    _loadPetData();
    _dogController.setState(DogAnimationState.eating);
    _elfController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    );

    // 小精靈入場滑動動畫
    _elfMove = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: const Offset(0, 0),
    ).animate(
      CurvedAnimation(
        parent: _elfController,
        curve: const Interval(0.0, 0.3, curve: Curves.easeOutBack),
      ),
    );

    // 小精靈縮放動畫
    _elfScale = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(
        parent: _elfController,
        curve: const Interval(0.3, 0.5, curve: Curves.elasticOut),
      ),
    );

    // 動畫結束後自動關閉並進入日誌頁
    _elfController.forward().then((_) {
      if (mounted) _goToDiary();
    });

    // 延遲 4 秒讓對話框與食物消失
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _isEaten = true);
    });
  }

  // === 讀取寵物/精靈體型設定 ===
  Future<void> _loadPetData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _dogController.setBodyTypeFromBackend(
          prefs.getString('dog_body_type') ?? prefs.getString('user_diet_goal'),
        );
      });
    }
  }

  // === 頁面導航 (跳轉回首頁並打開飲食日記頁) ===
  void _goToDiary() {
    final targetDate = widget.recordDate ?? DateTime.now();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => const HomePage(initialIndex: 1),
      ),
      (route) => false,
    );
    ApiClient.navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => DiaryPage(date: targetDate),
      ),
    );
  }

  @override
  void dispose() {
    _elfController.dispose();
    super.dispose();
  }

  // === UI 主體畫面構建 ===
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          // 1. 背景標題文字
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Transform.translate(
                  offset: const Offset(0, -250),
                  child: const Text(
                    "小精靈用餐中...",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),

          // 2. 小精靈動畫與用餐對話框
          Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: _elfMove,
              child: ScaleTransition(
                scale: _elfScale,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 310),
                  child: Transform.translate(
                    offset: const Offset(-10, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_isEaten)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: const Text(
                              "啊姆！看起來很好吃！",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: 180,
                          height: 180,
                          child: DogAvatar(
                            controller: _dogController,
                            instanceId: 'feeding-eating',
                            scale: 1.8,
                            cameraControls: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 3. 固定位置的「跳過動畫」按鈕
          Positioned(
            bottom: 165.0,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton.extended(
                onPressed: _goToDiary,
                label: const Text(
                  "跳過動畫 >>",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                // Flutter 3.27+ 官方推薦寫法，替代已棄用的 withOpacity(0.8)
                backgroundColor: AppColors.background.withValues(alpha: 0.8),
                foregroundColor: AppColors.textPrimary,
                elevation: 1.0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                extendedPadding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

