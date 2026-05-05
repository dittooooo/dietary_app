import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/api_config.dart';
import '../../color/app_colors.dart';
import './login_page.dart'; 

class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic> initialData;
  const EditProfilePage({super.key, required this.initialData});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameController;
  late TextEditingController _ageController;
  late TextEditingController _heightController;
  late TextEditingController _weightController;
  
  String _gender = '';
  Set<String> _diseases = {};
  Set<String> _goals = {};

  final List<String> _genderOptions = ['男', '女'];
  final List<String> _diseaseOptions = ['糖尿病', '高血壓', '無疾病'];
  final List<String> _goalOptions = ['減脂', '增肌', '養生'];

  @override
  void initState() {
    super.initState();
    final data = widget.initialData;
    _nameController = TextEditingController(text: data['nickname'] ?? '');
    _ageController = TextEditingController(text: data['age']?.toString() ?? '');
    _heightController = TextEditingController(text: data['height']?.toString() ?? '');
    _weightController = TextEditingController(text: data['weight']?.toString() ?? '');
    _gender = data['gender'] ?? '男';
    
    // 解析疾病與目標 (相容多種後端命名與格式)
    var healthData = data['healthConditions'] ?? data['health_conditions'];
    if (healthData != null) {
      if (healthData is String && healthData.isNotEmpty) {
        _diseases = healthData.split(RegExp(r'[,\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
      } else if (healthData is List) {
        _diseases = Set<String>.from(healthData);
      }
    }
    
    var goalData = data['dietGoal'] ?? data['diet_goal'];
    if (goalData != null) {
      if (goalData is String && goalData.isNotEmpty) {
        _goals = goalData.split(RegExp(r'[,\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
      } else if (goalData is List) {
        _goals = Set<String>.from(goalData);
      }
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      final body = jsonEncode({
        'nickname': _nameController.text.trim(),
        'gender': _gender,
        'age': int.tryParse(_ageController.text) ?? 0,
        'height': double.tryParse(_heightController.text) ?? 0.0,
        'weight': double.tryParse(_weightController.text) ?? 0.0,
        'healthConditions': _diseases.toList(),
        'dietGoal': _goals.join(', '),
        'petType': widget.initialData['petType'] ?? '預設小精靈',
      });

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/user/onboarding'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('個人資料修改成功！'))
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失敗: $e'))
        );
      }
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確定要註銷帳號嗎？'),
        content: const Text('這將會永久刪除您的所有資料，且無法復原。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消', style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('確認註銷', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/user/account'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        // ... (success logic)
      } else if (response.statusCode == 404 || response.statusCode == 405) {
        // 後端未實作時的補償說明 (前端輔助)
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('目前後端暫不支援註銷功能，請聯繫管理員。'))
          );
        }
      } else {
        throw Exception('註銷失敗: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('目前後端尚未開放註銷功能。'))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('編輯資料', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        centerTitle: true,
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildSectionBox([
                _buildRowItem('暱稱', _nameController),
                _buildRowItem('帳號', TextEditingController(text: widget.initialData['email'] ?? ''), enabled: false),
              ]),
              const SizedBox(height: 15),
              _buildSectionBox([
                _buildGenderSelector(),
                _buildRowItem('年齡', _ageController, isNumber: true),
                _buildRowItem('身高', _heightController, isNumber: true, suffix: 'cm'),
                _buildRowItem('體重', _weightController, isNumber: true, suffix: 'kg'),
                _buildTagSelector('疾病', _diseaseOptions, _diseases),
                _buildTagSelector('目標', _goalOptions, _goals),
              ]),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildCustomButton('刪除帳戶', AppColors.secondary, isDashed: true, onTap: _deleteAccount),
                  _buildCustomButton('完成修改', AppColors.primary, onTap: _updateProfile),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionBox(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildRowItem(String label, TextEditingController controller, {bool enabled = true, bool isNumber = false, String suffix = ''}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              keyboardType: isNumber ? TextInputType.number : TextInputType.text,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: '請輸入',
                suffixText: suffix,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 60, child: Text('性別', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _genderOptions.map((g) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: ChoiceChip(
                  label: Text(g),
                  selected: _gender == g,
                  onSelected: (val) => setState(() => _gender = g),
                  selectedColor: AppColors.secondary.withOpacity(0.2),
                  labelStyle: TextStyle(color: _gender == g ? AppColors.textPrimary : AppColors.textSecondary),
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagSelector(String label, List<String> options, Set<String> selection) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          Expanded(
            child: Wrap(
              spacing: 8,
              alignment: WrapAlignment.center,
              children: options.map((opt) {
                final isSelected = selection.contains(opt);
                return FilterChip(
                  label: Text(opt, style: TextStyle(color: isSelected ? AppColors.textPrimary : AppColors.textSecondary)),
                  selected: isSelected,
                  onSelected: (val) {
                    // ... (logic remains same)
                  },
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
                  showCheckmark: false,
                  backgroundColor: Colors.transparent,
                  selectedColor: AppColors.secondary.withOpacity(0.1),
                );
              }).toList(),
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildCustomButton(String text, Color color, {bool isDashed = false, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }
}
