// === 1. 外部套件與自定義模組匯入 ===
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../color/app_colors.dart';
import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import '../../services/diet_service.dart';
import '../../widgets/dog_avatar.dart';
import '../home/home_page.dart';
import 'diary_page.dart';
import 'manual_record_page.dart';

// === 2. 飲食紀錄主頁面 ===
class DietaryRecordPage extends StatefulWidget {
  final ValueChanged<DateTime>? onDateSelected;
  final ValueListenable<int>? avatarRefreshListenable;

  const DietaryRecordPage({
    super.key,
    this.onDateSelected,
    this.avatarRefreshListenable,
  });

  @override
  State<DietaryRecordPage> createState() => _DietaryRecordPageState();
}

class _DietaryRecordPageState extends State<DietaryRecordPage> {
  // === 狀態變數與控制器 ===
  final ScrollController _scrollController = ScrollController();
  bool _showBackToToday = false;
  DateTime _selectedDate = DateTime.now();
  bool _showOverlay = false;
  DateTime? _rippleDate;
  bool _isLoadingRecords = false;
  List<dynamic> _dietRecords = [];

  // 生成歷史日期序列（過去100天）
  final List<DateTime> _pathDates = List.generate(
    100,
    (i) => DateTime.now().subtract(Duration(days: i)),
  );
  String? _avatarUrl;

  // === 頭像與數據載入邏輯 ===
  String? _resolveAvatarUrl(dynamic avatarPath) {
    final path = avatarPath?.toString().trim();
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;

    final serverBase = ApiConfig.baseUrl.replaceAll('/api', '');
    return '$serverBase$path';
  }

