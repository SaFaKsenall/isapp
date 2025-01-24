import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:myapp/chat/chatpage.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ChatListScreen extends StatefulWidget {
  @override
  _ChatListScreenState createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<Map<String, dynamic>> _chatRooms = [];
  bool _isLoading = true;
  bool _isInitialized = false;
  late SharedPreferences _prefs;
  final String _chatsCacheKey = 'chats_cache';
  final String _lastFetchTimeKey = 'chats_last_fetch';

  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<Map<String, dynamic>> _filteredChatRooms = [];

  @override
  void initState() {
    super.initState();
    _quickInit();
  }

  Future<void> _quickInit() async {
    // Önce cache'den yükle
    await _loadCachedChats();

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }

    // Arka planda Firestore'dan yükle
    await _fetchChatRooms();
  }

  Future<void> _loadCachedChats() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final chatsJson = _prefs.getString(_chatsCacheKey);

      if (chatsJson != null) {
        final List<dynamic> decodedChats = json.decode(chatsJson);
        if (mounted) {
          setState(() {
            _chatRooms = List<Map<String, dynamic>>.from(decodedChats);
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Cache yükleme hatası: $e');
    }
  }

  Widget _buildSkeletonLoader() {
    return ListView.builder(
      itemCount: 5,
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemBuilder: (context, index) {
        return Card(
          margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          elevation: 0,
          child: ListTile(
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[300],
              ),
            ),
            title: Container(
              width: 140,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                SizedBox(height: 4),
                Container(
                  width: 80,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _fetchChatRooms() async {
    String currentUserId = _auth.currentUser!.uid;
    try {
      QuerySnapshot querySnapshot = await _firestore
          .collection('chats')
          .where('users', arrayContains: currentUserId)
          .get();

      List<Map<String, dynamic>> chatRooms = [];
      for (var doc in querySnapshot.docs) {
        Map<String, dynamic> chatRoomData = doc.data() as Map<String, dynamic>;
        List<String> users = List<String>.from(chatRoomData['users'] ?? []);
        String otherUserId = users.firstWhere((user) => user != currentUserId);

        String otherUserName = await _fetchOtherUserName(otherUserId);
        String otherUserProfileImageUrl =
            await _fetchOtherUserProfileImageUrl(otherUserId);

        chatRooms.add({
          'chatId': doc.id,
          'otherUserId': otherUserId,
          'otherUserName': otherUserName,
          'otherUserProfileImageUrl': otherUserProfileImageUrl,
          'lastMessage': chatRoomData['lastMessage'] ?? '',
          'lastMessageTime': (chatRoomData['lastMessageTime'] as Timestamp?)
                  ?.toDate()
                  ?.millisecondsSinceEpoch ??
              DateTime.now().millisecondsSinceEpoch,
        });
      }

      // Son mesaj tarihine göre sırala
      chatRooms
          .sort((a, b) => b['lastMessageTime'].compareTo(a['lastMessageTime']));

      // Cache'i güncelle
      await _prefs.setString(_chatsCacheKey, json.encode(chatRooms));
      await _prefs.setInt(
          _lastFetchTimeKey, DateTime.now().millisecondsSinceEpoch);

      if (mounted) {
        setState(() {
          _chatRooms = chatRooms;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Sohbet odaları yükleme hatası: $e');
    }
  }

  Future<String> _fetchOtherUserName(String otherUserId) async {
    try {
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(otherUserId).get();
      if (userDoc.exists) {
        return userDoc['username'] ?? '';
      }
    } catch (e) {
      print('Kullanıcı adı çekme hatası: $e');
    }
    return 'Bilinmeyen Kullanıcı';
  }

  Future<String> _fetchOtherUserProfileImageUrl(String otherUserId) async {
    try {
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(otherUserId).get();
      if (userDoc.exists) {
        return userDoc['profileImageUrl'] ??
            'https://randomuser.me/api/portraits/men/1.jpg';
      }
    } catch (e) {
      print('Profil fotoğrafı çekme hatası: $e');
    }
    return 'https://randomuser.me/api/portraits/men/1.jpg';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF5F6FA),
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF64B5F6), // Açık mavi
                Color(0xFF42A5F5), // Mavi
                Color(0xFF2196F3), // Koyu mavi
              ],
            ),
          ),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Sohbet ara...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                style: TextStyle(color: Colors.white),
                onChanged: _filterChats,
              )
            : Text('Mesajlar'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _filteredChatRooms = [];
                }
              });
            },
          ),
        ],
      ),
      body: !_isInitialized ? _buildSkeletonLoader() : _buildChatList(),
    );
  }

  Widget _buildChatList() {
    final chatsToShow = _isSearching && _searchController.text.isNotEmpty
        ? _filteredChatRooms
        : _chatRooms;

    if (chatsToShow.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 70, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              _isSearching ? 'Sohbet bulunamadı' : 'Henüz mesaj yok',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: chatsToShow.length,
      itemBuilder: (context, index) {
        final chatRoom = chatsToShow[index];
        return Card(
          margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          elevation: 0,
          child: ListTile(
            leading: Hero(
              tag: 'profile_${chatRoom['otherUserId']}',
              child: CircleAvatar(
                radius: 25,
                backgroundImage:
                    NetworkImage(chatRoom['otherUserProfileImageUrl']),
                backgroundColor: Colors.grey[200],
              ),
            ),
            title: Text(
              chatRoom['otherUserName'],
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chatRoom['lastMessage'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatDateTime(chatRoom['lastMessageTime']),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            onTap: () => _navigateToChat(chatRoom),
          ),
        );
      },
    );
  }

  void _filterChats(String query) {
    setState(() {
      _filteredChatRooms = _chatRooms
          .where((chat) => chat['otherUserName']
              .toString()
              .toLowerCase()
              .contains(query.toLowerCase()))
          .toList();
    });
  }

  String _formatDateTime(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Dün';
    } else if (difference.inDays < 7) {
      final weekDays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
      return weekDays[dateTime.weekday - 1];
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  void _navigateToChat(Map<String, dynamic> chatRoom) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatPage(
          otherUserId: chatRoom['otherUserId'],
          otherUserName: chatRoom['otherUserName'],
          otherUserProfileImageUrl: chatRoom['otherUserProfileImageUrl'],
        ),
      ),
    ).then((_) => _fetchChatRooms()); // Geri döndüğünde sohbetleri yenile
  }
}
