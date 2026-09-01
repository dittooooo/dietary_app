import 'package:flutter/material.dart';

import '../../color/app_colors.dart';
import '../../config/api_config.dart';
import '../../services/admin_service.dart';

/// 管理者檢視與回覆全站使用者問題反饋之主視圖頁面。
class AdminProblemFeedbackPage extends StatefulWidget {
  const AdminProblemFeedbackPage({super.key});

  @override
  State<AdminProblemFeedbackPage> createState() => _AdminProblemFeedbackPageState();
}

/// 管理者問題反饋頁面之狀態管理與 API 互動邏輯。
class _AdminProblemFeedbackPageState extends State<AdminProblemFeedbackPage> {
  bool _isLoading = true;
  List<dynamic> _feedbackList = [];

  /// 初始化 Widget 狀態與管理控制台資料。
  @override
  /// 執行 initState 之專屬功能操作。
  void initState() {
    super.initState();
    _loadFeedback();
  }

  /// 向後端 AdminService 發送請求，載入全站使用者提交之問題反饋清單。
  Future<void> _loadFeedback() async {
    setState(() => _isLoading = true);
    final list = await AdminService().listProblemFeedback();
    if (!mounted) return;
    setState(() {
      _feedbackList = list;
      _isLoading = false;
    });
  }

  /// 執行 formatDate 之專屬功能操作。
  String _formatDate(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.length >= 16) {
      return text.substring(0, 16).replaceFirst('T', ' ');
    }
    return text;
  }

  /// 執行 openReplyDialog 之專屬功能操作。
  Future<void> _openReplyDialog(Map feedback) async {
    final id = int.tryParse('${feedback['id'] ?? ''}');
    if (id == null) return;

    final reply = await showDialog<String>(
      context: context,
      builder: (context) => _ReplyDialog(
        initialReply: feedback['adminReply']?.toString() ?? '',
      ),
    );

    if (reply == null) {
      return;
    }

    final result = await AdminService().replyProblemFeedback(id, reply);
    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已回覆使用者')),
      );
      await _loadFeedback();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message']?.toString() ?? '回覆失敗')),
      );
    }
  }

  /// 判斷圖片路徑格式，將相對路徑轉譯補全為可供網頁或 App 載入之完整圖片 URL。
  String _resolveImageUrl(String photoUrl) {
    if (photoUrl.startsWith('http://') || photoUrl.startsWith('https://')) {
      return photoUrl;
    }
    return '${ApiConfig.serverBaseUrl}$photoUrl';
  }

  /// 彈出大圖對話框，放大檢視使用者附帶之問題反饋圖片。
  Future<void> _openPhotoDialog(String photoUrl) async {
    final imageUrl = _resolveImageUrl(photoUrl);
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppColors.background,
        insetPadding: const EdgeInsets.all(18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '使用者上傳圖片',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.60,
                    maxWidth: MediaQuery.of(context).size.width * 0.85,
                  ),
                  child: InteractiveViewer(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('圖片載入失敗'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 繪製並傳回當前 Widget 之 UI 畫面架構。
  @override
  /// 建立  區塊之視覺 UI 視圖元件。
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(
          '問題回饋管理',
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
      body: RefreshIndicator(
        onRefresh: _loadFeedback,
        color: AppColors.secondary,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.secondary),
              )
            : _feedbackList.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text('目前沒有使用者送出的問題。')),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: _feedbackList.length,
                    itemBuilder: (context, index) {
                      final raw = _feedbackList[index];
                      final feedback = raw is Map ? raw : <String, dynamic>{};
                      return _buildFeedbackCard(feedback);
                    },
                  ),
      ),
    );
  }

  /// 建立 FeedbackCard 區塊之視覺 UI 視圖元件。
  Widget _buildFeedbackCard(Map feedback) {
    final adminReply = feedback['adminReply']?.toString() ?? '';
    final photoUrl = feedback['photoUrl']?.toString() ?? '';
    final hasReply = adminReply.trim().isNotEmpty;
    final hasPhoto = photoUrl.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasReply ? AppColors.sage : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasReply ? Icons.check_circle_outline : Icons.pending_actions,
                color: hasReply ? AppColors.success : AppColors.secondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  feedback['userName']?.toString() ?? '使用者',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                hasReply ? '已回覆' : '待回覆',
                style: TextStyle(
                  color: hasReply ? AppColors.success : AppColors.secondary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '送出時間 ${_formatDate(feedback['createdAt'])}',
            style: TextStyle(
              color: AppColors.textPrimary.withValues(alpha: 0.55),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          const Text('使用者問題', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(feedback['content']?.toString() ?? ''),
          if (hasPhoto) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _openPhotoDialog(photoUrl),
              icon: const Icon(Icons.image_search_outlined),
              label: const Text('查看圖片'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.secondary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Text('目前回覆', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(hasReply ? adminReply : '尚未回覆'),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openReplyDialog(feedback),
              icon: Icon(hasReply ? Icons.edit_note : Icons.reply),
              label: Text(hasReply ? '修改回覆' : '回覆使用者'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 彈出式回覆對話框元件，提供文字輸入框供管理者撰寫回覆內容。
class _ReplyDialog extends StatefulWidget {
  final String initialReply;

  const _ReplyDialog({required this.initialReply});

  @override
  State<_ReplyDialog> createState() => _ReplyDialogState();
}

/// 回覆對話框之輸入框控制器與狀態管理。
class _ReplyDialogState extends State<_ReplyDialog> {
  late final TextEditingController _controller;

  /// 初始化 Widget 狀態與管理控制台資料。
  @override
  /// 執行 initState 之專屬功能操作。
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialReply);
  }

  /// 銷毀狀態並釋放控制器資源。
  @override
  /// 執行 dispose 之專屬功能操作。
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 執行 submit 之專屬功能操作。
  void _submit() {
    final reply = _controller.text.trim();
    if (reply.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先輸入回覆內容')),
      );
      return;
    }
    Navigator.pop(context, reply);
  }

  /// 繪製並傳回當前 Widget 之 UI 畫面架構。
  @override
  /// 建立  區塊之視覺 UI 視圖元件。
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: const Text('回覆使用者'),
      content: TextField(
        controller: _controller,
        maxLength: 2000,
        minLines: 5,
        maxLines: 8,
        decoration: const InputDecoration(
          hintText: '輸入要給使用者看的回覆',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.background,
          ),
          onPressed: _submit,
          child: const Text('送出回覆'),
        ),
      ],
    );
  }
}
