import 'package:flutter/material.dart';
import 'admin_add_item_page.dart';
import '../../color/app_colors.dart';

class GenericAdminListPage extends StatefulWidget {
  final String title;
  final String searchHint;

  const GenericAdminListPage({
    super.key,
    required this.title,
    this.searchHint = '輸入關鍵字查詢...',
  });

  @override
  State<GenericAdminListPage> createState() => _GenericAdminListPageState();
}

class _GenericAdminListPageState extends State<GenericAdminListPage> {
  final TextEditingController _searchController = TextEditingController();
  bool _isDeleteMode = false;
  bool _isLoading = false;

  // 模擬資料清單
  List<Map<String, String>> _allData = [];
  List<Map<String, String>> _foundData = [];

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    // 預留後端 API 對接
    await Future.delayed(const Duration(milliseconds: 600));
    setState(() {
      _allData = []; // 預設為空，等待後端資料
      _foundData = _allData;
      _isLoading = false;
    });
  }

  void _runFilter(String enteredKeyword) {
    if (enteredKeyword.isEmpty) {
      setState(() => _foundData = _allData);
      return;
    }
    setState(() {
      _foundData = _allData.where((item) =>
          item.values.any((val) => val.toLowerCase().contains(enteredKeyword.toLowerCase()))
      ).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(_isDeleteMode ? '點擊以刪除' : widget.title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: _isDeleteMode ? AppColors.danger.withOpacity(0.1) : AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20.0),
            child: IconButton(
              icon: Icon(_isDeleteMode ? Icons.close : Icons.delete, size: 40),
              onPressed: () => setState(() => _isDeleteMode = !_isDeleteMode),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(15.0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => _runFilter(value),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.background,
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search, color: AppColors.secondary),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: const BorderSide(color: AppColors.primary)),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _foundData.isEmpty
                    ? const Center(child: Text('查無資料', style: TextStyle(fontSize: 18, color: AppColors.textSecondary)))
                    : ListView.builder(
                        itemCount: _foundData.length,
                        itemBuilder: (context, index) {
                          final item = _foundData[index];
                          return Card(
                            color: AppColors.background,
                            margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              title: Text(item['name'] ?? '未命名', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                              subtitle: Text(item['desc'] ?? '', style: const TextStyle(color: AppColors.textSecondary)),
                              trailing: const Icon(Icons.edit, size: 20, color: AppColors.secondary),
                              onTap: () {
                                if (_isDeleteMode) {
                                  _showDeleteDialog(item);
                                } else {
                                  // 進入編輯畫面
                                }
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AdminAddItemPage(title: widget.title),
            ),
          ).then((value) {
            if (value == true) _fetchData(); // 若新增成功則刷新
          });
        },
        child: const Icon(Icons.add, color: AppColors.background),
      ),
    );
  }

  void _showDeleteDialog(Map<String, String> item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: const Text('確定刪除？', style: TextStyle(color: AppColors.textPrimary)),
        content: Text('這將永久移除這項資料。', style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: AppColors.textSecondary))),
          TextButton(
            onPressed: () {
              setState(() {
                _allData.removeWhere((i) => i == item);
                _runFilter(_searchController.text);
                _isDeleteMode = false;
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已刪除')));
            },
            child: const Text('確定', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
