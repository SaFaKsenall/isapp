import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:myapp/chat/chatpage.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

class ChatListScreen extends StatefulWidget {
  @override
  _ChatListScreenState createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<Map<String, dynamic>> _chatRooms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchChatRooms();

    // Bildirim tıklama yönetimi
    OneSignal.Notifications.addClickListener((event) {
      if (event.notification.additionalData != null) {
        final data = event.notification.additionalData!;
        if (data['type'] == 'chat') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatPage(
                otherUserId: data['senderId'],
                otherUserName: data['senderName'],
                otherUserProfileImageUrl: data['senderProfileImage'],
              ),
            ),
          );
        }
      }
    });
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
          'lastMessageTime':
              (chatRoomData['lastMessageTime'] as Timestamp?)?.toDate() ??
                  DateTime.now(),
        });
      }

      // Son mesaj tarihine göre sırala
      chatRooms.sort((a, b) => (b['lastMessageTime'] as DateTime)
          .compareTo(a['lastMessageTime'] as DateTime));

      setState(() {
        _chatRooms = chatRooms;
        _isLoading = false;
      });
    } catch (e) {
      print('Error fetching chat rooms: $e');
      setState(() {
        _isLoading = false;
      });
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
      appBar: AppBar(
        title: Text('Mesajlar'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _chatRooms.isEmpty
              ? Center(child: Text('Henüz mesaj yok'))
              : ListView.builder(
                  itemCount: _chatRooms.length,
                  itemBuilder: (context, index) {
                    final chatRoom = _chatRooms[index];
                    return ListTile(
                      leading: Hero(
                        tag: 'profile_${chatRoom['otherUserId']}',
                        child: CircleAvatar(
                          radius: 20,
                          backgroundImage: NetworkImage(
                              chatRoom['otherUserProfileImageUrl']),
                          backgroundColor: Colors.grey[200],
                        ),
                      ),
                      title: Text(chatRoom['otherUserName']),
                      subtitle: Text(chatRoom['lastMessage']),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatPage(
                              otherUserId: chatRoom['otherUserId'],
                              otherUserName: chatRoom['otherUserName'],
                              otherUserProfileImageUrl:
                                  chatRoom['otherUserProfileImageUrl'],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}
