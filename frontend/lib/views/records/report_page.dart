import 'package:flutter/material.dart';
import 'dart:ui';
import '../home/home_page.dart';
import '../auth/profile_page.dart';
import '../../color/app_colors.dart';

class ReportPage extends StatelessWidget {
  final DateTime date;
  const ReportPage({super.key, required this.date});

  Widget _buildTabButton(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label, 
        style: TextStyle(
          color: isSelected ? AppColors.background : AppColors.textPrimary, 
          fontWeight: FontWeight.bold
        )
      ),
    );
  }

  Widget _buildIndicator(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        Text(label, style: const TextStyle(color: AppColors.textSecondary)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 內容區域
          Positioned.fill(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 100), // 預留標題列高度
                  // 1. 日/月/年 切換與圖表區
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildTabButton("日", true),
                            _buildTabButton("月", false),
                            _buildTabButton("年", false),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          height: 200,
                          width: double.infinity,
                          child: CustomPaint(painter: MockLineChartPainter()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 2. 攝取量指標
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildIndicator("蛋白質", "75g", Colors.blue),
                      _buildIndicator("碳水", "210g", Colors.blue),
                      _buildIndicator("脂肪", "55g", Colors.blue),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // 3. 總結數據卡片
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        ),
                      ]
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("本週總結", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        SizedBox(height: 10),
                        Text("您的攝取量穩定，建議增加膳食纖維。", style: TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          // 頂部固定標題列
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    height: 80, 
                    decoration: BoxDecoration(
                      color: AppColors.background.withOpacity(0.5),
                      border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back_ios, size: 28),
                        ),
                        const Text(
                          '趨勢報告',
                          style: TextStyle(
                            fontSize: 22, 
                            fontWeight: FontWeight.bold, 
                            color: AppColors.textPrimary, 
                            letterSpacing: 1.2
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (context) => const ProfilePage(returnIndex: 1)),
                              (route) => false,
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 15, offset: const Offset(0, 8))
                              ],
                            ),
                            child: const CircleAvatar(
                              radius: 25,
                              backgroundColor: AppColors.background,
                              child: Icon(Icons.person, color: AppColors.accent, size: 35),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        backgroundColor: AppColors.background,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => HomePage(initialIndex: index)),
            (route) => false,
          );
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '首頁'),
          BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '飲食紀錄'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '個人首頁'),
        ],
      ),
    );
  }
}

class MockLineChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    final path = Path();
    path.moveTo(0, size.height * 0.8);
    path.lineTo(size.width * 0.3, size.height * 0.6);
    path.lineTo(size.width * 0.6, size.height * 0.4);
    path.lineTo(size.width, size.height * 0.2);
    canvas.drawPath(path, paint);
    final dotPaint = Paint()..color = AppColors.secondary;
    canvas.drawCircle(Offset(0, size.height * 0.8), 4, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.3, size.height * 0.6), 4, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.6, size.height * 0.4), 4, dotPaint);
    canvas.drawCircle(Offset(size.width, size.height * 0.2), 4, dotPaint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
