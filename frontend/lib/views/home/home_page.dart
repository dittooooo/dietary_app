import 'package:flutter/material.dart';
import '../auth/profile_page.dart';
import '../records/dietary_record_page.dart';
import 'home_view.dart';
import '../../color/app_colors.dart';

class HomePage extends StatefulWidget {
  final int initialIndex;
  final bool showChat;
  const HomePage({super.key, this.initialIndex = 0, this.showChat = false});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late int _selectedIndex;
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _pages = [
      HomeView(initialOpenChat: widget.showChat),
      const DietaryRecordPage(),
      const ProfilePage(),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 3.9,
              offset: const Offset(0, -1.17),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textPrimary.withOpacity(0.4),
          backgroundColor: AppColors.background,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home),
              label: '首頁',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.edit_note),
              label: '飲食紀錄',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_circle),
              label: '個人首頁',
            ),
          ],
        ),
      ),
    );
  }
}


