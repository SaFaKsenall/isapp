import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({Key? key}) : super(key: key);

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _newJobNotifications = true;
  bool _allNotifications = true;
  bool _chatNotifications = true;
  bool _updateNotifications = true;
  bool _isLoading = true;
  bool _hasSystemPermission = false;

  @override
  void initState() {
    super.initState();
    _initializeNotificationSettings();
  }

  Future<void> _initializeNotificationSettings() async {
    await _checkNotificationPermission();
    await _loadSettings();
  }

  Future<void> _checkNotificationPermission() async {
    try {
      final deviceState = await OneSignal.Notifications.permission;
      final subscriptionState = await OneSignal.User.pushSubscription.optedIn;

      setState(() {
        _hasSystemPermission = deviceState ?? false;
        _allNotifications =
            (deviceState ?? false) && (subscriptionState ?? false);
      });

      // SharedPreferences'ı güncelle
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('allNotifications', _allNotifications);
    } catch (e) {
      print('Bildirim izni kontrol hatası: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _newJobNotifications = prefs.getBool('newJobNotifications') ?? true;
        _chatNotifications = prefs.getBool('chatNotifications') ?? true;
        _updateNotifications = prefs.getBool('updateNotifications') ?? true;
        _isLoading = false;
      });
    } catch (e) {
      print('Ayarlar yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleAllNotifications(bool value) async {
    if (value) {
      try {
        // OneSignal bildirim izni kontrolü
        final deviceState = await OneSignal.Notifications.permission;

        if (!deviceState) {
          // Bildirim izni yoksa, anasayfa.dart'taki gibi izin iste
          if (mounted) {
            final result = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Bildirim İzni'),
                content: const Text(
                  'Uygulamamız size önemli güncellemeler ve bildirimler göndermek istiyor. İzin vermek ister misiniz?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text(
                      'Hayır',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('İzin Ver'),
                  ),
                ],
              ),
            );

            if (result == true) {
              // OneSignal'ı başlat ve izin iste
              print('OneSignal başlatılıyor...');
              OneSignal.initialize('10eef095-d1ee-4c36-a53d-454b1f5d6746');

              print('Bildirim izni isteniyor...');
              final permissionResult =
                  await OneSignal.Notifications.requestPermission(true);
              print(
                  'Bildirim izni durumu: ${permissionResult ? "İzin Verildi ✅" : "İzin Reddedildi ❌"}');

              if (permissionResult) {
                print('Push subscription bilgisi alınıyor...');
                final status = await OneSignal.User.pushSubscription;
                print(
                    'Push subscription durumu: ${status?.id != null ? "Aktif ✅" : "Pasif ❌"}');
                print('Push token: ${status?.id ?? "Alınamadı ❌"}');

                final playerId = status?.id;
                if (playerId != null) {
                  print('Player ID başarıyla alındı ✅: $playerId');
                  final currentUser = FirebaseAuth.instance.currentUser;
                  if (currentUser != null) {
                    print('Player ID Firestore\'a kaydediliyor...');
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(currentUser.uid)
                        .update({'oneSignalPlayerId': playerId});
                    print('Player ID Firestore\'a başarıyla kaydedildi ✅');
                  }
                }

                // Tüm bildirimleri aç
                setState(() {
                  _hasSystemPermission = true;
                  _allNotifications = true;
                  _newJobNotifications = true;
                  _chatNotifications = true;
                  _updateNotifications = true;
                });

                // SharedPreferences'ı güncelle
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('allNotifications', true);
                await prefs.setBool('newJobNotifications', true);
                await prefs.setBool('chatNotifications', true);
                await prefs.setBool('updateNotifications', true);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Bildirimler başarıyla açıldı'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } else {
                await _disableAllNotifications();
              }
            } else {
              await _disableAllNotifications();
            }
          }
        } else {
          // Bildirim izni varsa direkt aç
          await _enableAllNotifications();
        }
      } catch (e) {
        print('Bildirim izni hatası: $e');
        await _disableAllNotifications();
      }
    } else {
      // Bildirimleri kapat
      await _disableAllNotifications();
    }
  }

  // Tüm bildirimleri açma fonksiyonu
  Future<void> _enableAllNotifications() async {
    await OneSignal.User.pushSubscription.optIn();

    setState(() {
      _hasSystemPermission = true;
      _allNotifications = true;
      _newJobNotifications = true;
      _chatNotifications = true;
      _updateNotifications = true;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('allNotifications', true);
    await prefs.setBool('newJobNotifications', true);
    await prefs.setBool('chatNotifications', true);
    await prefs.setBool('updateNotifications', true);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bildirimler başarıyla açıldı'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // Tüm bildirimleri kapatma fonksiyonu
  Future<void> _disableAllNotifications() async {
    try {
      print('Bildirimler kapatılıyor...');
      await OneSignal.User.pushSubscription.optOut();
      print('OneSignal aboneliği kapatıldı ✅');

      setState(() {
        _hasSystemPermission = false;
        _allNotifications = false;
        _newJobNotifications = false;
        _chatNotifications = false;
        _updateNotifications = false;
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('allNotifications', false);
      await prefs.setBool('newJobNotifications', false);
      await prefs.setBool('chatNotifications', false);
      await prefs.setBool('updateNotifications', false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tüm bildirimler kapatıldı'),
            backgroundColor: Colors.grey,
          ),
        );
      }
    } catch (e) {
      print('Bildirimleri kapatma hatası: $e');
    }
  }

  Future<void> _updateSettings(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      print('Ayarlar kaydedilirken hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirim Ayarları'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  if (!_hasSystemPermission)
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_amber_rounded,
                                  color: Colors.orange.shade700),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Bildirimler kapalı',
                                  style: TextStyle(
                                    color: Colors.orange.shade900,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Önemli güncellemeler ve mesajları kaçırmamak için bildirimleri açmanızı öneririz.',
                            style: TextStyle(color: Colors.orange.shade800),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => _toggleAllNotifications(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade100,
                              foregroundColor: Colors.orange.shade900,
                            ),
                            child: const Text('Bildirimleri Etkinleştir'),
                          ),
                        ],
                      ),
                    ),
                  // Bildirim ayarları listesi...
                  _buildNotificationSettings(),
                ],
              ),
            ),
    );
  }

  Widget _buildNotificationSettings() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildNotificationTile(
            title: 'Tüm Bildirimler',
            subtitle: _hasSystemPermission
                ? 'Tüm bildirimleri yönet'
                : 'Bildirimleri etkinleştir',
            icon: Icons.notifications,
            value: _allNotifications,
            onChanged: _toggleAllNotifications,
            color: Colors.blue,
          ),
          if (_allNotifications && _hasSystemPermission) ...[
            const Divider(),
            _buildNotificationTile(
              title: 'Yeni İş İlanları',
              subtitle: 'Yeni iş ilanlarından haberdar ol',
              icon: Icons.work,
              value: _newJobNotifications,
              onChanged: (value) async {
                setState(() => _newJobNotifications = value);
                await _updateSettings('newJobNotifications', value);
              },
              color: Colors.purple,
            ),
            _buildNotificationTile(
              title: 'Sohbet Bildirimleri',
              subtitle: 'Yeni mesajlardan haberdar ol',
              icon: Icons.chat,
              value: _chatNotifications,
              onChanged: (value) async {
                setState(() => _chatNotifications = value);
                await _updateSettings('chatNotifications', value);
              },
              color: Colors.green,
            ),
            _buildNotificationTile(
              title: 'Güncellemeler',
              subtitle: 'Yeni özelliklerden haberdar ol',
              icon: Icons.system_update,
              value: _updateNotifications,
              onChanged: (value) async {
                setState(() => _updateNotifications = value);
                await _updateSettings('updateNotifications', value);
              },
              color: Colors.orange,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNotificationTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required Function(bool) onChanged,
    required Color color,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: color,
      ),
    );
  }
}
