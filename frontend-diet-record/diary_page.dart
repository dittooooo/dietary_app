import 'package:flutter/material.dart';
import '../home/home_page.dart';
import '../auth/profile_page.dart';

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
      backgroundColor: const Color(0xFFFDF5FF),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildDateBar(dateStr),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1, selectedItemColor: Colors.deepPurple,
        onTap: (index) => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => HomePage(initialIndex: index)), (route) => false),
        items: const [BottomNavigationBarItem(icon: Icon(Icons.home), label: '首頁'), BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '飲食紀錄'), BottomNavigationBarItem(icon: Icon(Icons.person), label: '個人首頁')],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 100, padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios, size: 28)),
          const Text('日記', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          GestureDetector(
            onTap: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const ProfilePage(returnIndex: 1)), (route) => false),
            child: Container(
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 15, offset: const Offset(0, 8))]),
              child: const CircleAvatar(radius: 25, backgroundColor: Colors.white, child: Icon(Icons.person, color: Colors.grey, size: 35)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateBar(String dateStr) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: Colors.black, width: 2))),
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
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black, width: 2), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), offset: const Offset(4, 4))]),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    color: const Color(0xFFEEEEEE), padding: const EdgeInsets.only(right: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _buildActionBtn(Icons.edit, "編輯", Colors.blue, () => _showActionMsg("編輯", title)),
                        _buildActionBtn(Icons.image, "相片", Colors.orange, () => _showActionMsg("圖像", title)),
                        _buildActionBtn(Icons.delete, "刪除", Colors.red, () => _showActionMsg("刪除", title)),
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
                          width: 80, decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.black, width: 1.5))),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 30, color: Colors.orange), Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]),
                        ),
                        Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(isExpanded ? items.join("\n") : items.take(2).join("\n"), style: const TextStyle(fontSize: 18, height: 1.4)))),
                        Row(
                          children: [
                            if (needsExpansion) IconButton(icon: Icon(isExpanded ? Icons.arrow_drop_up : Icons.arrow_drop_down), onPressed: () { setState(() { if (isExpanded) _expandedMeals.remove(title); else _expandedMeals.add(title); }); }),
                            Container(width: 4, height: 40, margin: const EdgeInsets.only(right: 4), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
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
            decoration: const BoxDecoration(color: Color(0xFFF9F9F9), border: Border(left: BorderSide(color: Colors.black, width: 2), right: BorderSide(color: Colors.black, width: 2), bottom: BorderSide(color: Colors.black, width: 2))),
            child: Text(items.skip(2).join("\n"), style: const TextStyle(fontSize: 18, height: 1.5)),
          ),
      ],
    );
  }

  Widget _buildActionBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4), width: 50,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.1), border: Border.all(color: color)), child: Icon(icon, color: color, size: 20)), const SizedBox(height: 4), Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold))]),
      ),
    );
  }
}
