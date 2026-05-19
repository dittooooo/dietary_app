import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../home/home_page.dart';
import '../../color/app_colors.dart';

class ElfFeedingPage extends StatefulWidget {
  final String imagePath;
  final List<Map<String, dynamic>> items;

  const ElfFeedingPage({
    super.key,
    required this.imagePath,
    required this.items,
  });

  @override
  State<ElfFeedingPage> createState() => _ElfFeedingPageState();
}

class _ElfFeedingPageState extends State<ElfFeedingPage> with TickerProviderStateMixin {
  late AnimationController _elfController;
  late Animation<double> _elfScale;
  late Animation<Offset> _elfMove;
  bool _isEaten = false;

  @override
  void initState() {
    super.initState();
    _elfController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    );

    _elfMove = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: const Offset(0, 0),
    ).animate(CurvedAnimation(parent: _elfController, curve: const Interval(0.0, 0.3, curve: Curves.easeOutBack)));

    _elfScale = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _elfController, curve: const Interval(0.3, 0.5, curve: Curves.elasticOut)),
    );

    _elfController.forward().then((_) {
      if (mounted) _goToDiary();
    });

    // 延遲一段時間讓食物消失
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _isEaten = true);
    });
  }

  void _goToDiary() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const HomePage(initialIndex: 1)),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _elfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          // 背景與標題
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "小精靈用餐中...",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 30),
                // 剛才拍的照片
                AnimatedOpacity(
                  duration: const Duration(seconds: 1),
                  opacity: _isEaten ? 0 : 1,
                  child: AnimatedScale(
                    duration: const Duration(seconds: 1),
                    scale: _isEaten ? 0.2 : 1,
                    child: Container(
                      width: 250, height: 250,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 3.9)],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: widget.imagePath.isNotEmpty
                          ? (kIsWeb 
                              ? Image.network(widget.imagePath, fit: BoxFit.cover)
                              : Image.file(File(widget.imagePath), fit: BoxFit.cover))
                          : Container(
                              color: Colors.grey[200],
                              child: const Icon(Icons.restaurant, size: 80, color: Colors.grey),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 小精靈動畫
          Align(
            alignment: Alignment.bottomCenter,
            child: SlideTransition(
              position: _elfMove,
              child: ScaleTransition(
                scale: _elfScale,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 150),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_isEaten)
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(15)),
                          child: const Text("啊姆！看起來很好吃！", style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        ),
                      const SizedBox(height: 10),
                      const Icon(Icons.pets, size: 120, color: Colors.black),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 跳過按鈕 (改到下方中央)
          Positioned(
            bottom: 50, left: 0, right: 0,
            child: Center(
              child: ElevatedButton(
                onPressed: _goToDiary,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.background.withOpacity(0.8),
                  foregroundColor: AppColors.textPrimary,
                  elevation: 0.975,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                ),
                child: const Text("跳過動畫 >>", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
