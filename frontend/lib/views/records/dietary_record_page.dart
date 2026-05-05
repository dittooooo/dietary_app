import 'package:flutter/material.dart';
import 'dart:ui';
import '../home/home_page.dart';
import '../auth/profile_page.dart';
import 'diary_page.dart';
import 'report_page.dart';
import 'camera_record_page.dart';
import 'dart:math' as math;
import '../../color/app_colors.dart';

class DietaryRecordPage extends StatefulWidget {
  const DietaryRecordPage({super.key});

  @override
  State<DietaryRecordPage> createState() => _DietaryRecordPageState();
}

class _DietaryRecordPageState extends State<DietaryRecordPage> {
  final ScrollController _scrollController = ScrollController();
  bool _showBackToToday = false;
  DateTime _selectedDate = DateTime.now(); 
  bool _showOverlay = false;
  DateTime? _rippleDate; 

  final List<DateTime> _pathDates = List.generate(100, (i) => DateTime.now().subtract(Duration(days: i)));

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.offset > 200 && !_showBackToToday) {
        setState(() => _showBackToToday = true);
      } else if (_scrollController.offset <= 200 && _showBackToToday) {
        setState(() => _showBackToToday = false);
      }
    });
  }

  void _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: AppColors.primary, onPrimary: AppColors.background, onSurface: AppColors.textPrimary)),
        child: child!,
      ),
    );
    if (picked != null) _scrollToDate(picked);
  }

  void _scrollToDate(DateTime date) {
    int daysDiff = DateTime.now().difference(date).inDays;
    if (daysDiff < 0) daysDiff = 0;
    
    int segmentIndex = (daysDiff / 5).floor();
    // 壓縮後的高度為 110。
    // 公式：Padding 250 + 圓點在 List 中的位置 30 - 目標螢幕座標 280 = segmentIndex * 110
    double adjustedOffset = segmentIndex * 110.0;
    
    if (adjustedOffset < 0) adjustedOffset = 0;
    
    setState(() {
      _selectedDate = date;
      _rippleDate = date;
      _showOverlay = true;
    });

    Future.microtask(() {
      if (mounted) {
        _scrollController.animateTo(
          adjustedOffset,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutQuart,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    const double margin = 20.0;
    const double radius = 50.0;
    final double pathWidth = screenWidth - (margin * 2) - (radius * 2);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Stack(
          children: [
            // 1. 路徑區 (高度壓縮至 110)
            Positioned.fill(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.only(top: 250, bottom: 200), 
                itemCount: 20,
                itemBuilder: (context, index) => _buildSPathSegment(index, pathWidth, margin),
              ),
            ),

            if (_showOverlay)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() { _showOverlay = false; _rippleDate = null; }),
                  behavior: HitTestBehavior.translucent,
                  child: Container(color: Colors.black.withOpacity(0.3)),
                ),
              ),

            _buildFixedHeader(context),
            _buildFeatureRow(),

            if (_showOverlay)
              Positioned(bottom: 0, left: 0, right: 0, child: _buildActionPanel(context)),

            // 「回今天」按鈕 (中文 + 雙箭頭)
            if (_showBackToToday)
              Positioned(
                right: 20,
                bottom: _showOverlay ? MediaQuery.of(context).size.height * 0.35 + 20 : 100,
                child: GestureDetector(
                  onTap: () => _scrollToDate(DateTime.now()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.keyboard_double_arrow_up, color: Colors.white, size: 20),
                        SizedBox(width: 4),
                        Text('回今天', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFixedHeader(BuildContext context) {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            height: 80, // 與個人首頁高度一致
            decoration: BoxDecoration(
              color: AppColors.background.withOpacity(0.7),
              border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const HomePage(initialIndex: 0)), 
                    (route) => false
                  ), 
                  icon: const Icon(Icons.arrow_back_ios, size: 28)
                ),
                const Text(
                  '飲食紀錄', 
                  style: TextStyle(
                    fontSize: 22, 
                    fontWeight: FontWeight.bold, 
                    color: AppColors.textPrimary, 
                    letterSpacing: 1.2
                  )
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ProfilePage(returnIndex: 1))),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle, 
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2), 
                          blurRadius: 15, 
                          offset: const Offset(0, 8)
                        )
                      ]
                    ),
                    child: const CircleAvatar(
                      radius: 25, 
                      backgroundColor: AppColors.background, 
                      child: Icon(Icons.person, color: AppColors.accent, size: 35)
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow() {
    return Positioned(
      top: 80, left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: _selectDate,
              child: Container(
                width: 60, height: 80,
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.2), blurRadius: 10, offset: const Offset(4, 6))]),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Text('月', style: TextStyle(fontSize: 14)), Text('${_selectedDate.day}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))]),
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CameraRecordPage())),
              child: Transform.translate(
                offset: const Offset(15, 0),
                child: Container(
                  width: 160, height: 70,
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.5), blurRadius: 15, offset: const Offset(0, 10))]),
                  child: const Icon(Icons.camera_alt, color: AppColors.background, size: 40),
                ),
              ),
            ),
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.1), blurRadius: 5, offset: const Offset(2, 2))]),
                  child: const Text('今天還沒記錄\n好餓喔...', style: TextStyle(fontSize: 10, color: AppColors.textPrimary), textAlign: TextAlign.center),
                ),
                const SizedBox(height: 5),
                const Icon(Icons.terrain, color: AppColors.accent, size: 25),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionPanel(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.35,
      decoration: const BoxDecoration(color: AppColors.secondary, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Text("${_selectedDate.month}月${_selectedDate.day}日 飲食記錄", style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 50),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _buildMenuButton(title: "日記", icon: Icons.restaurant, color: AppColors.background, onTap: () { setState(() => _showOverlay = false); Navigator.push(context, MaterialPageRoute(builder: (context) => DiaryPage(date: _selectedDate))); }),
              _buildMenuButton(title: "報告", icon: Icons.assignment_outlined, color: AppColors.border, onTap: () { setState(() => _showOverlay = false); Navigator.push(context, MaterialPageRoute(builder: (context) => ReportPage(date: _selectedDate))); }),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton({required String title, required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140, height: 110,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.1), blurRadius: 10, offset: const Offset(4, 4))]),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 45, color: AppColors.textPrimary), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary))]),
      ),
    );
  }

  Widget _buildSPathSegment(int index, double pathWidth, double margin) {
    bool isLeftToRight = index % 2 == 0;
    return Container(
      height: 110, // 壓縮高度至 110
      margin: EdgeInsets.symmetric(horizontal: margin),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: const Size(double.infinity, 110),
            painter: GeometricSPathPainter(isLeftToRight: isLeftToRight),
          ),
          ..._buildDotsOnGeometricPath(index, pathWidth, isLeftToRight),
        ],
      ),
    );
  }

  List<Widget> _buildDotsOnGeometricPath(int index, double pathWidth, bool isLeftToRight) {
    List<Widget> dots = [];
    for (int i = 0; i < 5; i++) {
      double t = i / 4.0;
      double dotX = isLeftToRight ? t * pathWidth + 50 : (1 - t) * pathWidth + 50;
      DateTime dotDate = _pathDates[index * 5 + i];
      // 座標精確對位：線條在 30，圓點中心在 30
      dots.add(Positioned(left: dotX - 30, top: 30 - 45, child: _buildDateDot(dotDate)));
    }
    return dots;
  }

  Widget _buildDateDot(DateTime date) {
    String label = "${date.month}/${date.day}";
    bool isSelected = date.year == _rippleDate?.year && date.month == _rippleDate?.month && date.day == _rippleDate?.day;
    double dotSize = isSelected ? 56.0 : 28.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _scrollToDate(date),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          SizedBox(
            width: 60, height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isSelected) const RippleAnimation(),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: dotSize, height: dotSize,
                  decoration: BoxDecoration(color: isSelected ? AppColors.primary : AppColors.secondary, shape: BoxShape.circle, boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: isSelected ? 12 : 8, offset: const Offset(2, 2))]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RippleAnimation extends StatefulWidget {
  const RippleAnimation({super.key});
  @override
  State<RippleAnimation> createState() => _RippleAnimationState();
}

