import 'dart:async';

import 'package:flutter/material.dart';

import '../../color/app_colors.dart';
import '../../services/diet_service.dart';
import '../../services/dish_search_service.dart';
import '../../utils/friendly_error_message.dart';

class _NutritionValues {
  const _NutritionValues({
    this.calories,
    this.protein,
    this.fat,
    this.carbohydrates,
  });

  final double? calories;
  final double? protein;
  final double? fat;
  final double? carbohydrates;

  String toNutritionText() => [
    if (calories != null) '熱量 $calories kcal',
    if (protein != null) '蛋白質 $protein g',
    if (fat != null) '脂肪 $fat g',
    if (carbohydrates != null) '碳水化合物 $carbohydrates g',
  ].join('，');
}

class _SelectedFood {
  const _SelectedFood({
    required this.id,
    required this.name,
    required this.unitLabel,
    required this.isManual,
    required this.nutrition,
  });

  final String id;
  final String name;
  final String unitLabel;
  final bool isManual;
  final _NutritionValues nutrition;
}

class _EditorResult {
  const _EditorResult({required this.name, required this.nutrition});

  final String name;
  final _NutritionValues nutrition;
}

class ManualRecordPage extends StatefulWidget {
  const ManualRecordPage({super.key, this.initialDate});

  final DateTime? initialDate;

  @override
  State<ManualRecordPage> createState() => _ManualRecordPageState();
}

class _ManualRecordPageState extends State<ManualRecordPage> {
  final _searchController = TextEditingController();
  final _searchService = DishSearchService();
  final _selectedItems = <_SelectedFood>[];

  Timer? _searchDebounce;
  DateTime _selectedDate = DateTime.now();
  String _mealType = '早餐';
  String _selectedTab = 'food';
  List<DishSearchResult> _results = const [];
  bool _isSearching = false;
  bool _isSaving = false;
  String? _searchError;

