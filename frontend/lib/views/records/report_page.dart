import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math' as math;
import '../home/home_page.dart';
import '../auth/profile_page.dart';
import '../../color/app_colors.dart';

class ReportPage extends StatefulWidget {
  final DateTime date;
  const ReportPage({super.key, required this.date});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  int _viewType = 0; // 0: 今日, 1: 一週
  int? _hoveredIdx; // 用於追蹤圖表上被點擊/懸停的點

  // 假資料
  final List<double> _weeklyData = [1800, 2100, 1600, 1950, 1700, 2200, 1500];
  final List<double> _monthlyData = List.generate(30, (index) => 1500 + math.Random().nextDouble() * 1000);

  String get _viewLabel {
    if (_viewType == 1) return "本週";
    return "今日";
  }

  String get _dateDisplay {
    if (_viewType == 0) {
      return "${widget.date.year}年 ${widget.date.month.toString().padLeft(2, '0')}月 ${widget.date.day.toString().padLeft(2, '0')}日";
    } else {
      DateTime startDate = widget.date.subtract(const Duration(days: 6));
      return "${startDate.year}年 ${startDate.month.toString().padLeft(2, '0')}月 ${startDate.day.toString().padLeft(2, '0')}日 - ${widget.date.month.toString().padLeft(2, '0')}月 ${widget.date.day.toString().padLeft(2, '0')}日";
    }
  }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 100),
                  Text(_dateDisplay, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  if (_viewType == 0) ...[
                    const SizedBox(height: 20),
                    const Icon(Icons.pets, size: 250, color: Colors.black54),
                    const SizedBox(height: 10),
                    const Text("小精靈目前狀態：休息中", style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                  ],
                  const SizedBox(height: 30),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 227, 224, 224),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2.925, offset: const Offset(0, 1.56)),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(onTap: () => setState(() { _viewType = 0; _hoveredIdx = null; }), child: _buildTabButton("日", _viewType == 0)),
                            GestureDetector(onTap: () => setState(() { _viewType = 1; _hoveredIdx = null; }), child: _buildTabButton("週", _viewType == 1)),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _viewType == 0 ? _buildTodayStats() : _buildTrendChart(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 2.5 總結數據區域 (僅限週/月)
                  if (_viewType != 0) ...[
                    _buildAggregatedStats(),
                    const SizedBox(height: 20),
                  ],
                  
                  // 3. 總結數據卡片
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 208, 231, 192),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2.925, offset: const Offset(0, 1.56)),
                      ]
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("${_viewLabel}總結", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        const SizedBox(height: 10),
                        Text(
                          _viewType == 0 ? "您的攝取量穩定，建議增加膳食纖維。" : "${_viewLabel}攝取量穩定，繼續保持！", 
                          style: const TextStyle(color: AppColors.textPrimary)
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          // Header omitted for brevity in thought, but should be kept in full file
          _buildHeader(context),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey,
        backgroundColor: AppColors.background,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => HomePage(initialIndex: index)), (route) => false);
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '首頁'),
          BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '飲食紀錄'),
          BottomNavigationBarItem(icon: Icon(Icons.account_circle), label: '個人首頁'),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Positioned(
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
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_ios, size: 28)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() { _viewType = (_viewType + 1) % 2; _hoveredIdx = null; }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
                          child: Text(_viewLabel, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text('趨勢報告', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary, letterSpacing: 1.2)),
                    ],
                  ),
                  _buildProfileAvatar(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileAvatar(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const ProfilePage(returnIndex: 1)), (route) => false),
      child: Container(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 2.925, offset: const Offset(0, 1.56))]),
        child: const CircleAvatar(radius: 25, backgroundColor: AppColors.background, child: Icon(Icons.person, color: AppColors.textPrimary, size: 35)),
      ),
    );
  }

  // --- 總結數據區域 (週/月) ---
  Widget _buildAggregatedStats() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 248, 242, 191), // 鵝黃色背景
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2.925, offset: const Offset(0, 1.56)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("總結數據", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 25),
          
          // 1. 先顯示分段比例進度條
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 40,
              child: Row(
                children: [
                  Expanded(flex: 13, child: Container(color: Colors.orange, child: const Center(child: Text("早餐", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))))),
                  Expanded(flex: 31, child: Container(color: Colors.green, child: const Center(child: Text("午餐", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))))),
                  Expanded(flex: 43, child: Container(color: Colors.blue, child: const Center(child: Text("晚餐", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))))),
                  Expanded(flex: 13, child: Container(color: Colors.grey, child: const Center(child: Text("其他", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))))),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 30),

          // 2. 後顯示條列式詳細數據
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: const [
              Padding(
                padding: EdgeInsets.only(right: 4),
                child: Text("千卡", style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 5),
          _buildDetailRow("早餐", "(13%)", "1989", Colors.orange),
          const SizedBox(height: 12),
          _buildDetailRow("午餐", "(31%)", "4842", Colors.green),
          const SizedBox(height: 12),
          _buildDetailRow("晚餐", "(43%)", "6776", Colors.blue),
          const SizedBox(height: 12),
          _buildDetailRow("其他", "(13%)", "2000", Colors.grey),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String percentage, String calories, Color color) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        SizedBox(width: 50, child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
        const SizedBox(width: 10),
        Text(percentage, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
        const Spacer(),
        Text(calories, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      ],
    );
  }

  Widget _buildTodayStats() {
    int current = 1500;
    int target = 2000;
    double progress = (current / target).clamp(0.0, 1.0);
    Color progressColor = progress >= 1.0 ? AppColors.danger : (progress >= 0.8 ? Colors.orange : Colors.green);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Align(alignment: Alignment.centerLeft, child: const Text("總結數據", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("卡路里", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Text("今日攝取: $current / $target", style: const TextStyle(fontSize: 12))]),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, constraints) {
          final double fullWidth = constraints.maxWidth;
          final double progressWidth = fullWidth * progress;
          return Container(height: 35, width: fullWidth, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
            child: Stack(children: [if (progressWidth > 0) Container(width: progressWidth, height: 35, decoration: BoxDecoration(color: progressColor, borderRadius: BorderRadius.circular(8)), child: ClipRRect(borderRadius: BorderRadius.circular(8), child: CustomPaint(painter: DiagonalLinesPainter(color: Colors.white.withOpacity(0.25)))))]));
        }),
        const SizedBox(height: 40),
        Align(alignment: Alignment.centerLeft, child: const Text("三大營養素", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        const SizedBox(height: 30),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [SizedBox(width: 220, height: 220, child: CustomPaint(painter: NutrientPiePainter())), const SizedBox(width: 30), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_buildNutrientLegendItem("脂肪", "54%", const Color(0xFFEF5350)), const SizedBox(height: 12), _buildNutrientLegendItem("碳水", "26%", const Color(0xFF42A5F5)), const SizedBox(height: 12), _buildNutrientLegendItem("蛋白質", "20%", const Color(0xFFFFA726))])]),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildNutrientLegendItem(String label, String value, Color color) {
    return Row(children: [Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 8), Text("$label $value", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary))]);
  }

  Widget _buildTrendChart() {
    List<double> data = _viewType == 1 ? _weeklyData : _monthlyData;
    if (data.isEmpty) return const SizedBox(height: 200, child: Center(child: Text("暫無資料")));

    double sum = 0;
    for (double v in data) {
      sum += v;
    }
    double avg = sum / data.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("平均攝取卡路里 ${avg.toInt()}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            return MouseRegion(
              onHover: (event) => _handleTouch(event.localPosition, constraints.maxWidth, data.length),
              onExit: (_) => setState(() => _hoveredIdx = null),
              child: GestureDetector(
                onPanUpdate: (details) => _handleTouch(details.localPosition, constraints.maxWidth, data.length),
                onTapDown: (details) => _handleTouch(details.localPosition, constraints.maxWidth, data.length),
                child: SizedBox(
                  height: 200,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: MockLineChartPainter(data: data, hoveredIdx: _hoveredIdx),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _handleTouch(Offset localPosition, double width, int count) {
    double step = width / (count - 1);
    int idx = (localPosition.dx / step).round().clamp(0, count - 1);
    setState(() { _hoveredIdx = idx; });
  }
}

class DiagonalLinesPainter extends CustomPainter {
  final Color color; DiagonalLinesPainter({required this.color});
  @override void paint(Canvas canvas, Size size) { final paint = Paint()..color = color..strokeWidth = 1.5; for (double i = -size.height; i < size.width; i += 8) { canvas.drawLine(Offset(i, size.height), Offset(i + size.height, 0), paint); } }
  @override bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class NutrientPiePainter extends CustomPainter {
  @override void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2); final radius = size.width / 2; final rect = Rect.fromCircle(center: center, radius: radius); final paint = Paint()..style = PaintingStyle.fill;
    const data = [{'label': '脂肪', 'value': 0.54, 'color': Color(0xFFEF5350)}, {'label': '蛋白質', 'value': 0.20, 'color': Color(0xFFFFA726)}, {'label': '碳水', 'value': 0.26, 'color': Color(0xFF42A5F5)}];
    double startAngle = -math.pi / 2;
    for (var item in data) {
      final sweepAngle = 2 * math.pi * (item['value'] as double); paint.color = item['color'] as Color; canvas.drawArc(rect, startAngle, sweepAngle, true, paint);
      final labelAngle = startAngle + sweepAngle / 2; final labelRadius = radius * 0.7; final x = center.dx + labelRadius * math.cos(labelAngle); final y = center.dy + labelRadius * math.sin(labelAngle);
      final textPainter = TextPainter(text: TextSpan(text: "${item['label']}\n${((item['value'] as double) * 100).toInt()}%", style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)), textAlign: TextAlign.center, textDirection: TextDirection.ltr);
      textPainter.layout(); textPainter.paint(canvas, Offset(x - textPainter.width / 2, y - textPainter.height / 2));
      startAngle += sweepAngle;
    }
    paint.color = AppColors.surface; canvas.drawCircle(center, radius * 0.3, paint); paint.style = PaintingStyle.stroke; paint.color = Colors.black12; paint.strokeWidth = 1; canvas.drawCircle(center, radius, paint);
  }
  @override bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class MockLineChartPainter extends CustomPainter {
  final List<double> data;
  final int? hoveredIdx;
  MockLineChartPainter({required this.data, this.hoveredIdx});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final double stepX = size.width / (data.length - 1);
    
    // 手動找出最大最小值，避免 reduce 報錯
    double maxVal = data[0];
    double minVal = data[0];
    for (double v in data) {
      if (v > maxVal) maxVal = v;
      if (v < minVal) minVal = v;
    }
    
    minVal = minVal * 0.8;
    final double range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    final paint = Paint()..color = Colors.blue.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 3.0;
    final path = Path();
    
    List<Offset> points = [];
    for (int i = 0; i < data.length; i++) {
      double x = i * stepX;
      double y = size.height - ((data[i] - minVal) / range * size.height);
      points.add(Offset(x, y));
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);

    final dotPaint = Paint()..color = AppColors.secondary;
    for (int i = 0; i < points.length; i++) {
      bool isHovered = hoveredIdx == i;
      canvas.drawCircle(points[i], isHovered ? 8 : 4, isHovered ? (Paint()..color = Colors.red) : dotPaint);
      
      if (isHovered) {
        final textPainter = TextPainter(
          text: TextSpan(text: data[i].toInt().toString(), style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold, backgroundColor: Colors.white70)),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(canvas, Offset(points[i].dx - textPainter.width / 2, points[i].dy - 25));
      }
    }
  }
  @override bool shouldRepaint(covariant MockLineChartPainter oldDelegate) => oldDelegate.hoveredIdx != hoveredIdx || oldDelegate.data != data;
}