class _RippleAnimationState extends State<RippleAnimation> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  @override
  void initState() { super.initState(); _controller = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(); }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) { return AnimatedBuilder(animation: _controller, builder: (context, child) => Container(width: 60, height: 60, child: CustomPaint(painter: RipplePainter(_controller.value)))); }
}

class RipplePainter extends CustomPainter {
  final double animationValue;
  RipplePainter(this.animationValue);
  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < 3; i++) {
      double value = (animationValue + i / 3.0) % 1.0;
      double radius = (size.width / 2 + 15) * value;
      double opacity = (1.0 - value).clamp(0.0, 1.0);
      final paint = Paint()..color = AppColors.accent.withOpacity(opacity * 0.7)..style = PaintingStyle.stroke..strokeWidth = 3.5;
      canvas.drawCircle(Offset(size.width / 2, size.height / 2), radius, paint);
    }
  }
  @override
  bool shouldRepaint(RipplePainter oldDelegate) => true;
}

class GeometricSPathPainter extends CustomPainter {
  final bool isLeftToRight;
  GeometricSPathPainter({required this.isLeftToRight});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.border..style = PaintingStyle.stroke..strokeWidth = 6.0..strokeCap = StrokeCap.round;
    const double radius = 50.0;
    double pathWidth = size.width - (radius * 2);
    // 對接邏輯：線條在 30，弧線高度 110，總高 110。
    // 這樣下一段起始於 110，內部的線條也位於 30 (110+30 = 140)，與上一段弧線結尾 (30+110 = 140) 完美接合
    if (isLeftToRight) {
      canvas.drawLine(const Offset(50, 30), Offset(50 + pathWidth, 30), paint);
      canvas.drawArc(Rect.fromLTWH(50 + pathWidth - radius, 30, radius * 2, 110), -math.pi / 2, math.pi, false, paint);
    } else {
      canvas.drawLine(Offset(50 + pathWidth, 30), const Offset(50, 30), paint);
      canvas.drawArc(Rect.fromLTWH(50 - radius, 30, radius * 2, 110), -math.pi / 2, -math.pi, false, paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
