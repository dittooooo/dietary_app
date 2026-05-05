import 'package:flutter/material.dart';
import 'dart:ui';
import '../home/home_page.dart';
import '../auth/profile_page.dart';
import '../../color/app_colors.dart';

class DiaryPage extends StatefulWidget {
  final DateTime date;
  const DiaryPage({super.key, required this.date});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  final Set<String> _expandedMeals = {};
  String? _swipedMeal;
  double _dragExtent = 0.0;

  void _showActionMsg(String action, String meal) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("正在執行 $meal 的 $action 功能"), duration: const Duration(seconds: 1), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    String dateStr = "${widget.date.year}年${widget.date.month}月${widget.date.day}日";

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          // 內容區域
          Positioned.fill(
            child: Column(
              children: [
                const SizedBox(height: 80), // 預留標題列高度
                _buildDateBar(dateStr),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    children: [
                      _buildMealCard("早餐", Icons.wb_sunny_outlined, ["無糖豆漿", "茶葉蛋", "全麥吐司", "奇異果"]),
                      const SizedBox(height: 15),
                      _buildMealCard("中餐", Icons.wb_sunny, ["雞肉飯糰"]),
                      const SizedBox(height: 15),
                      _buildMealCard("晚餐", Icons.nights_stay_outlined, ["燒肉便當"]),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 頂部固定標題列
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(child: _buildHeader(context)),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1, 
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        backgroundColor: AppColors.background,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => HomePage(initialIndex: index)), (route) => false),
        items: const [BottomNavigationBarItem(icon: Icon(Icons.home), label: '首頁'), BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '飲食紀錄'), BottomNavigationBarItem(icon: Icon(Icons.person), label: '個人首頁')],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            height: 80, 
            decoration: BoxDecoration(
              color: AppColors.background.withOpacity(0.5),
              border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
            ),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios, size: 28)),
                const Text(
                  '日記', 
                  style: TextStyle(
                    fontSize: 22, 
                    fontWeight: FontWeight.bold, 
                    color: AppColors.textPrimary, 
                    letterSpacing: 1.2
                  )
                ),
              GestureDetector(
                onTap: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const ProfilePage(returnIndex: 1)), (route) => false),
                child: Container(
                  decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 15, offset: const Offset(0, 8))]),
                  child: const CircleAvatar(radius: 25, backgroundColor: AppColors.background, child: Icon(Icons.person, color: AppColors.accent, size: 35)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateBar(String dateStr) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(child: Text(dateStr, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500))),
    );
  }

  Widget _buildMealCard(String title, IconData icon, List<String> items) {
    bool isExpanded = _expandedMeals.contains(title);
    bool isSwiped = _swipedMeal == title;
    bool needsExpansion = items.length > 2;

    return Column(
      children: [
        GestureDetector(
          // 支援拖拽與滑動雙模式
          onHorizontalDragUpdate: (details) {
            _dragExtent += details.delta.dx;
            if (_dragExtent < -5) setState(() => _swipedMeal = title);
            else if (_dragExtent > 5) setState(() => _swipedMeal = null);
          },
          onHorizontalDragEnd: (details) {
            _dragExtent = 0; // 重置拖動計量
            if (details.primaryVelocity! < -300) setState(() => _swipedMeal = title);
            else if (details.primaryVelocity! > 300) setState(() => _swipedMeal = null);
          },
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    color: const Color(0xFFEEEEEE), padding: const EdgeInsets.only(right: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _buildActionBtn(Icons.edit, "編輯", AppColors.secondary, () => _showActionMsg("編輯", title)),
                        _buildActionBtn(Icons.image, "相片", AppColors.accent, () => _showActionMsg("圖像", title)),
                        _buildActionBtn(Icons.delete, "刪除", AppColors.danger, () => _showActionMsg("刪除", title)),
                      ],
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250), curve: Curves.easeOutQuart,
                  left: isSwiped ? -180 : 0, right: isSwiped ? 180 : 0,
                  top: 0, bottom: 0,
                  child: Container(
                    color: Colors.white,
                    child: Row(
                      children: [
                        Container(
                          width: 80, decoration: BoxDecoration(border: Border(right: BorderSide(color: AppColors.border, width: 1.5))),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 30, color: AppColors.secondary), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary))]),
                        ),
                        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(isExpanded ? items.join("\n") : items.take(2).join("\n"), style: const TextStyle(fontSize: 18, height: 1.4, color: AppColors.textPrimary)))),
                        Row(
                          children: [
                            if (needsExpansion) IconButton(icon: Icon(isExpanded ? Icons.arrow_drop_up : Icons.arrow_drop_down, color: AppColors.textSecondary), onPressed: () { setState(() { if (isExpanded) _expandedMeals.remove(title); else _expandedMeals.add(title); }); }),
                            Container(width: 4, height: 40, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded && items.length > 2)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(items.skip(2).join("\n"), style: const TextStyle(fontSize: 18, height: 1.5, color: AppColors.textPrimary)),
          ),
      ],
    );
  }

  Widget _buildActionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4), width: 50,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.1)), child: Icon(icon, color: color, size: 20)), const SizedBox(height: 4), Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold))]),
      ),
    );
  }
}
