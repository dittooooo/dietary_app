import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../color/app_colors.dart';
import '../../controllers/dog_state_controller.dart';
import '../../services/diet_service.dart';
import '../../widgets/body_transition_animation_dialog.dart';
import '../../widgets/dog_avatar.dart';
import '../records/report_page.dart';

/// 管理者專用之測試工具箱與開發者除錯主控制頁面。
class AdminTestToolsPage extends StatefulWidget {
  const AdminTestToolsPage({super.key});

  @override
  State<AdminTestToolsPage> createState() => _AdminTestToolsPageState();
}

/// 測試工具箱頁面之測試任務執行狀態與日誌輸出管理。
class _AdminTestToolsPageState extends State<AdminTestToolsPage> {
  DogBodyType _oldBodyType = DogBodyType.normal;
  DogBodyType _newBodyType = DogBodyType.heavy;
  String _reportDateMode = 'YESTERDAY';
  bool _isLoadingReport = false;

  /// 繪製並傳回當前 Widget 之 UI 畫面架構。
  @override
  /// 建立  區塊之視覺 UI 視圖元件。
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          '管理者測試工具',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildToolCard(
            title: '體型變化動畫',
            children: [
              _buildBodyTypePicker(
                label: '原本體型',
                value: _oldBodyType,
                onChanged: (value) => setState(() => _oldBodyType = value),
              ),
              const SizedBox(height: 10),
              _buildBodyTypePicker(
                label: '新的體型',
                value: _newBodyType,
                onChanged: (value) => setState(() => _newBodyType = value),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showBodyTransitionTest,
                  icon: const Icon(Icons.play_arrow, color: Colors.white),
                  label: const Text(
                    '播放測試動畫',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: _primaryButtonStyle(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildToolCard(
            title: '飲食總結報告',
            children: [
              DropdownButtonFormField<String>(
                initialValue: _reportDateMode,
                decoration: InputDecoration(
                  labelText: '報告日期',
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'YESTERDAY', child: Text('昨日')),
                  DropdownMenuItem(value: 'TODAY', child: Text('今日')),
                  DropdownMenuItem(value: 'WEEK', child: Text('本周')),
                ],
                onChanged: _isLoadingReport
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _reportDateMode = value);
                        }
                      },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoadingReport ? null : _showDietSummaryReport,
                  icon: _isLoadingReport
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.insert_chart, color: Colors.white),
                  label: Text(
                    _isLoadingReport ? '載入中...' : '顯示報告',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: _primaryButtonStyle(
                    disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 建立 ToolCard 區塊之視覺 UI 視圖元件。
  Widget _buildToolCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  ButtonStyle _primaryButtonStyle({Color? disabledBackgroundColor}) {
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      disabledBackgroundColor: disabledBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  /// 建立 BodyTypePicker 區塊之視覺 UI 視圖元件。
  Widget _buildBodyTypePicker({
    required String label,
    required DogBodyType value,
    required ValueChanged<DogBodyType> onChanged,
  }) {
    return DropdownButtonFormField<DogBodyType>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      items: DogBodyType.values
          .map(
            (type) => DropdownMenuItem(
              value: type,
              child: Text(_bodyTypeLabel(type)),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }

  /// 將體態 Enum 轉譯為單字中文標籤（瘦、標準、壯、胖）。
  String _bodyTypeLabel(DogBodyType bodyType) {
    switch (bodyType) {
      case DogBodyType.thin:
        return '瘦';
      case DogBodyType.normal:
        return '標準';
      case DogBodyType.muscle:
        return '壯';
      case DogBodyType.heavy:
        return '胖';
    }
  }

  /// 彈出對話視窗以進行 BodyTransitionTest 相關操作與資料確認。
  void _showBodyTransitionTest() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return BodyTransitionAnimationDialog(
          oldBodyType: _oldBodyType,
          newBodyType: _newBodyType,
        );
      },
    );
  }

  /// 彈出對話視窗以進行 DietSummaryReport 相關操作與資料確認。
  Future<void> _showDietSummaryReport() async {
    setState(() => _isLoadingReport = true);

    try {
      final records = await DietService().getMyDietRecords();
      if (_reportDateMode == 'WEEK') {
        if (!mounted) return;
        setState(() => _isLoadingReport = false);
        _showWeeklyDietSummaryDialog();
        return;
      }
      final targetDate = _targetReportDate();
      final summary = _buildDietSummaryForDate(records, targetDate);

      if (!mounted) return;
      setState(() => _isLoadingReport = false);
      _showDietSummaryDialog(
        date: targetDate,
        calories: summary.calories,
        protein: summary.protein,
        fat: summary.fat,
        carbs: summary.carbs,
        dishes: summary.dishes,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingReport = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('載入飲食報告失敗，請稍後再試')),
      );
    }
  }

  DateTime _targetReportDate() {
    final today = DateTime.now();
    return _reportDateMode == 'TODAY'
        ? today
        : today.subtract(const Duration(days: 1));
  }

  /// 顯示內嵌週飲食摘要報告的對話視窗。
  void _showWeeklyDietSummaryDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 430,
          height: MediaQuery.of(context).size.height * 0.86,
          child: Column(
            children: [
              const Expanded(
                child: ReportPage(
                  initialViewType: 1,
                  embedded: true,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      '太棒了，我知道了！',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _DietSummary _buildDietSummaryForDate(
    List<dynamic> records,
    DateTime targetDate,
  ) {
    double calories = 0;
    double protein = 0;
    double fat = 0;
    double carbs = 0;
    final dishes = <String>[];

    for (final record in records) {
      final recordDate = _getRecordDate(record);
      if (recordDate == null || !_isSameDate(recordDate, targetDate)) continue;

      calories += _getCaloriesFromRecord(record);
      protein += _getNutrientFromRecord(record, r'(?:蛋白質|protein)');
      fat += _getNutrientFromRecord(record, r'(?:脂肪|fat)');
      carbs += _getNutrientFromRecord(
        record,
        r'(?:碳水化合物|碳水|carbohydrate|carbs)',
      );

      final dishName = record['dishName'];
      if (dishName != null && dishName.toString().trim().isNotEmpty) {
        dishes.add(dishName.toString());
      }
    }

    return _DietSummary(
      calories: calories,
      protein: protein,
      fat: fat,
      carbs: carbs,
      dishes: dishes,
    );
  }

  /// 執行 isSameDate 之專屬功能操作。
  bool _isSameDate(DateTime date, DateTime targetDate) {
    return date.year == targetDate.year &&
        date.month == targetDate.month &&
        date.day == targetDate.day;
  }

  DateTime? _getRecordDate(dynamic record) {
    if (record == null) return null;

    for (final key in const ['date', 'mealDate', 'createdAt']) {
      final parsedDate = _parseDateValue(record[key]);
      if (parsedDate != null) return parsedDate;
    }

    return null;
  }

  DateTime? _parseDateValue(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    if (value is List && value.length >= 3) {
      final year = int.tryParse(value[0].toString());
      final month = int.tryParse(value[1].toString());
      final day = int.tryParse(value[2].toString());
      if (year != null && month != null && day != null) {
        return DateTime(year, month, day);
      }
    }
    if (value is Map) {
      final year = int.tryParse('${value['year'] ?? value['yearValue'] ?? ''}');
      final month =
          int.tryParse('${value['month'] ?? value['monthValue'] ?? ''}');
      final day =
          int.tryParse('${value['day'] ?? value['dayOfMonth'] ?? ''}');
      if (year != null && month != null && day != null) {
        return DateTime(year, month, day);
      }
    }
    return null;
  }

  /// 向伺服器或本地快取加載 CaloriesFromRecord 之數據內容。
  double _getCaloriesFromRecord(dynamic record) {
    if (record == null) return 0;
    final nutritionValue = _nutritionValue(record, 'calories');
    if (nutritionValue != null) return nutritionValue;

    final combined = '${record['dishName'] ?? ''} ${record['description'] ?? ''}';
    final match = RegExp(
      r'(\d+(?:\.\d+)?)\s*(?:kcal|千卡|卡)',
      caseSensitive: false,
    ).firstMatch(combined);
    if (match != null) {
      return double.tryParse(match.group(1) ?? '') ?? 0;
    }

    return record['dishName']?.toString().trim().isNotEmpty == true ? 400 : 0;
  }

  /// 向伺服器或本地快取加載 NutrientFromRecord 之數據內容。
  double _getNutrientFromRecord(dynamic record, String pattern) {
    if (record == null) return 0;
    String key = '';
    if (pattern.contains('蛋白質') || pattern.contains('protein')) {
      key = 'protein';
    } else if (pattern.contains('脂肪') || pattern.contains('fat')) {
      key = 'fat';
    } else if (pattern.contains('碳水') || pattern.contains('carb')) {
      key = 'carbohydrates';
    }

    final directValue = _nutritionValue(record, key);
    if (directValue != null) return directValue;

    final nutrition = record['nutrition']?.toString() ?? '';
    final match = RegExp(
      '$pattern:\\s*(\\d+(?:\\.\\d+)?)',
      caseSensitive: false,
    ).firstMatch(nutrition);
    return match == null ? 0 : double.tryParse(match.group(1) ?? '') ?? 0;
  }

  double? _nutritionValue(dynamic record, String key) {
    final nutrition = record['nutrition'];
    if (nutrition is Map && nutrition[key] != null) {
      return _firstNumber(nutrition[key]);
    }
    if (nutrition is String && nutrition.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(nutrition);
        if (decoded is Map && decoded[key] != null) {
          return _firstNumber(decoded[key]);
        }
      } catch (_) {}
    }
    return null;
  }

  double? _firstNumber(dynamic value) {
    if (value is num) return value.toDouble();
    final match = RegExp(r'(\d+(?:\.\d+)?)').firstMatch('${value ?? ''}');
    return match == null ? null : double.tryParse(match.group(1) ?? '');
  }

  /// 彈出對話視窗以進行 DietSummaryDialog 相關操作與資料確認。
  void _showDietSummaryDialog({
    required DateTime date,
    required double calories,
    required double protein,
    required double fat,
    required double carbs,
    required List<String> dishes,
  }) {
    final dateStr = '${date.month}/${date.day}';
    final isToday = _isSameDate(date, DateTime.now());
    final dateLabel = isToday ? '今天' : '昨天';
    final comment = dishes.isEmpty
        ? '$dateLabel沒有記錄任何飲食。記得補記錄，我才能為您做評估喔。'
        : '$dateLabel記錄了：${dishes.join('、')}。總熱量為 ${calories.toStringAsFixed(0)} kcal。請繼續保持健康飲食！';

    SystemChannels.textInput.invokeMethod('TextInput.hide');
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();

    final pCal = protein * 4;
    final fCal = fat * 9;
    final cCal = carbs * 4;
    final macroTotalCal = pCal + fCal + cCal;

    var carbsPercent = 0;
    var proteinPercent = 0;
    var fatPercent = 0;

    if (macroTotalCal > 0) {
      carbsPercent = ((cCal / macroTotalCal) * 100).round();
      proteinPercent = ((pCal / macroTotalCal) * 100).round();
      fatPercent = 100 - carbsPercent - proteinPercent;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: AppColors.background,
          elevation: 10,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                Text(
                  '$dateStr 飲食總結報告',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: 320,
                  height: 270,
                  child: DogAvatar(
                    controller: DogStateController.instance,
                    scale: 3.2,
                    instanceId: 'admin-summary-dialog-dog',
                  ),
                ),
                _buildCalorieArcGaugeCard(calories.round(), dateLabel),
                const SizedBox(height: 8),
                _buildMacronutrientBarChartCard(
                  dateLabel: dateLabel,
                  carbsPercent: carbsPercent,
                  proteinPercent: proteinPercent,
                  fatPercent: fatPercent,
                  carbs: carbs,
                  protein: protein,
                  fat: fat,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Text(
                    comment,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textPrimary.withValues(alpha: 0.85),
                      height: 1.3,
                    ),
                  ),
                ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                  child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.background,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '太棒了，我知道了！',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 建立 CalorieArcGaugeCard 區塊之視覺 UI 視圖元件。
  Widget _buildCalorieArcGaugeCard(int currentCalories, String dateLabel) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$dateLabel熱量',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: SizedBox(
              width: 190,
              height: 95,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  CustomPaint(
                    size: const Size(190, 95),
                    painter: _AdminCalorieGaugeArcPainter(
                      currentCalories: currentCalories.toDouble(),
                    ),
                  ),
                  Positioned(
                    bottom: 6,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '約',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          _formatInt(currentCalories),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                            height: 1.1,
                          ),
                        ),
                        const Text(
                          'kcal',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildGaugeZoneLabel('偏低', '< 1,700 kcal', const Color(0xFF7C83FD)),
              _buildGaugeZoneLabel('適量', '1,700 - 2,000 kcal', const Color(0xFF52C41A)),
              _buildGaugeZoneLabel('偏高', '> 2,000 kcal', const Color(0xFFFF7A45)),
            ],
          ),
        ],
      ),
    );
  }

  /// 執行 formatInt 之專屬功能操作。
  String _formatInt(int value) {
    return value.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (match) => '${match[1]},',
        );
  }

  /// 建立 GaugeZoneLabel 區塊之視覺 UI 視圖元件。
  Widget _buildGaugeZoneLabel(String zoneTitle, String rangeStr, Color color) {
    return Column(
      children: [
        Text(
          zoneTitle,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          rangeStr,
          style: const TextStyle(
            fontSize: 9,
            color: Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// 建立 MacronutrientBarChartCard 區塊之視覺 UI 視圖元件。
  Widget _buildMacronutrientBarChartCard({
    required String dateLabel,
    required int carbsPercent,
    required int proteinPercent,
    required int fatPercent,
    required double carbs,
    required double protein,
    required double fat,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$dateLabel三大營養素比例',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Column(
            children: [
              SizedBox(
                height: 84,
                child: Stack(
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildDashedGridLine('100%'),
                        _buildDashedGridLine('75%'),
                        _buildDashedGridLine('50%'),
                        _buildDashedGridLine('25%'),
                        _buildDashedGridLine('0%'),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 40, right: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _buildSingleBarItem(carbsPercent, const Color(0xFF7C83FD)),
                          _buildSingleBarItem(proteinPercent, const Color(0xFFFF7A45)),
                          _buildSingleBarItem(fatPercent, const Color(0xFFFFB800)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 40, right: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMacroLabelItem('碳水化合物', carbs),
                    _buildMacroLabelItem('蛋白質', protein),
                    _buildMacroLabelItem('脂肪', fat),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 建立 MacroLabelItem 區塊之視覺 UI 視圖元件。
  Widget _buildMacroLabelItem(String label, double grams) {
    return SizedBox(
      width: 62,
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            '約 ${grams.round()} g',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 建立 DashedGridLine 區塊之視覺 UI 視圖元件。
  Widget _buildDashedGridLine(String label) {
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.black45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ],
    );
  }

  /// 建立 SingleBarItem 區塊之視覺 UI 視圖元件。
  Widget _buildSingleBarItem(int pct, Color color) {
    const plotHeight = 84.0;
    final barHeight =
        (pct / 100.0 * plotHeight).clamp(4.0, plotHeight).toDouble();
    final labelBottom =
        (barHeight + 3).clamp(4.0, plotHeight - 14).toDouble();

    return SizedBox(
      width: 62,
      height: plotHeight,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Positioned(
            bottom: 0,
            child: Container(
              width: 38,
              height: barHeight,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: labelBottom,
            child: Text(
              '$pct%',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 執行 DietSummary 之專屬功能操作。
class _DietSummary {
  final double calories;
  final double protein;
  final double fat;
  final double carbs;
  final List<String> dishes;

  const _DietSummary({
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.dishes,
  });
}

/// 執行 AdminCalorieGaugeArcPainter 之專屬功能操作。
class _AdminCalorieGaugeArcPainter extends CustomPainter {
  final double currentCalories;

  const _AdminCalorieGaugeArcPainter({required this.currentCalories});

  @override
  /// 執行 paint 之專屬功能操作。
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 10);
    final radius = size.width / 2 - 20;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const strokeWidth = 22.0;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    const startAngle = math.pi;
    const totalAngle = math.pi;
    const seg1Angle = totalAngle * 0.38;
    const seg2Angle = totalAngle * 0.34;
    const seg3Angle = totalAngle * 0.28;

    paint.color = const Color(0xFF7C83FD);
    canvas.drawArc(rect, startAngle, seg1Angle, false, paint);

    paint.color = const Color(0xFF52C41A);
    canvas.drawArc(rect, startAngle + seg1Angle, seg2Angle, false, paint);

    paint.color = const Color(0xFFFF7A45);
    canvas.drawArc(
      rect,
      startAngle + seg1Angle + seg2Angle,
      seg3Angle,
      false,
      paint,
    );

    double progressRatio;
    if (currentCalories < 1700) {
      progressRatio = (currentCalories / 1700.0).clamp(0.0, 1.0) * 0.38;
    } else if (currentCalories <= 2000) {
      progressRatio =
          0.38 + ((currentCalories - 1700.0) / 300.0).clamp(0.0, 1.0) * 0.34;
    } else {
      progressRatio =
          0.72 + ((currentCalories - 2000.0) / 1000.0).clamp(0.0, 1.0) * 0.28;
    }

    final knobAngle = startAngle + progressRatio * totalAngle;
    final knobX = center.dx + radius * math.cos(knobAngle);
    final knobY = center.dy + radius * math.sin(knobAngle);

    canvas.drawCircle(
      Offset(knobX, knobY),
      11,
      Paint()
        ..color = Colors.black26
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawCircle(Offset(knobX, knobY), 9, Paint()..color = Colors.white);

    Color dotColor;
    if (currentCalories < 1700) {
      dotColor = const Color(0xFF7C83FD);
    } else if (currentCalories <= 2000) {
      dotColor = const Color(0xFF52C41A);
    } else {
      dotColor = const Color(0xFFFF7A45);
    }
    canvas.drawCircle(Offset(knobX, knobY), 5, Paint()..color = dotColor);
  }

  @override
  /// 執行 shouldRepaint 之專屬功能操作。
  bool shouldRepaint(covariant _AdminCalorieGaugeArcPainter oldDelegate) {
    return oldDelegate.currentCalories != currentCalories;
  }
}
