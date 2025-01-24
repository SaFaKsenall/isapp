import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:myapp/model/user_model.dart';
import 'package:myapp/notifications/notivications.dart';
import 'package:myapp/notifications/yardim_destek.dart';

class MyDrawer extends StatelessWidget {
  final UserModel user;

  const MyDrawer({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade800,
              Colors.blue.shade600,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Profil Bölümü
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 45,
                        backgroundColor: Colors.white,
                        backgroundImage: user.profileImageUrl != null
                            ? NetworkImage(user.profileImageUrl!)
                            : null,
                        child: user.profileImageUrl == null
                            ? Icon(Icons.person,
                                size: 45, color: Colors.blue.shade800)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      user.username,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (user.email != null)
                      Text(
                        user.email!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(color: Colors.white24, height: 1),
              // Menü Öğeleri
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildDrawerItem(
                          icon: Icons.person_outline,
                          title: 'Cv Oluşturma',
                          onTap: () => Navigator.pop(context),
                        ),
                        _buildDrawerItem(
                          icon: Icons.work_outline,
                          title: 'Bağlı Cihazlar',
                          onTap: () => Navigator.pop(context),
                        ),
                        _buildDrawerItem(
                          icon: Icons.message_outlined,
                          title: 'Uygulama Güncellemeri',
                          onTap: () => Navigator.pop(context),
                        ),
                        _buildDrawerItem(
                          icon: Icons.notifications_outlined,
                          title: 'Bildirimler',
                          onTap: () {
                            Navigator.pop(context); // Drawer'ı kapat
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const NotificationSettingsPage()));
                          },
                        ),
                        _buildDrawerItem(
                          icon: Icons.settings_outlined,
                          title: 'Ayarlar',
                          onTap: () => Navigator.pop(context),
                        ),
                        const Divider(color: Colors.white24, height: 1),
                        _buildDrawerItem(
                          icon: Icons.help_outline,
                          title: 'Yardım & Destek',
                          onTap: () {
                            Navigator.pop(context); // Drawer'ı kapat
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>  YardimDestekPage(),
                              ),
                            );
                          },
                        ),
                        _buildDrawerItem(
                          icon: Icons.info_outline,
                          title: 'Hakkında',
                          onTap: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Çıkış Yap Butonu
              Container(
                decoration: BoxDecoration(
                  color: Colors.red.shade400,
                ),
                child: _buildDrawerItem(
                  icon: Icons.logout,
                  title: 'Çıkış Yap',
                  onTap: () async {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.pushNamedAndRemoveUntil(
                        context,
                        '/login',
                        (route) => false,
                      );
                    }
                  },
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.white),
      title: Text(
        title,
        style: TextStyle(
          color: color ?? Colors.white,
          fontSize: 16,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      visualDensity: const VisualDensity(vertical: -1),
    );
  }
}
