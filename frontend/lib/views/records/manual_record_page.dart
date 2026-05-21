import 'package:flutter/material.dart';
import '../../color/app_colors.dart';
import 'elf_feeding_page.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'simple_camera_page.dart';

class ManualRecordPage extends StatefulWidget {
  final DateTime? initialDate;
  const ManualRecordPage({super.key, this.initialDate});

  @override
  State<ManualRecordPage> createState() => _ManualRecordPageState();
}

class _ManualRecordPageState extends State<ManualRecordPage> {
  late DateTime _selectedDate;
  late String _mealType;
  final List<TextEditingController> _itemControllers = [TextEditingController()];
  XFile? _selectedImage;
  Uint8List? _imageBytes;
  final ImagePicker _picker = ImagePicker();
  
  final List<String> _mealOptions = ['早餐', '午餐', '晚餐', '其他'];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _mealType = _getAutoMealType();
  }

  String _getAutoMealType() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 11) return '早餐';
    if (hour >= 11 && hour < 14) return '午餐';
    if (hour >= 17 && hour < 21) return '晚餐';
    return '其他';
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primary, onPrimary: Colors.white, onSurface: AppColors.textPrimary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  void _addItem() {
    setState(() => _itemControllers.add(TextEditingController()));
  }

  void _removeItem(int index) {
    if (_itemControllers.length > 1) {
      setState(() => _itemControllers.removeAt(index));
    }
  }

  Future<void> _pickImage() async {
    // 彈出選單讓使用者選擇「拍照」或「從相簿選取」
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.textPrimary),
              title: const Text('拍照', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.textPrimary),
              title: const Text('從相簿選取', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source != null) {
      try {
        XFile? image;
        if (source == ImageSource.camera) {
          // 使用自訂的 SimpleCameraPage 進行拍照，解決 Web 和行動端相機拉起與預覽問題
          image = await Navigator.push<XFile>(
            context,
            MaterialPageRoute(builder: (context) => const SimpleCameraPage()),
          );
        } else {
          image = await _picker.pickImage(source: ImageSource.gallery);
        }

        if (image != null) {
          final bytes = await image.readAsBytes();
          setState(() {
            _selectedImage = image;
            _imageBytes = bytes;
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('選取圖片失敗: $e'))
          );
        }
      }
    }
  }

  void _submit() {
    List<Map<String, String>> items = [];
    for (var controller in _itemControllers) {
      if (controller.text.trim().isNotEmpty) {
        items.add({
          'name': controller.text.trim(),
          'portion': '1份',
          'calories': '-- kcal', // 手動輸入預設不帶熱量
        });
      }
    }

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請至少輸入一項飲食內容')));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ElfFeedingPage(
          imagePath: _selectedImage?.path ?? "", 
          items: items,
        ),
      ),
    );
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
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary), onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 0. 照片選擇區
            _buildPhotoSection(),
            const SizedBox(height: 20),
            
            // 1. 日期與時段選擇
            _buildSelectionSection(),
            const SizedBox(height: 25),
            
            // 2. 飲食內容標題
            const Row(
              children: [
                Icon(Icons.restaurant_menu, color: AppColors.secondary, size: 20),
                SizedBox(width: 8),
                Text('飲食內容', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              ],
            ),
            const SizedBox(height: 15),

            // 3. 項目列表
            ..._itemControllers.asMap().entries.map((entry) => _buildItemField(entry.key, entry.value)).toList(),

            const SizedBox(height: 15),
            
            // 4. 新增項目按鈕
            Center(
              child: TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add_circle_outline, color: AppColors.secondary),
                label: const Text('新增一項內容', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold)),
              ),
            ),
            
            const SizedBox(height: 40),
            
            // 5. 完成按鈕
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 2,
                ),
                child: const Text('完成紀錄並餵食', style: TextStyle(color: AppColors.background, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSelectRow("${_selectedDate.year}/${_selectedDate.month}/${_selectedDate.day}", Icons.calendar_today, _selectDate),
          ),
          Container(
            width: 1,
            height: 30,
            color: AppColors.border.withOpacity(0.5),
          ),
          Expanded(
            child: _buildSelectRow(_mealType, Icons.access_time, _showMealPicker),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectRow(String value, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center, // 水平置中
          children: [
            Icon(icon, size: 18, color: AppColors.textPrimary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                value, 
                style: const TextStyle(
                  fontWeight: FontWeight.bold, 
                  fontSize: 14, // 稍微縮小字體以適應並排
                  color: AppColors.textPrimary
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

  Widget _buildItemField(int index, TextEditingController controller) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Padding(padding: EdgeInsets.symmetric(horizontal: 15), child: Icon(Icons.edit_note, color: Colors.grey)),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: '例：火腿蛋吐司',
                hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5)),
                border: InputBorder.none,
              ),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          if (_itemControllers.length > 1)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: AppColors.danger, size: 20),
              onPressed: () => _removeItem(index),
            ),
        ],
      ),
    );
  }

  void _showMealPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _mealOptions.map((m) => ListTile(
            title: Text(m, textAlign: TextAlign.center, style: TextStyle(fontWeight: _mealType == m ? FontWeight.bold : FontWeight.normal)),
            onTap: () { setState(() => _mealType = m); Navigator.pop(context); },
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildPhotoSection() {
    return GestureDetector(
      onTap: _pickImage,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.05), blurRadius: 10)],
        ),
        clipBehavior: Clip.antiAlias,
        child: _selectedImage == null || _imageBytes == null
            ? SizedBox(
                height: 150,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80, height: 70,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 5, offset: const Offset(0, 2))],
                        ),
                        child: const Icon(Icons.camera_alt, color: AppColors.background, size: 30),
                      ),
                      const SizedBox(height: 10),
                      const Text('添加照片 (選填)', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              )
            : Stack(
                children: [
                  Image.memory(
                    _imageBytes!,
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                  Positioned(
                    right: 10, top: 10,
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _selectedImage = null;
                        _imageBytes = null;
                      }),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                        child: const Icon(Icons.close, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