  Future<void> _loadAvatar() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedAvatarUrl = _resolveAvatarUrl(
      prefs.getString('user_avatar_url'),
    );
    if (mounted) {
      setState(() {
        _avatarUrl = cachedAvatarUrl;
      });
    }
    final result = await AuthService().getUserProfile();
    if (result['success'] == true) {
      final userData = result['data'];
      final avatarPath =
          userData?['avatarUrl'] ?? userData?['user']?['avatarUrl'];
      final fullUrl = _resolveAvatarUrl(avatarPath);
      if (fullUrl != null) {
        if (mounted) {
          setState(() {
            _avatarUrl = fullUrl;
          });
        }
        await prefs.setString('user_avatar_url', fullUrl);
      }
    }
  }

  void _handleAvatarRefresh() {
    _loadAvatar();
  }

  @override
  void initState() {
    super.initState();
    widget.avatarRefreshListenable?.addListener(_handleAvatarRefresh);
    _loadAvatar();
    _loadDietRecords();
    _scrollController.addListener(() {
      if (_scrollController.offset > 200 && !_showBackToToday) {
        setState(() => _showBackToToday = true);
      } else if (_scrollController.offset <= 200 && _showBackToToday) {
        setState(() => _showBackToToday = false);
      }
    });
  }

  Future<void> _loadDietRecords() async {
    setState(() => _isLoadingRecords = true);
    try {
      final records = await DietService().getMyDietRecords();
      if (mounted) {
        setState(() => _dietRecords = records);
      }
    } catch (_) {
      debugPrint('載入飲食紀錄狀態失敗');
    } finally {
      if (mounted) {
        setState(() => _isLoadingRecords = false);
      }
    }
  }

  // === 飲食紀錄解析與精靈提示計算 ===
  DateTime? _recordDate(dynamic record) {
    if (record == null) return null;
    final value = record['date'] ?? record['mealDate'] ?? record['createdAt'];
    if (value == null) return null;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        return null;
      }
    }
    if (value is List && value.length >= 3) {
      try {
        return DateTime(
          int.parse(value[0].toString()),
          int.parse(value[1].toString()),
          int.parse(value[2].toString()),
        );
      } catch (_) {
        return null;
      }
    }
    if (value is Map) {
      try {
        return DateTime(
          int.parse((value['year'] ?? value['yearValue']).toString()),
          int.parse((value['month'] ?? value['monthValue']).toString()),
          int.parse((value['day'] ?? value['dayOfMonth']).toString()),
        );
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  List<dynamic> _recordsForDate(DateTime date) {
    return _dietRecords.where((record) {
      final recordDate = _recordDate(record);
      return recordDate != null &&
          recordDate.year == date.year &&
          recordDate.month == date.month &&
          recordDate.day == date.day;
    }).toList();
  }

  String _elfRecordMessage() {
    if (_isLoadingRecords) return '正在看看\n飲食紀錄...';

    final records = _recordsForDate(_selectedDate);
    final today = DateTime.now();
    final isToday =
        _selectedDate.year == today.year &&
        _selectedDate.month == today.month &&
        _selectedDate.day == today.day;

    if (records.isEmpty) {
      return isToday ? '今天還沒記錄\n好餓喔...' : '這天還沒記錄\n可以補一下喔';
    }

    final mealTypes = records
        .map((record) => (record['mealType'] ?? '').toString().toUpperCase())
        .toSet();
    final missingMeals = <String>[
      if (!mealTypes.contains('BREAKFAST')) '早餐',
      if (!mealTypes.contains('LUNCH')) '午餐',
      if (!mealTypes.contains('DINNER')) '晚餐',
    ];

    if (missingMeals.isEmpty) {
      return '三餐都有記錄\n好棒！';
    }
    if (records.length >= 3) {
      return '已記錄 ${records.length} 筆\n繼續保持！';
    }
    return '已記錄 ${records.length} 筆\n還差${missingMeals.first}';
  }

  // === 日期選擇器與滾動定位 ===
  void _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: AppColors.background,
            onSurface: AppColors.textPrimary,
          ),
        ),
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
      _showOverlay = false;
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            DiaryPage(date: date, onDateChanged: widget.onDateSelected),
      ),
    ).then((_) => _loadDietRecords());
    widget.onDateSelected?.call(date);

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

  // === UI 建構主邏輯 ===
  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    const double margin = 20.0;
    const double radius = 50.0;
    final double pathWidth = screenWidth - (margin * 2) - (radius * 2);
    final double statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          // 1. 路徑區 (高度壓縮至 110)
          Positioned.fill(
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.only(top: 250 + statusBarHeight, bottom: 200),
              itemCount: 20,
              itemBuilder: (context, index) =>
                  _buildSPathSegment(index, pathWidth, margin),
            ),
          ),

          // 2. 遮罩區
          if (_showOverlay)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() {
                  _showOverlay = false;
                  _rippleDate = null;
                }),
                behavior: HitTestBehavior.translucent,
                child: Container(
                  // Flutter 3.27+ API 替代 withOpacity
                  color: Colors.black.withValues(alpha: 0.3),
                ),
              ),
            ),

          // 3. 固定標題列與功能列
          _buildFixedHeader(context),
          _buildFeatureRow(),

          // 4. 底部彈出操作區
          if (_showOverlay)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildActionPanel(context),
            ),

          // 5. 「回今天」按鈕 (中文 + 雙箭頭)
          if (_showBackToToday)
            Positioned(
              right: 20,
              bottom: _showOverlay
                  ? MediaQuery.of(context).size.height * 0.35 + 20
                  : 20,
              child: GestureDetector(
                onTap: () => _scrollToDate(DateTime.now()),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        // Flutter 3.27+ API 替代 withOpacity
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 1.95,
                        offset: const Offset(0, 0.78),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.keyboard_double_arrow_up,
                        color: Colors.white,
                        size: 20,
                      ),
                      SizedBox(width: 4),
                      Text(
                        '回今天',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // === 頂部標題與用戶頭像區 ===
  Widget _buildFixedHeader(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            height: 80 + statusBarHeight,
            decoration: BoxDecoration(
              // Flutter 3.27+ API 替代 withOpacity
              color: AppColors.background.withValues(alpha: 0.7),
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 0.5),
              ),
            ),
            padding: EdgeInsets.fromLTRB(16, statusBarHeight + 20, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 50),
                const Text(
                  '飲食紀錄',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                    letterSpacing: 1.2,
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (context) => HomePage(initialIndex: 3),
                    ),
                    (route) => false,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          // Flutter 3.27+ API 替代 withOpacity
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 2.925,
                          offset: const Offset(0, 1.56),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 25,
                      backgroundColor: AppColors.background,
                      backgroundImage:
                          _avatarUrl != null && _avatarUrl!.isNotEmpty
                          ? NetworkImage(_avatarUrl!)
                          : null,
                      child: _avatarUrl == null || _avatarUrl!.isEmpty
                          ? const Icon(
                              Icons.person,
                              color: AppColors.textPrimary,
                              size: 35,
                            )
                          : null,
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

  // === 頂部快捷功能區（日期選擇、新增按鈕、寵物提示） ===
  Widget _buildFeatureRow() {
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    return Positioned(
      top: 80 + statusBarHeight,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 1. 月份/日期選擇框
            GestureDetector(
              onTap: _selectDate,
              child: Container(
                width: 60,
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      // Flutter 3.27+ API 替代 withOpacity
                      color: AppColors.primary.withValues(alpha: 0.2),
                      blurRadius: 1.95,
                      offset: const Offset(0.78, 1.17),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('月', style: TextStyle(fontSize: 14)),
                    Text(
                      '${_selectedDate.day}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 2. 新增飲食記錄按鈕
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        ManualRecordPage(initialDate: _selectedDate),
                  ),
                ).then((_) => _loadDietRecords());
              },
              child: Container(
                width: 160,
                height: 70,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      // Flutter 3.27+ API 替代 withOpacity
                      color: AppColors.primary.withValues(alpha: 0.5),
                      blurRadius: 2.925,
                      offset: const Offset(0, 1.95),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add,
                  color: AppColors.background,
                  size: 35,
                ),
              ),
            ),
            // 3. 寵物對話與頭像互動
            GestureDetector(
              onTap: () => Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      const HomePage(initialIndex: 0, showChat: true),
                ),
                (route) => false,
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCF8EC),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          // Flutter 3.27+ API 替代 withOpacity
                          color: AppColors.primary.withValues(alpha: 0.1),
                          blurRadius: 0.975,
                          offset: const Offset(0.39, 0.39),
                        ),
                      ],
                    ),
                    child: Text(
                      _elfRecordMessage(),
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Transform.translate(
                    offset: const Offset(0, -13),
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: OverflowBox(
                        maxWidth: 82,
                        maxHeight: 82,
                        child: SizedBox(
                          width: 82,
                          height: 82,
                          child: DogAvatar(
                            instanceId: 'diet-record-prompt',
                            scale: 1.8,
                            cameraControls: false,
                          ),
                        ),
                      ),
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

  // === 底部動作選單面板 ===
  Widget _buildActionPanel(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.35,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Text(
            "${_selectedDate.month}月${_selectedDate.day}日 飲食記錄",
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 50),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMenuButton(
                  title: "日記",
                  icon: Icons.restaurant,
                  color: const Color.fromARGB(255, 235, 215, 192),
                  onTap: () {
                    setState(() => _showOverlay = false);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DiaryPage(
                          date: _selectedDate,
                          onDateChanged: widget.onDateSelected,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuButton({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        height: 110,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              // Flutter 3.27+ API 替代 withOpacity
              color: AppColors.primary.withValues(alpha: 0.1),
              blurRadius: 1.95,
              offset: const Offset(0.78, 0.78),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 45, color: AppColors.textPrimary),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // === 歷史記錄蛇形路徑與日期節點 ===
  Widget _buildSPathSegment(int index, double pathWidth, double margin) {
    bool isLeftToRight = index % 2 == 0;
    return Container(
      height: 110,
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

  List<Widget> _buildDotsOnGeometricPath(
    int index,
    double pathWidth,
    bool isLeftToRight,
  ) {
    List<Widget> dots = [];
    for (int i = 0; i < 5; i++) {
      double t = i / 4.0;
      double dotX = isLeftToRight
          ? t * pathWidth + 50
          : (1 - t) * pathWidth + 50;
      DateTime dotDate = _pathDates[index * 5 + i];
      dots.add(
        Positioned(
          left: dotX - 30,
          top: 30 - 45,
          child: _buildDateDot(dotDate),
        ),
      );
    }
    return dots;
  }

  Widget _buildDateDot(DateTime date) {
    String label = "${date.month}/${date.day}";
    bool isSelected =
        date.year == _rippleDate?.year &&
        date.month == _rippleDate?.month &&
        date.day == _rippleDate?.day;
    double dotSize = isSelected ? 56.0 : 28.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _scrollToDate(date),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
          SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isSelected) const RippleAnimation(),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: dotSize,
                  height: dotSize,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.secondary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        // Flutter 3.27+ API 替代 withOpacity
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: isSelected ? 2.34 : 1.56,
                        offset: const Offset(0.39, 0.39),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.avatarRefreshListenable?.removeListener(_handleAvatarRefresh);
    _scrollController.dispose();
    super.dispose();
  }
}

// === 3. 動畫特效 Widget：點選日期之擴散波紋 ===
class RippleAnimation extends StatefulWidget {
  const RippleAnimation({super.key});

  @override
  State<RippleAnimation> createState() => _RippleAnimationState();
}

class _RippleAnimationState extends State<RippleAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      // 效能優化：僅指定固定寬高時使用 SizedBox 代替 Container，避免多餘的裝飾與邊距計算（符合 Flutter sized_box_for_whitespace 規範）
      builder: (context, child) => SizedBox(
        width: 60,
        height: 60,
        child: CustomPaint(painter: RipplePainter(_controller.value)),
      ),
    );
  }
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
      final paint = Paint()
        // Flutter 3.27+ API 替代 withOpacity
        ..color = AppColors.accent.withValues(alpha: opacity * 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5;
      canvas.drawCircle(Offset(size.width / 2, size.height / 2), radius, paint);
    }
  }

  @override
  bool shouldRepaint(RipplePainter oldDelegate) => true;
}

// === 4. CustomPainter：繪製背景 S 型雙向蛇形歷史路徑 ===
class GeometricSPathPainter extends CustomPainter {
  final bool isLeftToRight;
  GeometricSPathPainter({required this.isLeftToRight});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFCF8EC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..strokeCap = StrokeCap.round;
    const double radius = 50.0;
    double pathWidth = size.width - (radius * 2);

    if (isLeftToRight) {
      canvas.drawLine(const Offset(50, 30), Offset(50 + pathWidth, 30), paint);
      canvas.drawArc(
        Rect.fromLTWH(50 + pathWidth - radius, 30, radius * 2, 110),
        -math.pi / 2,
        math.pi,
        false,
        paint,
      );
    } else {
      canvas.drawLine(Offset(50 + pathWidth, 30), const Offset(50, 30), paint);
      canvas.drawArc(
        Rect.fromLTWH(50 - radius, 30, radius * 2, 110),
        -math.pi / 2,
        -math.pi,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
