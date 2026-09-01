import 'package:flutter/material.dart';

import '../color/app_colors.dart';
import '../services/diet_service.dart';

/// 對話框內嵌原生「歷史飲食紀錄卡片」組件
class MealRecordCard extends StatefulWidget {
  final String queryDate; // ISO 格式日期 (YYYY-MM-DD)
  final VoidCallback? onClose; // 點擊右上角 ✕ 關閉/收起卡片的回調
  final VoidCallback? onNavigateToDiary; // 點擊「查看完整飲食日記」的回調
  final ValueChanged<String>? onAddRecordForDate; // 點擊「＋ 補記這天的飲食」的回調

  const MealRecordCard({
    super.key,
    required this.queryDate,
    this.onClose,
    this.onNavigateToDiary,
    this.onAddRecordForDate,
  });

  @override
  State<MealRecordCard> createState() => _MealRecordCardState();
}

/// MealRecordCard 之狀態管理類別。
class _MealRecordCardState extends State<MealRecordCard> {
  final DietService _dietService = DietService();
  bool _isLoading = true;
  List<dynamic> _records = [];
  bool _isClosed = false;

  /// 初始化 Widget 狀態與動畫控制器。
  @override
  /// 執行 initState 之專屬功能操作。
  void initState() {
    super.initState();
    _fetchRecords();
  }

  @override
  /// 執行 didUpdateWidget 之專屬功能操作。
  void didUpdateWidget(covariant MealRecordCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queryDate != widget.queryDate) {
      _fetchRecords();
    }
  }

  /// 向 DietService 載入特定日期之歷史飲食紀錄數據。
  Future<void> _fetchRecords() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final list = await _dietService.getDietRecordsByDate(widget.queryDate);
      if (mounted) {
        setState(() {
          _records = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _records = [];
          _isLoading = false;
        });
      }
    }
  }

  // 安全提取熱量數值（相容頂層 calories、嵌套 nutrition.calories 以及帶有 "481.21 kcal" 單位之字串）
  double? _extractCalories(dynamic rec) {
    if (rec is! Map) return null;

    dynamic rawCal = rec['nutrition'] is Map ? rec['nutrition']['calories'] : null;
    rawCal ??= rec['calories'];

    if (rawCal == null) return null;

    final str = rawCal.toString();
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(str);
    if (match != null) {
      return double.tryParse(match.group(1) ?? '');
    }
    return double.tryParse(str);
  }

  // 計算當天總大卡熱量
  /// 計算特定日期飲食紀錄之攝取熱量總和（kcal）。
  double _calculateTotalCalories() {
    double total = 0.0;
    for (var rec in _records) {
      final cal = _extractCalories(rec);
      if (cal != null) {
        total += cal;
      }
    }
    return total;
  }

  // 將飲食紀錄依餐期 (BREAKFAST, LUNCH, DINNER, OTHER) 分組
  Map<String, List<Map<String, dynamic>>> _groupRecordsByPeriod() {
    final Map<String, List<Map<String, dynamic>>> grouped = {
      'BREAKFAST': [],
      'LUNCH': [],
      'DINNER': [],
      'OTHER': [],
    };

    for (var rec in _records) {
      if (rec is Map<String, dynamic>) {
        final rawType = (rec['mealType'] ?? rec['meal'] ?? 'OTHER').toString().toUpperCase();
        String periodKey = 'OTHER';
        if (rawType.contains('BREAKFAST') || rawType.contains('早餐')) {
          periodKey = 'BREAKFAST';
        } else if (rawType.contains('LUNCH') || rawType.contains('午餐')) {
          periodKey = 'LUNCH';
        } else if (rawType.contains('DINNER') || rawType.contains('晚餐')) {
          periodKey = 'DINNER';
        }
        grouped[periodKey]!.add(rec);
      }
    }
    return grouped;
  }

  /// 依據餐期 Key 取得帶有圖示之中文標題名稱。
  String _getPeriodLabel(String key) {
    switch (key) {
      case 'BREAKFAST':
        return '🍳 早餐';
      case 'LUNCH':
        return '🍱 午餐';
      case 'DINNER':
        return '🍜 晚餐';
      default:
        return '🍪 點心 / 其他';
    }
  }

  /// 繪製並傳回當前 Widget 之 UI 畫面架構。
  @override
  /// 建立  區塊之視覺 UI 視圖元件。
  Widget build(BuildContext context) {
    if (_isClosed) return const SizedBox.shrink();

    final totalCalories = _calculateTotalCalories();
    final groupedRecords = _groupRecordsByPeriod();
    final hasRecords = _records.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 8.0, bottom: 4.0),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: AppColors.surface, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- 1. 卡片 Header 標頭區 ---
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
              decoration: const BoxDecoration(
                color: AppColors.surface,
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 16.0, color: AppColors.primary),
                  const SizedBox(width: 6.0),
                  Expanded(
                    child: Text(
                      '${widget.queryDate} 飲食紀錄',
                      style: const TextStyle(
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  if (hasRecords) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: Text(
                        '🔥 ${totalCalories.toStringAsFixed(0)} kcal',
                        style: const TextStyle(
                          fontSize: 12.0,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6.0),
                  ],
                  // 右上角關閉按鈕 (✕)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isClosed = true;
                      });
                      if (widget.onClose != null) {
                        widget.onClose!();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(2.0),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 16.0,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // --- 2. 卡片 Body 內容區 ---
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(20.0),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                    ),
                  ),
                ),
              )
            else if (!hasRecords)
              // 空狀態 (Empty State)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '🍽️',
                      style: TextStyle(fontSize: 28),
                    ),
                    const SizedBox(height: 6.0),
                    const Text(
                      '該天尚未記錄任何飲食內容喔！',
                      style: TextStyle(
                        fontSize: 13.0,
                        color: Colors.black54,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12.0),
                    InkWell(
                      onTap: () {
                        if (widget.onAddRecordForDate != null) {
                          widget.onAddRecordForDate!(widget.queryDate);
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '＋ 補記這天的飲食',
                          style: TextStyle(
                            fontSize: 12.0,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              // 有紀錄時按餐期顯示明細
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: groupedRecords.entries
                      .where((entry) => entry.value.isNotEmpty)
                      .map((entry) {
                    final periodTitle = _getPeriodLabel(entry.key);
                    final periodItems = entry.value;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            periodTitle,
                            style: const TextStyle(
                              fontSize: 12.0,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 4.0),
                          ...periodItems.map((item) {
                            final name = (item['dishName'] ?? item['dish_name'] ?? '餐點').toString();
                            final amount = item['amount'] ?? 1;
                            final calVal = _extractCalories(item);
                            final calStr = calVal != null
                                ? '${calVal.toStringAsFixed(0)} kcal'
                                : '';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 4.0),
                              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(color: AppColors.border.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '$name x $amount',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (calStr.isNotEmpty)
                                    Text(
                                      calStr,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

            // --- 3. 卡片 Footer 導航區 ---
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.surface, width: 1.0),
                ),
              ),
              child: InkWell(
                onTap: () {
                  if (widget.onNavigateToDiary != null) {
                    widget.onNavigateToDiary!();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Text(
                        '查看完整飲食日記',
                        style: TextStyle(
                          fontSize: 12.0,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(width: 4.0),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 11.0,
                        color: AppColors.primary,
                      ),
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
}
