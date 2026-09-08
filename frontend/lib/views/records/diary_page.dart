// === 1. 外部套件與自定義模組匯入 ===
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../color/app_colors.dart';
import '../../config/api_config.dart';
import '../../services/auth_service.dart';
import '../../services/diet_service.dart';
import '../../services/token_storage.dart';
import '../../utils/friendly_error_message.dart';
import '../home/home_page.dart';
import 'manual_record_page.dart';

// === 2. 日記頁面 Widget 宣告 ===
class DiaryPage extends StatefulWidget {
  final DateTime date;
  final ValueChanged<DateTime>? onDateChanged;
  const DiaryPage({super.key, required this.date, this.onDateChanged});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  // === 狀態變數與控制器 ===
  late DateTime _selectedDate;
  final Set<String> _expandedMeals = {};
  String? _swipedMeal;
  double _dragExtent = 0.0;
  String? _jwtToken;

  List<dynamic> _allRecords = [];
  bool _isLoading = false;
  String? _avatarUrl;

  // === 生命週期與用戶/寵物資料載入 ===
  @override
  void initState() {
    super.initState();
    _selectedDate = widget.date;
    _loadPetData();
    _fetchRecords();
  }

  @override
  void didUpdateWidget(covariant DiaryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldDate = DateTime(
      oldWidget.date.year,
      oldWidget.date.month,
      oldWidget.date.day,
    );
    final newDate = DateTime(
      widget.date.year,
      widget.date.month,
      widget.date.day,
    );
    if (!oldDate.isAtSameMomentAs(newDate)) {
      setState(() {
        _selectedDate = newDate;
        _expandedMeals.clear();
        _swipedMeal = null;
      });
    }
  }

