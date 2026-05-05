import 'package:flutter/material.dart';
import '../../color/app_colors.dart';

class UserDetailPage extends StatelessWidget {
  final Map<String, String> userData;
  const UserDetailPage({super.key, required this.userData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(userData['name']!, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildDetailField('使用者 ID', userData['id']!),
            _buildDetailField('姓名 / 別名', userData['name']!),
            _buildDetailField('電子郵件 (帳號)', userData['email']!),
            _buildDetailField('性別', userData['gender']!),
            _buildDetailField('身高 (cm)', userData['height']!),
            _buildDetailField('體重 (kg)', userData['weight']!),
            _buildDetailField('個人目標', '養成健康飲食習慣'),
            _buildDetailField('特殊疾病', '無'),
            const SizedBox(height: 30),
            const Text('向右滑動可返回清單', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: TextFormField(
        initialValue: value,
        readOnly: true,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          filled: true,
          fillColor: AppColors.background,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
        ),
      ),
    );
  }
}
