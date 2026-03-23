import 'package:flutter/material.dart';
import 'initial_info_page.dart';

class SuccessTransitionPage extends StatefulWidget {
  final String title;
  final bool shouldNavigate;
  const SuccessTransitionPage({
    super.key, 
    this.title = '登入成功！',
    this.shouldNavigate = true,
  });

  @override
  State<SuccessTransitionPage> createState() => _SuccessTransitionPageState();
}

class _SuccessTransitionPageState extends State<SuccessTransitionPage> {
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _animateProgress();
  }

  void _animateProgress() async {
    for (int i = 0; i <= 100; i++) {
      await Future.delayed(const Duration(milliseconds: 20));
      if (mounted) {
        setState(() => _progress = i / 100.0);
      }
    }
    if (mounted && widget.shouldNavigate) {
      // 進度條跑完後跳轉至個人資料填寫頁面
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const InitialInfoPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.face, size: 80), // 預留位
              const SizedBox(height: 20),
              Text(widget.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: _progress,
                backgroundColor: Colors.grey[200],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                minHeight: 10,
              ),
              const SizedBox(height: 40),
              const Icon(Icons.image, size: 100, color: Colors.grey), // 動畫預留位
              const SizedBox(height: 20),
              const Text('希望您能享受 App', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