  Future<void> _loadPetData() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _avatarUrl = prefs.getString('user_avatar_url');
      });
    }
    _jwtToken = await const SecureTokenStorage().readAccessToken();
    final result = await AuthService().getUserProfile();
    if (result['success'] == true) {
      final userData = result['data'];
      final avatarPath =
          userData?['avatarUrl'] ?? userData?['user']?['avatarUrl'];
      if (avatarPath != null && avatarPath.isNotEmpty) {
        final serverBase = ApiConfig.baseUrl.replaceAll('/api', '');
        final fullUrl = avatarPath.startsWith('http')
            ? avatarPath
            : '$serverBase$avatarPath';
        if (mounted) {
          setState(() {
            _avatarUrl = fullUrl;
          });
        }
        await prefs.setString('user_avatar_url', fullUrl);
      }
    }
  }

  // === 日期切換與選擇邏輯 ===
  Future<void> _selectDate() async {
    final picked = await showDatePicker(
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

    if (picked == null || !mounted) return;
    final selectedDate = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      _selectedDate = selectedDate;
      _expandedMeals.clear();
      _swipedMeal = null;
    });
    widget.onDateChanged?.call(selectedDate);
  }

  void _goToPreviousDay() {
    final prevDate = _selectedDate.subtract(const Duration(days: 1));
    setState(() {
      _selectedDate = DateTime(prevDate.year, prevDate.month, prevDate.day);
      _expandedMeals.clear();
      _swipedMeal = null;
    });
    widget.onDateChanged?.call(_selectedDate);
  }

  void _goToNextDay() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentSelected = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    if (currentSelected.isAtSameMomentAs(today) ||
        currentSelected.isAfter(today)) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已經是最新的日期'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final nextDate = _selectedDate.add(const Duration(days: 1));
    setState(() {
      _selectedDate = DateTime(nextDate.year, nextDate.month, nextDate.day);
      _expandedMeals.clear();
      _swipedMeal = null;
    });
    widget.onDateChanged?.call(_selectedDate);
  }

  // === 飲食紀錄 API 獲取與圖片預載入 ===
  Future<void> _fetchRecords() async {
    setState(() => _isLoading = true);
    try {
      final token = await const SecureTokenStorage().readAccessToken();
      final records = await DietService().getMyDietRecords();
      debugPrint('飲食紀錄載入完成，共 ${records.length} 筆');
      setState(() {
        _jwtToken = token; // 確保 JWT Token 在 UI 載入前就緒，防止圖片 headers 變更觸發二次下載
        _allRecords = records;
      });
      // 預加載所有餐點圖片，點擊展開時瞬間顯示
      for (var record in records) {
        if (record['photoUrl'] != null &&
            (record['photoUrl'] as String).isNotEmpty) {
          final imageUrl =
              "${ApiConfig.baseUrl.replaceAll('/api', '')}${record['photoUrl']}";
          final provider = NetworkImage(
            imageUrl,
            headers: token != null ? {'Authorization': 'Bearer $token'} : null,
          );
          // [Lint修復] 異步操作(await)後使用 context 前需檢查 mounted，避免 Widget 銷毀後存取 context 造成錯誤
          if (!mounted) return;
          precacheImage(provider, context).catchError((_) {
            debugPrint('飲食圖片預載入失敗');
          });
        }
      }
    } catch (_) {
      debugPrint('加載飲食紀錄失敗');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // === 紀錄日期解析與份數解析工具 ===
  DateTime? _getRecordDate(dynamic record) {
    if (record == null) return null;

    // 0. Try date first (from backend record_date field)
    final dateVal = record['date'];
    if (dateVal != null) {
      if (dateVal is String) {
        try {
          return DateTime.parse(dateVal);
        } catch (_) {}
      } else if (dateVal is List && dateVal.length >= 3) {
        try {
          return DateTime(
            int.parse(dateVal[0].toString()),
            int.parse(dateVal[1].toString()),
            int.parse(dateVal[2].toString()),
          );
        } catch (_) {}
      } else if (dateVal is Map) {
        try {
          final y = int.parse(
            (dateVal['year'] ?? dateVal['yearValue']).toString(),
          );
          final m = int.parse(
            (dateVal['month'] ?? dateVal['monthValue']).toString(),
          );
          final d = int.parse(
            (dateVal['day'] ?? dateVal['dayOfMonth']).toString(),
          );
          return DateTime(y, m, d);
        } catch (_) {}
      }
    }

    // 1. Try mealDate second
    final mealDateVal = record['mealDate'];
    if (mealDateVal != null) {
      if (mealDateVal is String) {
        try {
          return DateTime.parse(mealDateVal);
        } catch (_) {}
      } else if (mealDateVal is List && mealDateVal.length >= 3) {
        try {
          return DateTime(
            int.parse(mealDateVal[0].toString()),
            int.parse(mealDateVal[1].toString()),
            int.parse(mealDateVal[2].toString()),
          );
        } catch (_) {}
      } else if (mealDateVal is Map) {
        try {
          final y = int.parse(
            (mealDateVal['year'] ?? mealDateVal['yearValue']).toString(),
          );
          final m = int.parse(
            (mealDateVal['month'] ?? mealDateVal['monthValue']).toString(),
          );
          final d = int.parse(
            (mealDateVal['day'] ?? mealDateVal['dayOfMonth']).toString(),
          );
          return DateTime(y, m, d);
        } catch (_) {}
      }
    }

    // 2. Fallback to createdAt
    final createdAtVal = record['createdAt'];
    if (createdAtVal != null) {
      if (createdAtVal is String) {
        try {
          return DateTime.parse(createdAtVal);
        } catch (_) {}
      } else if (createdAtVal is List && createdAtVal.length >= 3) {
        try {
          final y = int.parse(createdAtVal[0].toString());
          final m = int.parse(createdAtVal[1].toString());
          final d = int.parse(createdAtVal[2].toString());
          final h = createdAtVal.length > 3
              ? int.parse(createdAtVal[3].toString())
              : 0;
          final min = createdAtVal.length > 4
              ? int.parse(createdAtVal[4].toString())
              : 0;
          final s = createdAtVal.length > 5
              ? int.parse(createdAtVal[5].toString())
              : 0;
          return DateTime(y, m, d, h, min, s);
        } catch (_) {}
      }
    }
    return null;
  }

  String _parsePortionAtIndex(dynamic record, int index) {
    if (record == null) return "1份";
    final amountVal = record['amount'];
    final portionsVal = record['portions'];
    final descriptionVal = record['description'];
    final sourceStr =
        (amountVal != null && amountVal.toString().trim().isNotEmpty)
        ? amountVal.toString().trim()
        : ((portionsVal != null && portionsVal.toString().trim().isNotEmpty)
              ? portionsVal.toString().trim()
              : (descriptionVal != null
                    ? descriptionVal.toString().trim()
                    : ''));

    if (sourceStr.isEmpty || sourceStr == "手動輸入飲食紀錄") {
      return "1份";
    }
    final parts = sourceStr.split(RegExp(r',\s*'));
    if (index >= parts.length) return "1份";
    final part = parts[index].trim();

    final match = RegExp(r'^(\d+(?:\.\d+)?)\s*(?:份)?$').firstMatch(part);
    if (match != null) {
      final numStr = match.group(1)!;
      final val = double.tryParse(numStr);
      if (val != null) {
        if (val == val.toInt()) {
          return "${val.toInt()}份";
        }
        return "$val份"; // [Lint修復] 簡化單一變數插值，移除多餘大括號
      }
    }
    if (part.contains("份")) {
      final m = RegExp(r'(\d+(?:\.\d+)?)\s*份').firstMatch(part);
      if (m != null) {
        final val = double.tryParse(m.group(1)!);
        if (val != null) {
          if (val == val.toInt()) {
            return "${val.toInt()}份";
          }
          return "$val份"; // [Lint修復] 簡化單一變數插值，移除多餘大括號
        }
      }
      return part;
    }
    return "1份";
  }

  // 根據日期過濾今日的飲食紀錄
  List<dynamic> _getRecordsForSelectedDate() {
    return _allRecords.where((record) {
      final rDate = _getRecordDate(record);
      if (rDate == null) return false;
      return rDate.year == _selectedDate.year &&
          rDate.month == _selectedDate.month &&
          rDate.day == _selectedDate.day;
    }).toList();
  }

  // === UI 建構主邏輯 ===
  @override
  Widget build(BuildContext context) {
    String dateStr =
        "${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日";
    final todayRecords = _getRecordsForSelectedDate();

    final breakfastRecords = todayRecords
        .where((r) => r['mealType'] == 'BREAKFAST')
        .toList();
    final lunchRecords = todayRecords
        .where((r) => r['mealType'] == 'LUNCH')
        .toList();
    final dinnerRecords = todayRecords
        .where((r) => r['mealType'] == 'DINNER')
        .toList();
    final otherRecords = todayRecords
        .where((r) => r['mealType'] == 'OTHER' || r['mealType'] == '其他')
        .toList();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  const SizedBox(height: 80),
                  _buildDateBar(dateStr),
                  Expanded(
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                            children: [
                              _buildMealSection(
                                "早餐",
                                Icons.wb_sunny_outlined,
                                breakfastRecords,
                              ),
                              const SizedBox(height: 15),
                              _buildMealSection(
                                "中餐",
                                Icons.wb_sunny,
                                lunchRecords,
                              ),
                              const SizedBox(height: 15),
                              _buildMealSection(
                                "晚餐",
                                Icons.nights_stay_outlined,
                                dinnerRecords,
                              ),
                              const SizedBox(height: 15),
                              _buildMealSection(
                                "其他",
                                Icons.more_horiz,
                                otherRecords,
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: _buildHeader(context)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  ManualRecordPage(initialDate: _selectedDate),
            ),
          );
          _fetchRecords();
        },
        backgroundColor: AppColors.primary,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 30),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey,
        backgroundColor: AppColors.background,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) =>
                HomePage(initialIndex: index, initialReportDate: _selectedDate),
          ),
          (route) => false,
        ),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.smart_toy_outlined),
            label: '米粒',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.edit_note), label: '飲食紀錄'),
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment_outlined),
            label: '飲食報告',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle),
            label: '個人首頁',
          ),
        ],
      ),
    );
  }

  // === 頂部固定標題列區塊 ===
  Widget _buildHeader(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          height: 80 + statusBarHeight,
          decoration: BoxDecoration(
            color: AppColors.background.withValues(
              alpha: 0.5,
            ), // [API更新] withOpacity 已過時，改用 withValues(alpha: 0.5)
            border: Border(
              bottom: BorderSide(color: AppColors.border, width: 0.5),
            ),
          ),
          padding: EdgeInsets.fromLTRB(16, statusBarHeight + 20, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () {
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  } else {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (context) => HomePage(initialIndex: 1),
                      ),
                      (route) => false,
                    );
                  }
                },
                icon: const Icon(Icons.arrow_back_ios, size: 28),
              ),
              const Text(
                '日記',
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
                        color: Colors.black.withValues(
                          alpha: 0.35,
                        ), // [API更新] withOpacity 已過時，改用 withValues(alpha: 0.35)
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
    );
  }

  // === 日期切換工具列 ===
  Widget _buildDateBar(String dateStr) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final currentSelected = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final bool isLatest =
        currentSelected.isAtSameMomentAs(today) ||
        currentSelected.isAfter(today);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: 0.05,
            ), // [API更新] withOpacity 改用 withValues(alpha: 0.05)
            blurRadius: 0.975,
            offset: const Offset(0, 0.39),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _goToPreviousDay,
            icon: const Icon(
              Icons.chevron_left,
              color: AppColors.textPrimary,
              size: 28,
            ),
            tooltip: '前一天',
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _selectDate,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                dateStr,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _goToNextDay,
            icon: Icon(
              Icons.chevron_right,
              color: isLatest
                  ? AppColors.textPrimary.withValues(
                      alpha: 0.35,
                    ) // [API更新] withOpacity 改用 withValues(alpha: 0.35)
                  : AppColors.textPrimary,
              size: 28,
            ),
            tooltip: '後一天',
          ),
        ],
      ),
    );
  }

  // === 餐點時段與餐點卡片組件 ===
  Widget _buildMealSection(String title, IconData icon, List<dynamic> records) {
    if (records.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(
                alpha: 0.05,
              ), // [API更新] withOpacity 改用 withValues(alpha: 0.05)
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: Colors.grey),
            const SizedBox(width: 12),
            Text(
              "$title - 今日無紀錄",
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: records.map((record) {
        final List<String> dishItems = (record['dishName'] as String).split(
          ', ',
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: _buildMealCard(title, icon, dishItems, record),
        );
      }).toList(),
    );
  }

  Widget _buildMealCard(
    String title,
    IconData icon,
    List<String> items,
    dynamic record,
  ) {
    bool isExpanded = _expandedMeals.contains(record['id'].toString());
    bool isSwiped = _swipedMeal == record['id'].toString();
    bool needsExpansion = true;
    final nutritionParts = _getNutritionParts(record['nutrition']);

    return Column(
      children: [
        GestureDetector(
          onHorizontalDragUpdate: (details) {
            _dragExtent += details.delta.dx;
            // [格式修復] if 語句補全大括號，符合 Dart 代碼規範
            if (_dragExtent < -5) {
              setState(() => _swipedMeal = record['id'].toString());
            } else if (_dragExtent > 5) {
              setState(() => _swipedMeal = null);
            }
          },
          onHorizontalDragEnd: (details) {
            _dragExtent = 0;
            // [格式修復] if 語句補全大括號，符合 Dart 代碼規範
            if (details.primaryVelocity! < -300) {
              setState(() => _swipedMeal = record['id'].toString());
            } else if (details.primaryVelocity! > 300) {
              setState(() => _swipedMeal = null);
            }
          },
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(
                    alpha: 0.1,
                  ), // [API更新] withOpacity 改用 withValues(alpha: 0.1)
                  blurRadius: 1.95,
                  offset: const Offset(0, 0.78),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    color: const Color(0xFFEEEEEE),
                    padding: const EdgeInsets.only(right: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _buildActionBtn(
                          Icons.edit,
                          "編輯",
                          AppColors.secondary,
                          () => _handleEditRecord(record),
                        ),
                        _buildActionBtn(
                          Icons.image,
                          "相片",
                          AppColors.accent,
                          () => _handleUploadPhoto(record),
                        ),
                        _buildActionBtn(
                          Icons.delete,
                          "刪除",
                          AppColors.danger,
                          () => _handleDeleteRecord(record),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutQuart,
                  left: isSwiped ? -200 : 0,
                  right: isSwiped ? 200 : 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    color: Colors.white,
                    child: Row(
                      children: [
                        Container(
                          width: 80,
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: AppColors.border,
                                width: 1.5,
                              ),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(icon, size: 30, color: AppColors.secondary),
                              Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  for (
                                    int i = 0;
                                    i <
                                        (isExpanded
                                            ? items.length
                                            : items.take(2).length);
                                    i++
                                  ) ...[
                                    if (i > 0) const TextSpan(text: "\n"),
                                    TextSpan(
                                      text: items[i],
                                      style: const TextStyle(
                                        fontSize: 18,
                                        height: 1.4,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    TextSpan(
                                      text:
                                          " (${_parsePortionAtIndex(record, i)})",
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              maxLines: isExpanded ? 10 : 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            if (needsExpansion)
                              IconButton(
                                icon: Icon(
                                  isExpanded
                                      ? Icons.arrow_drop_up
                                      : Icons.arrow_drop_down,
                                  color: AppColors.textPrimary,
                                ),
                                onPressed: () {
                                  setState(() {
                                    // [格式修復] if 語句補全大括號
                                    if (isExpanded) {
                                      _expandedMeals.remove(
                                        record['id'].toString(),
                                      );
                                    } else {
                                      _expandedMeals.add(
                                        record['id'].toString(),
                                      );
                                    }
                                  });
                                },
                              ),
                            Container(
                              width: 4,
                              height: 40,
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: AppColors.border,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
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
        Visibility(
          visible: isExpanded,
          maintainState: true,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(15),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: 0.05,
                  ), // [API更新] withOpacity 改用 withValues(alpha: 0.05)
                  blurRadius: 0.975,
                  offset: const Offset(0, 0.39),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (items.length > 2)
                  Text(
                    items.skip(2).join("\n"),
                    style: const TextStyle(
                      fontSize: 18,
                      height: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                if (nutritionParts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(
                          alpha: 0.08,
                        ), // [API更新] withOpacity 改用 withValues(alpha: 0.08)
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "營養分析",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.secondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // [Lint修復] Spread 展開運算子內直接傳回 Iterable，移除多餘的 .toList()
                          ...nutritionParts.map(
                            (part) => Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 2.0,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: AppColors.secondary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    part.trim(),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (record['photoUrl'] != null &&
                    (record['photoUrl'] as String).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        "${ApiConfig.baseUrl.replaceAll('/api', '')}${record['photoUrl']}",
                        headers: _jwtToken != null
                            ? {'Authorization': 'Bearer $_jwtToken'}
                            : null,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: 200,
                            color: Colors.grey[100],
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                              ),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.broken_image,
                              size: 50,
                              color: Colors.grey,
                            ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // === 左滑動作按鈕（編輯、上傳相片、刪除） ===
  Widget _buildActionBtn(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: 50,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(
                  alpha: 0.1,
                ), // [API更新] withOpacity 改用 withValues(alpha: 0.1)
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // === 營養數據解析工具函數 ===
  List<String> _getNutritionParts(dynamic nutritionVal) {
    if (nutritionVal == null) return [];

    String formatValue(String key, dynamic val) {
      if (val == null) return '--';
      final sVal = val.toString().trim();
      if (sVal.isEmpty || sVal == 'null' || sVal == 'None') return '--';

      if (key.contains('熱量') ||
          key.toLowerCase().contains('calories') ||
          key.toLowerCase().contains('cal')) {
        if (sVal.contains('kcal') || sVal.contains('卡')) return sVal;
        return '$sVal kcal';
      }
      if (key.contains('蛋白質') ||
          key.toLowerCase().contains('protein') ||
          key.contains('脂肪') ||
          key.toLowerCase().contains('fat') ||
          key.contains('碳水') ||
          key.toLowerCase().contains('carb')) {
        if (sVal.contains('g') || sVal.contains('克')) return sVal;
        return '$sVal g';
      }
      return sVal;
    }

    if (nutritionVal is Map) {
      final List<String> parts = [];
      nutritionVal.forEach((k, v) {
        final keyStr = k.toString().trim();
        final valStr = formatValue(keyStr, v);
        String displayKey = keyStr;
        // [格式修復] if/else 語句補全大括號，符合 Dart 規範
        if (keyStr.toLowerCase() == 'calories') {
          displayKey = '熱量';
        } else if (keyStr.toLowerCase() == 'protein') {
          displayKey = '蛋白質';
        } else if (keyStr.toLowerCase() == 'fat') {
          displayKey = '脂肪';
        } else if (keyStr.toLowerCase() == 'carbohydrates' ||
            keyStr.toLowerCase() == 'carbs') {
          displayKey = '碳水化合物';
        }
        parts.add('$displayKey: $valStr');
      });
      return parts;
    }
    if (nutritionVal is String) {
      if (nutritionVal.isEmpty) return [];
      final trimmed = nutritionVal.trim();
      if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
        try {
          final parsed = jsonDecode(trimmed);
          if (parsed is Map) {
            return _getNutritionParts(parsed);
          }
        } catch (_) {}
      }
      return nutritionVal
          .split(', ')
          .where((s) => s.trim().isNotEmpty)
          .toList();
    }
    return [nutritionVal.toString()];
  }

  String _parseNutrient(String? nutritionStr, String pattern) {
    if (nutritionStr == null || nutritionStr.isEmpty) return '';
    final regExp = RegExp(
      pattern + r'(?:\s*:\s*|\s+)(\d+(?:\.\d+)?)',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(nutritionStr);
    return match != null ? (match.group(1) ?? '') : '';
  }

  // === 飲食紀錄 CRUD 操作邏輯 ===
  // 1. 編輯紀錄
  Future<void> _handleEditRecord(dynamic record) async {
    setState(() => _swipedMeal = null);
    final String nutritionStr = record['nutrition'] is Map
        ? _getNutritionParts(record['nutrition']).join(', ')
        : (record['nutrition']?.toString() ?? '');
    final calVal = _parseNutrient(nutritionStr, r'(?:熱量|calories|kcal)');
    final proVal = _parseNutrient(nutritionStr, r'(?:蛋白質|protein)');
    final fatVal = _parseNutrient(nutritionStr, r'(?:脂肪|fat)');
    final carbVal = _parseNutrient(nutritionStr, r'(?:碳水化合物|碳水|carbs)');

    final rawAmount = (record['amount'] ?? record['portion'] ?? '1').toString();
    final amountDigits = rawAmount.replaceAll(RegExp(r'[^\d.]'), '');
    final result = await showDialog<_EditDietRecordFormData>(
      context: context,
      builder: (ctx) => _EditDietRecordDialog(
        dishName: (record['dishName'] ?? '未命名料理').toString(),
        initialAmountText: amountDigits.isEmpty ? '1' : amountDigits,
        initialCaloriesText: calVal,
        initialProteinText: proVal,
        initialFatText: fatVal,
        initialCarbohydratesText: carbVal,
      ),
    );
    if (result == null || !mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('正在更新餐點資訊...')));

    final res = await DietService().updateDietRecord(
      record['id'],
      amount: result.amount,
      calories: result.calories,
      protein: result.protein,
      fat: result.fat,
      carbohydrates: result.carbohydrates,
    );
    if (!mounted) return;
    if (res['success'] == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('更新成功！')));
      _fetchRecords();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(FriendlyErrorMessage.dietRecord)),
      );
    }
  }

  // 2. 上傳相片
  Future<void> _handleUploadPhoto(dynamic record) async {
    setState(() => _swipedMeal = null);
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        // [Lint修復] 選擇相片異步操作後檢查 mounted
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('正在上傳餐點照片...')));
        final bytes = await image.readAsBytes();
        final res = await DietService().uploadDietPhoto(
          record['id'],
          bytes,
          image.name,
        );
        // [Lint修復] 上傳照片異步操作後檢查 mounted
        if (!mounted) return;
        if (res['success'] == true) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('照片上傳成功！')));
          _fetchRecords();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(FriendlyErrorMessage.upload)),
          );
        }
      }
    } catch (e) {
      // [Lint修復] catch 區塊存取 context 前檢查 mounted
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(FriendlyErrorMessage.upload)),
      );
    }
  }

  // 3. 刪除紀錄
  void _handleDeleteRecord(dynamic record) {
    setState(() => _swipedMeal = null);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text('確定要刪除「${record['dishName']}」這筆飲食紀錄嗎？此動作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('正在刪除...')));
              final success = await DietService().deleteDietRecord(
                record['id'],
              );
              // [Lint修復] 刪除紀錄異步操作後檢查 mounted
              if (!mounted) return;
              if (success) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('已刪除紀錄！')));
                _fetchRecords();
              } else {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('刪除失敗，請再試一次。')));
              }
            },
            child: const Text(
              '確認刪除',
              style: TextStyle(
                color: AppColors.danger,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditDietRecordFormData {
  const _EditDietRecordFormData({
    required this.amount,
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbohydrates,
  });

  final double amount;
  final double calories;
  final double protein;
  final double fat;
  final double carbohydrates;
}

class _EditDietRecordDialog extends StatefulWidget {
  const _EditDietRecordDialog({
    required this.dishName,
    required this.initialAmountText,
    required this.initialCaloriesText,
    required this.initialProteinText,
    required this.initialFatText,
    required this.initialCarbohydratesText,
  });

  final String dishName;
  final String initialAmountText;
  final String initialCaloriesText;
  final String initialProteinText;
  final String initialFatText;
  final String initialCarbohydratesText;

  @override
  State<_EditDietRecordDialog> createState() => _EditDietRecordDialogState();
}

class _EditDietRecordDialogState extends State<_EditDietRecordDialog> {
  late final TextEditingController _dishNameController;
  late final TextEditingController _amountController;
  late final TextEditingController _caloriesController;
  late final TextEditingController _proteinController;
  late final TextEditingController _fatController;
  late final TextEditingController _carbohydratesController;

  late final double _perServingCalories;
  late final double _perServingProtein;
  late final double _perServingFat;
  late final double _perServingCarbohydrates;

  var _isUpdatingCalculatedValues = false;
  var _caloriesEdited = false;
  var _proteinEdited = false;
  var _fatEdited = false;
  var _carbohydratesEdited = false;

  @override
  void initState() {
    super.initState();
    _dishNameController = TextEditingController(text: widget.dishName);
    _amountController = TextEditingController(text: widget.initialAmountText);
    _caloriesController = TextEditingController(
      text: widget.initialCaloriesText,
    );
    _proteinController = TextEditingController(text: widget.initialProteinText);
    _fatController = TextEditingController(text: widget.initialFatText);
    _carbohydratesController = TextEditingController(
      text: widget.initialCarbohydratesText,
    );

    final initialAmount = double.tryParse(widget.initialAmountText) ?? 1;
    _perServingCalories =
        (double.tryParse(widget.initialCaloriesText) ?? 0) / initialAmount;
    _perServingProtein =
        (double.tryParse(widget.initialProteinText) ?? 0) / initialAmount;
    _perServingFat =
        (double.tryParse(widget.initialFatText) ?? 0) / initialAmount;
    _perServingCarbohydrates =
        (double.tryParse(widget.initialCarbohydratesText) ?? 0) / initialAmount;

    _amountController.addListener(_recalculateUneditedNutrition);
    _caloriesController.addListener(_handleCaloriesChanged);
    _proteinController.addListener(_handleProteinChanged);
    _fatController.addListener(_handleFatChanged);
    _carbohydratesController.addListener(_handleCarbohydratesChanged);
  }

  @override
  void dispose() {
    _amountController.removeListener(_recalculateUneditedNutrition);
    _caloriesController.removeListener(_handleCaloriesChanged);
    _proteinController.removeListener(_handleProteinChanged);
    _fatController.removeListener(_handleFatChanged);
    _carbohydratesController.removeListener(_handleCarbohydratesChanged);

    _dishNameController.dispose();
    _amountController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _carbohydratesController.dispose();
    super.dispose();
  }

  String _numberText(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  void _handleCaloriesChanged() {
    _caloriesEdited = !_isUpdatingCalculatedValues;
  }

  void _handleProteinChanged() {
    _proteinEdited = !_isUpdatingCalculatedValues;
  }

  void _handleFatChanged() {
    _fatEdited = !_isUpdatingCalculatedValues;
  }

  void _handleCarbohydratesChanged() {
    _carbohydratesEdited = !_isUpdatingCalculatedValues;
  }

  void _recalculateUneditedNutrition() {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) return;

    _isUpdatingCalculatedValues = true;
    if (!_caloriesEdited) {
      _caloriesController.text = _numberText(_perServingCalories * amount);
    }
    if (!_proteinEdited) {
      _proteinController.text = _numberText(_perServingProtein * amount);
    }
    if (!_fatEdited) {
      _fatController.text = _numberText(_perServingFat * amount);
    }
    if (!_carbohydratesEdited) {
      _carbohydratesController.text = _numberText(
        _perServingCarbohydrates * amount,
      );
    }
    _isUpdatingCalculatedValues = false;
  }

  void _submit() {
    final parsedAmount = double.tryParse(_amountController.text.trim());
    if (parsedAmount == null ||
        parsedAmount <= 0 ||
        parsedAmount != parsedAmount.roundToDouble()) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('份數需為大於 0 的整數')));
      return;
    }

    final calories = double.tryParse(_caloriesController.text.trim());
    final protein = double.tryParse(_proteinController.text.trim());
    final fat = double.tryParse(_fatController.text.trim());
    final carbohydrates = double.tryParse(_carbohydratesController.text.trim());
    if ([
      calories,
      protein,
      fat,
      carbohydrates,
    ].any((value) => value == null || value < 0)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('請填寫四項營養數值；沒有資料請填 0。')));
      return;
    }

    Navigator.of(context).pop(
      _EditDietRecordFormData(
        amount: parsedAmount,
        calories: calories!,
        protein: protein!,
        fat: fat!,
        carbohydrates: carbohydrates!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('編輯餐點資訊'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _dishNameController,
              enabled: false,
              decoration: const InputDecoration(labelText: '料理名稱'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '份數',
                hintText: '例：1',
              ),
            ),
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '以下為依目前份數換算的總營養，並非單份；沒有資料請填 0。',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _caloriesController,
              decoration: const InputDecoration(labelText: '熱量 (kcal)'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _proteinController,
              decoration: const InputDecoration(labelText: '蛋白質 (g)'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fatController,
              decoration: const InputDecoration(labelText: '脂肪 (g)'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _carbohydratesController,
              decoration: const InputDecoration(labelText: '碳水化合物 (g)'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text(
            '儲存',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
