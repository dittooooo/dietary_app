import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../color/app_colors.dart';
import '../../services/auth_service.dart';
import '../../utils/friendly_error_message.dart';

/// 使用者提交問題回饋與查看歷史回饋紀錄主頁面 Widget。
class ProblemFeedbackPage extends StatefulWidget {
  const ProblemFeedbackPage({super.key});

  @override
  State<ProblemFeedbackPage> createState() => _ProblemFeedbackPageState();
}

/// 內部使用的 _ProblemFeedbackPageState 元件與狀態處理類別。
class _ProblemFeedbackPageState extends State<ProblemFeedbackPage> {
  final TextEditingController _contentController = TextEditingController();
  bool _isSubmitting = false;
  bool _isLoadingFeedback = true;
  List<dynamic> _feedbackList = [];
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;

  /// 初始化 Widget 狀態與訂閱生命週期。
  @override
  void initState() {
    super.initState();
    _loadFeedback();
  }

  /// 銷毀 Widget 狀態與釋放控制器資源。
  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  /// 載入歷史問題回饋清單。
  Future<void> _loadFeedback() async {
    setState(() => _isLoadingFeedback = true);
    final list = await AuthService().listMyProblemFeedback();
    if (!mounted) return;
    setState(() {
      _feedbackList = list;
      _isLoadingFeedback = false;
    });
  }

  /// 提交新的問題回饋內容與附件圖片至後端。
  Future<void> _submit() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先輸入問題內容')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final result = await AuthService().submitProblemFeedback(content);

    if (!mounted) return;

    if (result['success'] == true) {
      var uploadedPhoto = true;
      final feedbackData = result['data'];
      final feedbackId = feedbackData is Map
          ? int.tryParse('${feedbackData['id'] ?? ''}')
          : null;
      if (_selectedImageBytes != null && _selectedImage != null) {
        if (feedbackId == null) {
          uploadedPhoto = false;
        } else {
          final photoResult = await AuthService().uploadProblemFeedbackPhoto(
            feedbackId,
            _selectedImageBytes!,
            _selectedImage!.name,
          );
          uploadedPhoto = photoResult['success'] == true;
        }
      }

      _contentController.clear();
      _clearSelectedImage();
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uploadedPhoto
                ? '問題回饋已送出，管理員回覆後會顯示在下方'
                : '問題已送出，但照片上傳失敗，請稍後再試',
          ),
        ),
      );
      await _loadFeedback();
    } else {
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(FriendlyErrorMessage.generic)),
      );
    }
  }

  /// 啟動圖片選擇器以選取回饋照片附件。
  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (image == null) return;

      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedImage = image;
        _selectedImageBytes = bytes;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(FriendlyErrorMessage.upload)),
      );
    }
  }

  void _clearSelectedImage() {
    setState(() {
      _selectedImage = null;
      _selectedImageBytes = null;
    });
  }

  String _formatDate(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.length >= 16) {
      return text.substring(0, 16).replaceFirst('T', ' ');
    }
    return text;
  }

  /// 繪製並傳回當前 Widget 之 UI 畫面架構。
  @override
  Widget build(BuildContext context) {
    final contentLength = _contentController.text.length;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          '問題回饋',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadFeedback,
          color: AppColors.secondary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSubmitCard(contentLength),
                const SizedBox(height: 24),
                _buildFeedbackHistory(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitCard(int contentLength) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '請描述你遇到的問題',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contentController,
            maxLength: 2000,
            maxLines: 8,
            minLines: 6,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '例如：在哪個頁面遇到問題、做了什麼操作、畫面出現什麼狀況...',
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.72),
              counterText: '$contentLength / 2000',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: AppColors.secondary,
                  width: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isSubmitting ? null : _pickImage,
            icon: const Icon(Icons.image_outlined),
            label: Text(_selectedImage == null ? '上傳問題截圖' : '更換問題截圖'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.secondary),
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (_selectedImage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.photo_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedImage!.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: _isSubmitting ? null : _clearSelectedImage,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.45),
              foregroundColor: AppColors.background,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: AppColors.background,
                    ),
                  )
                : const Text(
                    '送出問題回饋',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '我的回饋紀錄',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (_isLoadingFeedback)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: CircularProgressIndicator(color: AppColors.secondary),
            ),
          )
        else if (_feedbackList.isEmpty)
          _buildEmptyCard()
        else
          ..._feedbackList.map(_buildFeedbackCard),
      ],
    );
  }

  Widget _buildEmptyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        '目前還沒有送出的問題。',
        style: TextStyle(color: AppColors.textPrimary),
      ),
    );
  }

  Widget _buildFeedbackCard(dynamic item) {
    final feedback = item is Map ? item : <String, dynamic>{};
    final content = feedback['content']?.toString() ?? '';
    final photoUrl = feedback['photoUrl']?.toString() ?? '';
    final adminReply = feedback['adminReply']?.toString() ?? '';
    final hasReply = adminReply.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasReply ? AppColors.sage : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasReply ? Icons.mark_chat_read_outlined : Icons.schedule,
                size: 18,
                color: hasReply ? AppColors.success : AppColors.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasReply ? '管理員已回覆' : '等待管理員回覆',
                  style: TextStyle(
                    color: hasReply ? AppColors.success : AppColors.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                _formatDate(feedback['createdAt']),
                style: TextStyle(
                  color: AppColors.textPrimary.withValues(alpha: 0.55),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '你的問題',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(content),
          if (photoUrl.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: const [
                Icon(Icons.image_outlined, size: 16),
                SizedBox(width: 6),
                Text('已附上問題截圖'),
              ],
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            '管理員回覆',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(hasReply ? adminReply : '管理員尚未回覆，請稍後再查看。'),
          if (hasReply && feedback['repliedAt'] != null) ...[
            const SizedBox(height: 8),
            Text(
              '回覆時間 ${_formatDate(feedback['repliedAt'])}',
              style: TextStyle(
                color: AppColors.textPrimary.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
