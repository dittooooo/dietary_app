import 'package:flutter/material.dart';
import '../home/home_page.dart';
import '../auth/profile_page.dart';

class ReportPage extends StatelessWidget {
  final DateTime date;
  const ReportPage({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // 1. 頂部導覽列 (規格與其他頁面完全統一)
              Container(
                height: 100,
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios, size: 28),
                    ),
                    const Text(
                      '趨勢報告',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
                          border: Border.all(color: Colors.black, width: 2),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 15, offset: const Offset(0, 8))
                          ],
                        ),
                        child: const CircleAvatar(
                          radius: 25,
                          backgroundColor: Colors.white,
                          child: Icon(Icons.person, color: Colors.grey, size: 35),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. 日/月/年 切換與圖表區
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black, width: 2),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('日 | 月 | 年', style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(width: 10),
                        Icon(Icons.calendar_today_outlined, size: 20),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 150,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: MockLineChartPainter(),
                      ),
                    ),
                    const Divider(color: Colors.black, thickness: 1.5),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [Text('8/13'), Text('8/14'), Text('8/15')],
                    )
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 3. 小精靈展示舞台
              Column(
                children: [
                  const Text('小精靈目前狀態', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 200, height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: const BorderRadius.all(Radius.elliptical(100, 20)),
                          border: Border.all(color: Colors.black),
                        ),
                      ),
                      const Positioned(
                        bottom: 10,
                        child: Icon(Icons.pets, size: 80, color: Colors.orange), 
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // 4. 總結數據卡片
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.black, width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('總結數據：', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Container(
                          width: 100, height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black, width: 2),
                            gradient: const SweepGradient(
                              colors: [Colors.orange, Colors.blue, Colors.green],
                              stops: [0.3, 0.7, 1.0],
                            ),
                          ),
                        ),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('· 熱量：1200 kcal'),
                            Text('· 蛋白質：60g'),
                            Text('· 碳水：150g'),
                            Text('· 脂肪：40g'),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        selectedItemColor: Colors.deepPurple,
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
    final paint = Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 2.0;
    final path = Path();
    path.moveTo(0, size.height * 0.8);
    path.lineTo(size.width * 0.3, size.height * 0.6);
    path.lineTo(size.width * 0.6, size.height * 0.4);
    path.lineTo(size.width, size.height * 0.2);
    canvas.drawPath(path, paint);
    final dotPaint = Paint()..color = Colors.black;
    canvas.drawCircle(Offset(0, size.height * 0.8), 4, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.3, size.height * 0.6), 4, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.6, size.height * 0.4), 4, dotPaint);
    canvas.drawCircle(Offset(size.width, size.height * 0.2), 4, dotPaint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