  static const _mealOptions = ['早餐', '午餐', '晚餐', '其他'];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _mealType = _automaticMealType();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String _automaticMealType() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 11) return '早餐';
    if (hour >= 11 && hour < 17) return '午餐';
    return '晚餐';
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      setState(() {
        _results = const [];
        _searchError = null;
        _isSearching = false;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      _search(trimmedQuery);
    });
  }

  Future<void> _search(String query) async {
    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final results = await _searchService.search(query);
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() => _results = results);
    } catch (_) {
      if (!mounted || _searchController.text.trim() != query) return;
      setState(() {
        _results = const [];
        _searchError = '搜尋暫時失敗，請確認 GraphRAG 服務已啟動。';
      });
    } finally {
      if (mounted && _searchController.text.trim() == query) {
        setState(() => _isSearching = false);
      }
    }
  }

  List<DishSearchResult> get _visibleResults => _results
      .where((item) => _selectedTab == 'dish' ? item.isDish : !item.isDish)
      .toList();

  _SelectedFood? _selectedFor(String id) {
    for (final item in _selectedItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  void _toggleSelection(DishSearchResult item) {
    setState(() {
      final index = _selectedItems.indexWhere((selected) => selected.id == item.id);
      if (index >= 0) {
        _selectedItems.removeAt(index);
      } else {
        _selectedItems.add(_SelectedFood(
          id: item.id,
          name: item.name,
          unitLabel: item.unitLabel,
          isManual: false,
          nutrition: _NutritionValues(calories: item.calories),
        ));
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.secondary),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) setState(() => _selectedDate = picked);
  }

  Future<void> _addManualItem() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    final result = await _showNutritionEditor(
      initialName: query,
      initialNutrition: const _NutritionValues(),
    );
    if (result == null || !mounted) return;

    final unitLabel = _selectedTab == 'dish' ? '1份' : '100克';
    setState(() {
      _selectedItems.add(_SelectedFood(
        id: 'manual-${DateTime.now().microsecondsSinceEpoch}',
        name: result.name,
        unitLabel: unitLabel,
        isManual: true,
        nutrition: result.nutrition,
      ));
    });
  }

  Future<_EditorResult?> _showNutritionEditor({
    required String initialName,
    required _NutritionValues initialNutrition,
  }) async {
    final nameController = TextEditingController(text: initialName);
    final caloriesController = TextEditingController(text: _numberText(initialNutrition.calories));
    final proteinController = TextEditingController(text: _numberText(initialNutrition.protein));
    final fatController = TextEditingController(text: _numberText(initialNutrition.fat));
    final carbohydratesController = TextEditingController(text: _numberText(initialNutrition.carbohydrates));
    String? error;

    final result = await showDialog<_EditorResult>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('手動新增營養資訊'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '資料庫沒有這項食物，請填寫四項營養資訊。',
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 14),
                _buildEditorField('名稱', nameController),
                _buildEditorField('熱量（kcal）', caloriesController),
                _buildEditorField('蛋白質（g）', proteinController),
                _buildEditorField('脂肪（g）', fatController),
                _buildEditorField('碳水化合物（g）', carbohydratesController),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final nutrition = _NutritionValues(
                  calories: double.tryParse(caloriesController.text.trim()),
                  protein: double.tryParse(proteinController.text.trim()),
                  fat: double.tryParse(fatController.text.trim()),
                  carbohydrates: double.tryParse(carbohydratesController.text.trim()),
                );
                final hasAllValues = nutrition.calories != null &&
                    nutrition.protein != null &&
                    nutrition.fat != null &&
                    nutrition.carbohydrates != null;
                if (nameController.text.trim().isEmpty || !hasAllValues) {
                  setDialogState(() => error = '請填寫名稱與四項有效數值。');
                  return;
                }
                Navigator.pop(context, _EditorResult(name: nameController.text.trim(), nutrition: nutrition));
              },
              child: const Text('套用'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    caloriesController.dispose();
    proteinController.dispose();
    fatController.dispose();
    carbohydratesController.dispose();
    return result;
  }

  String _numberText(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble() ? value.toInt().toString() : value.toString();
  }

  Widget _buildEditorField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: label == '名稱'
            ? TextInputType.text
            : const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }

  Future<void> _saveSelectedItems() async {
    if (_selectedItems.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);

    final dietService = DietService();
    var savedCount = 0;
    try {
      for (final item in _selectedItems) {
        final result = await dietService.createDietRecord(
          dishName: item.name,
          mealType: _mealType,
          amount: 1,
          nutrition: item.nutrition.toNutritionText(),
          description: '${item.isManual ? '手動新增' : '系統搜尋'}（${item.unitLabel}）',
          mealDate: _selectedDate,
          fetchNutritionIfMissing: false,
        );
        if (result['success'] == true) savedCount++;
      }

      if (!mounted) return;
      if (savedCount == _selectedItems.length) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已儲存 $savedCount 項，部分項目未能儲存。')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(FriendlyErrorMessage.dietRecord)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F4),
      appBar: AppBar(
        toolbarHeight: 88,
        backgroundColor: const Color(0xFFF7F7F4),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.secondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: _showMealPicker,
              icon: const Icon(Icons.arrow_drop_down, size: 20),
              label: Text(_mealType, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              style: TextButton.styleFrom(foregroundColor: AppColors.secondary, padding: EdgeInsets.zero),
            ),
            InkWell(
              onTap: _pickDate,
              child: Text(
                '${_selectedDate.year}年${_selectedDate.month}月${_selectedDate.day}日',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ),
          ],
        ),
        titleSpacing: 0,
      ),
      body: Column(
        children: [
          _buildTabs(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (query) {
                setState(() {});
                _onSearchChanged(query);
              },
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: _selectedTab == 'dish' ? '搜尋食譜' : '搜尋食材',
                prefixIcon: const Icon(Icons.search, color: Colors.black),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                        icon: const Icon(Icons.cancel, color: Colors.black54),
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: const BorderSide(color: Color(0xFFD0D0D0), width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: const BorderSide(color: Color(0xFFD0D0D0), width: 2),
                ),
              ),
            ),
          ),
          Expanded(child: _buildResultArea()),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        child: SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: _selectedItems.isEmpty || _isSaving ? null : _saveSelectedItems,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              disabledBackgroundColor: const Color(0xFFD9D9D3),
              shape: const StadiumBorder(),
            ),
            child: _isSaving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text(
                    _selectedItems.isEmpty ? '請選擇食物' : '儲存 ${_selectedItems.length} 項',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      color: AppColors.secondary,
      child: Row(children: [_buildTab('dish', '食譜'), _buildTab('food', '食材')]),
    );
  }

  Widget _buildTab(String tab, String label) {
    final isActive = _selectedTab == tab;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTab = tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            border: isActive ? const Border(bottom: BorderSide(color: Colors.white, width: 3)) : null,
          ),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: isActive ? Colors.white : Colors.white60, fontSize: 17, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _buildResultArea() {
    if (_isSearching) return const Center(child: CircularProgressIndicator(color: AppColors.secondary));
    if (_searchError != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_searchError!, textAlign: TextAlign.center)));
    if (_searchController.text.trim().isEmpty) return const Center(child: Text('輸入名稱，搜尋食譜或食材', style: TextStyle(color: Colors.black54)));

    final results = _visibleResults;
    if (results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('資料庫找不到這項食物', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('要不要手動新增四項營養資訊？', style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _addManualItem,
                icon: const Icon(Icons.add),
                label: const Text('手動新增'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 20),
      itemBuilder: (context, index) {
        final item = results[index];
        final selected = _selectedFor(item.id);
        final calories = selected?.nutrition.calories ?? item.calories;
        final calorieText = calories == null ? '約略熱量暫無資料' : '約 ${calories.round()} 大卡';
        return ListTile(
          onTap: () => _toggleSelection(item),
          contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 6),
          title: Text(item.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text('${item.unitLabel}  ·  $calorieText', style: const TextStyle(color: AppColors.success, fontSize: 15)),
          ),
          trailing: Icon(
            selected == null ? Icons.radio_button_unchecked : Icons.check_circle,
            color: selected == null ? Colors.black26 : AppColors.success,
            size: 28,
          ),
        );
      },
    );
  }

  void _showMealPicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _mealOptions.map((meal) => ListTile(
            title: Text(meal, textAlign: TextAlign.center),
            onTap: () {
              setState(() => _mealType = meal);
              Navigator.pop(context);
            },
          )).toList(),
        ),
      ),
    );
  }
}
