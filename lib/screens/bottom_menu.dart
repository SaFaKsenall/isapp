import 'package:flutter/material.dart';
import 'package:myapp/model/user_model.dart';
import 'package:myapp/screens/anasayfa.dart';
import 'package:myapp/screens/ispaylasmaprfili/job_profile_page.dart';
import 'package:myapp/screens/qr_payment/qr_gonderme.dart';
import 'package:myapp/screens/search_page.dart';

class AnimatedBottomTabBar extends StatefulWidget {
  final UserModel user; // Add this line to receive the user

  const AnimatedBottomTabBar({super.key, required this.user});

  @override
  _AnimatedBottomTabBarState createState() => _AnimatedBottomTabBarState();
}

class _AnimatedBottomTabBarState extends State<AnimatedBottomTabBar> {
  int _selectedIndex = 0;

  // Modify _pages to use the passed user
  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const InstagramStyleJobListing(),
      const JobSearchPage(),
      JobProfilePage(user: widget.user), // Pass the user here
      const ReferralQRCodePage( ),
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
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.shifting,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home),
            label: 'Ana Sayfa',
            backgroundColor: Colors.blue[50],
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.search),
            label: 'Arama',
            backgroundColor: Colors.green[50],
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: 'Profil',
            backgroundColor: Colors.purple[50],
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings),
            label: 'Ayarlar',
            backgroundColor: Colors.orange[50],
          ),
        ],
      ),
    );
  }
}

