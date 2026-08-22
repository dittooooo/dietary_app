import 'package:flutter/material.dart';

import '../../color/app_colors.dart';
import '../../services/auth_service.dart';
import '../../utils/friendly_error_message.dart';

class ProblemFeedbackPage extends StatefulWidget {
  const ProblemFeedbackPage({super.key});

  @override
  State<ProblemFeedbackPage> createState() => _ProblemFeedbackPageState();
}

class _ProblemFeedbackPageState extends State<ProblemFeedbackPage> {
  final TextEditingController _contentController = TextEditingController();
  bool _isSubmitting = false;
  bool _isLoadingFeedback = true;
  List<dynamic> _feedbackList = [];

  @override
  void initState() {
    super.initState();
    _loadFeedback();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadFeedback() async {
    setState(() => _isLoadingFeedback = true);
    final list = await AuthService().listMyProblemFeedback();
    if (!mounted) return;
    setState(() {
      _feedbackList = list;
      _isLoadingFeedback = false;
    });
  }

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
    setState(() => _isSubmitting = false);

    if (result['success'] == true) {
      _contentController.clear();
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('問題回饋已送出，管理員回覆後會顯示在下方')),
      );
      await _loadFeedback();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(FriendlyErrorMessage.generic)),
      );
    }
  }

  String _formatDate(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.length >= 16) {
      return text.substring(0, 16).replaceFirst('T', ' ');
    }
    return text;
  }

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
            color: Colors.black.withOpacity(0.08),
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
              fillColor: Colors.white.withOpacity(0.72),
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
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.primary.withOpacity(0.45),
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
                  color: AppColors.textPrimary.withOpacity(0.55),
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
                color: AppColors.textPrimary.withOpacity(0.55),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
