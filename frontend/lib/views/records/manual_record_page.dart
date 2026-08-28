import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../color/app_colors.dart';
import '../../services/diet_service.dart';
import '../../utils/friendly_error_message.dart';
import 'elf_feeding_page.dart';
import 'simple_camera_page.dart';

class _ManualRecordItem {
  final TextEditingController nameController;
  final TextEditingController portionController;
  DateTime selectedDate;
  String mealType;
  XFile? selectedImage;
  Uint8List? imageBytes;
  bool isExpanded;

  _ManualRecordItem({
    required this.nameController,
    required this.portionController,
    required this.selectedDate,
    required this.mealType,
    // this.selectedImage,
    // this.imageBytes,
    this.isExpanded = true,
  });
}

class ManualRecordPage extends StatefulWidget {
  final DateTime? initialDate;
  const ManualRecordPage({super.key, this.initialDate});

  @override
  State<ManualRecordPage> createState() => _ManualRecordPageState();
}

class _ManualRecordPageState extends State<ManualRecordPage> {
  final List<_ManualRecordItem> _items = [];
  final List<String> _mealOptions = ['早餐', '午餐', '晚餐', '其他'];
  final ImagePicker _picker = ImagePicker();
  final ScrollController _scrollController = ScrollController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _addNewItem();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _getAutoMealType() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 11) return '早餐';
    if (hour >= 11 && hour < 17) return '午餐';
    return '晚餐';
  }

  void _addNewItem() {
    setState(() {
      _items.add(_ManualRecordItem(
        nameController: TextEditingController(),
        portionController: TextEditingController(text: '1'),
        selectedDate: widget.initialDate ?? DateTime.now(),
        mealType: _getAutoMealType(),
        isExpanded: true,
      ));
    });
  }

  void _removeItem(int index) {
    if (_items.length > 1) {
      setState(() {
        _items.removeAt(index);
      });
    }
  }

  Future<void> _selectDateFor(int index) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _items[index].selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _items[index].selectedDate = picked);
    }
  }

  void _showMealPickerFor(int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _mealOptions
              .map((m) => ListTile(
                    title: Text(
                      m,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: _items[index].mealType == m
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    onTap: () {
                      setState(() => _items[index].mealType = m);
                      Navigator.pop(context);
                    },
                  ))
              .toList(),
        ),
      ),
    );
  }

  Future<void> _pickImageFor(int index) async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
              title: const Text('相機拍照', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('相簿選擇', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      if (source == ImageSource.camera) {
        if (!mounted) return;
        final XFile? photo = await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SimpleCameraPage()),
        );
        if (photo != null) {
          final bytes = await photo.readAsBytes();
          setState(() {
            _items[index].selectedImage = photo;
            _items[index].imageBytes = bytes;
          });
        }
      } else {
        final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
        if (image != null) {
          final bytes = await image.readAsBytes();
          setState(() {
            _items[index].selectedImage = image;
            _items[index].imageBytes = bytes;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(FriendlyErrorMessage.upload)),
        );
      }
    }
  }

  Future<void> _submit() async {
    final validItems = _items.where((item) => item.nameController.text.trim().isNotEmpty).toList();

    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請至少輸入一項餐點名稱！')),
      );
      return;
    }

    setState(() => _isSaving = true);

    List<Map<String, String>> elfItems = [];
    List<String> failedMessages = [];
    String? firstImagePath;

    try {
      for (int i = 0; i < validItems.length; i++) {
        final item = validItems[i];
        final name = item.nameController.text.trim();
        final pText = item.portionController.text.trim();
        final pVal = double.tryParse(pText);
        String cleanP = '1';
        if (pVal != null) {
          cleanP = pVal == pVal.toInt() ? pVal.toInt().toString() : pVal.toString();
        }
        final amountText = '$cleanP 份';

        final result = await DietService().createDietRecord(
          dishName: name,
          mealType: item.mealType,
          amount: amountText,
          description: '手動輸入飲食紀錄',
          mealDate: item.selectedDate,
        );

        if (result['success'] == true) {
          final recordData = result['data'];
          final int? recordId = recordData?['id'];

          if (recordId != null && item.imageBytes != null && item.selectedImage != null) {
            DietService()
                .uploadDietPhoto(recordId, item.imageBytes!, item.selectedImage!.name)
                .catchError((e) {
              debugPrint('背景上傳圖片失敗: $e');
              return {'success': false, 'message': e.toString()};
            });
          }

          if (firstImagePath == null && item.selectedImage != null) {
            firstImagePath = item.selectedImage!.path;
          }

          final double? calVal = recordData != null
              ? double.tryParse((recordData['calories'] ?? '').toString())
              : null;

          elfItems.add({
            'name': name,
            'portion': '${cleanP}份',
            'calories': calVal != null ? '$calVal kcal' : '-- kcal',
          });
        } else {
          final msg = result['message'] ?? '寫入資料庫失敗';
          failedMessages.add('$name ($msg)');
        }
      }

      if (mounted) {
        if (failedMessages.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('新增飲食紀錄失敗：${failedMessages.join("；")}'),
              duration: const Duration(seconds: 4),
            ),
          );
        } else if (elfItems.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('成功一次寫入 ${elfItems.length} 筆紀錄至資料庫！')),
          );

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ElfFeedingPage(
                imagePath: firstImagePath ?? "",
                items: elfItems,
                recordDate: validItems.isNotEmpty ? validItems[0].selectedDate : DateTime.now(),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(FriendlyErrorMessage.dietRecord)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('手動紀錄', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        centerTitle: true,
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RawScrollbar(
        controller: _scrollController,
        thumbColor: Colors.grey.shade600,
        thumbVisibility: true,
        thickness: 6.0,
        radius: const Radius.circular(3),
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.only(left: 20, top: 20, right: 14, bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 手動紀錄標題下方提示 (字體放大)
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 14),
                  child: Text(
                    '提示：每欄請記錄單一餐點',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ),
              ),

              // 卡片 Grid 清單
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 16),
                itemBuilder: (context, index) => _buildRecordCard(_items[index], index),
              ),

              const SizedBox(height: 25),

              // 新增一項內容按鈕 (增加一張紀錄 Grid 卡片)
              Center(
                child: TextButton.icon(
                  onPressed: _addNewItem,
                  icon: const Icon(Icons.add_circle_outline, color: AppColors.secondary),
                  label: const Text('新增一項內容', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),

              const SizedBox(height: 30),

              // 完成紀錄並餵食按鈕
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    elevation: 2,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Text(
                          '完成紀錄並餵食',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordCard(_ManualRecordItem item, int index) {
    final bool isExpanded = item.isExpanded;
    final String dishName = item.nameController.text.trim();
    final String portionStr = item.portionController.text.trim().isEmpty ? '1' : item.portionController.text.trim();
    final String summaryText = dishName.isEmpty ? '' : '$dishName (${item.mealType} • $portionStr份)';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // === 卡片 Header (點擊可展開/收合) ===
          InkWell(
            onTap: () {
              setState(() {
                item.isExpanded = !item.isExpanded;
              });
            },
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // 展開 / 收合 箭頭 (放最左側)
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: AppColors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 8),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '紀錄 #${index + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 收合時顯示摘要資訊
                  if (!isExpanded) ...[
                    Expanded(
                      child: Text(
                        summaryText.isEmpty ? '點擊展開編輯' : summaryText,
                        style: TextStyle(
                          fontSize: 13,
                          color: summaryText.isEmpty ? Colors.grey : AppColors.textPrimary,
                          fontWeight: summaryText.isEmpty ? FontWeight.normal : FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else
                    const Spacer(),

                  // 刪除按鈕 (最右側)
                  if (_items.length > 1)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 22),
                      onPressed: () => _removeItem(index),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ),
          ),

          // === 卡片內容區塊 (展開時顯示) ===
          if (isExpanded) ...[
            const Divider(height: 1, color: AppColors.surface),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 照片選擇區
                  _buildPhotoSection(item, index),

                  const SizedBox(height: 12),

                  // 2. 日期與時段選擇
                  _buildSelectionSection(item, index),

                  const SizedBox(height: 12),

                  // 3. 飲食內容與份數
                  _buildDishAndPortionField(item, index),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhotoSection(_ManualRecordItem item, int index) {
    return GestureDetector(
      onTap: () => _pickImageFor(index),
      child: Container(
        width: double.infinity,
        height: 130,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: item.selectedImage == null || item.imageBytes == null
            ? Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(Icons.camera_alt, color: AppColors.background, size: 26),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      '添加照片 (選填)',
                      style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              )
            : Stack(
                children: [
                  Image.memory(
                    item.imageBytes!,
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        item.selectedImage = null;
                        item.imageBytes = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSelectionSection(_ManualRecordItem item, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSelectRow(
              "${item.selectedDate.year}/${item.selectedDate.month}/${item.selectedDate.day}",
              Icons.calendar_today,
              () => _selectDateFor(index),
            ),
          ),
          Container(
            width: 1,
            height: 24,
            color: AppColors.border.withOpacity(0.5),
          ),
          Expanded(
            child: _buildSelectRow(
              item.mealType,
              Icons.access_time,
              () => _showMealPickerFor(index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectRow(String value, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: AppColors.textPrimary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDishAndPortionField(_ManualRecordItem item, int index) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.restaurant_menu, color: Colors.grey, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: item.nameController,
              decoration: const InputDecoration(
                hintText: '例：火腿蛋吐司',
                hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                border: InputBorder.none,
              ),
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
          ),
          Container(
            width: 1,
            height: 24,
            color: AppColors.border.withOpacity(0.5),
          ),
          const SizedBox(width: 8),
          const Text('份數: ', style: TextStyle(fontSize: 13, color: Colors.black54)),
          SizedBox(
            width: 35,
            child: TextField(
              controller: item.portionController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: '1',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
