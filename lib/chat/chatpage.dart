import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ChatPage extends StatefulWidget {
  final String otherUserId;
  final String otherUserName;
  final String otherUserProfileImageUrl;

  ChatPage({
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserProfileImageUrl,
  });

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _replyMessage;
  String? _replyMessageId;
  String? _replySenderName;
  bool _isReplying = false;
  bool _isLoading = false;
  bool _showScrollButton = false;

  late AnimationController _replyController;
  late Animation<double> _replyAnimation;
  late Stream<QuerySnapshot> _messagesStream;
  String? _jobEmployerId;
  bool _isFirstLoad = true;
  final List<String> _recentMessages = [];
  static const int _messageHistoryLimit = 3;
  bool _isProcessingAutoMessage = false;
  DateTime? _lastAutoMessageTime;

  @override
  void initState() {
    super.initState();
    _initMessageStream();
    _initScrollListener();
    _initReplyAnimation();
    _fetchJobEmployerId();
  }

  Future<void> _fetchJobEmployerId() async {
    try {
      final chatDocRef =
          FirebaseFirestore.instance.collection('chats').doc(_getChatId());

      final messageSnapshot = await chatDocRef
          .collection('messages')
          .where('type', isEqualTo: 'job_card')
          .limit(1)
          .get();

      if (messageSnapshot.docs.isNotEmpty) {
        final jobCardData =
            messageSnapshot.docs.first.get('text') as Map<String, dynamic>;
        setState(() {
          _jobEmployerId = jobCardData['employerId'];
        });
      }
    } catch (e) {
      print('İşveren id getirilirken bir hata oluştu: $e');
    }
  }

  void _initMessageStream() {
    _messagesStream = _firestore
        .collection('chats')
        .doc(_getChatId())
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();

    // Sadece yeni mesaj gönderildiğinde scroll yapılacak
    _messagesStream.listen((snapshot) {
      if (_isFirstLoad && snapshot.docs.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom(animate: false);
          _isFirstLoad = false;
        });
      }
    });
  }

  void _initScrollListener() {
    _scrollController.addListener(() {
      setState(() {
        _showScrollButton = _scrollController.position.maxScrollExtent -
                _scrollController.offset >
            400;
      });
    });
  }

  void _initReplyAnimation() {
    _replyController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 200),
    );
    _replyAnimation = CurvedAnimation(
      parent: _replyController,
      curve: Curves.easeOut,
    );
  }

  String _getChatId() {
    List<String> ids = [_auth.currentUser!.uid, widget.otherUserId]..sort();
    return ids.join('_');
  }

  Future<void> _sendMessage(
      {String? replyTo, String? replyToId, String? replySenderName}) async {
    if (_messageController.text.trim().isEmpty || _isLoading) return;
    setState(() => _isLoading = true);

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) throw Exception('Kullanıcı oturum açmamış');

      final messageText = _messageController.text.trim();

      // Hassas bilgi kontrolü
      bool containsSensitiveInfo = _checkForSensitiveInfo(messageText);

      // Mesajı Firestore'a gönder
      await _sendMessageToFirestore(
        currentUser,
        replyTo,
        replyToId,
        replySenderName,
      );

      // UI'ı güncelle
      _messageController.clear();
      if (_isReplying) _clearReply();

      // Hassas bilgi yoksa bildirim gönder
      if (!containsSensitiveInfo) {
        try {
          final receiverDoc = await _firestore
              .collection('users')
              .doc(widget.otherUserId)
              .get();
          if (receiverDoc.exists) {
            final receiverData = receiverDoc.data() as Map<String, dynamic>;
            final receiverPlayerId =
                receiverData['oneSignalPlayerId'] as String?;

            if (receiverPlayerId != null && receiverPlayerId.isNotEmpty) {
              await _sendPushNotification(
                receiverPlayerId,
                messageText,
                currentUser.displayName ?? 'İsimsiz Kullanıcı',
                currentUser.photoURL ?? '',
              );
            } else {
              print('Alıcının OneSignal Player ID\'si bulunamadı');
            }
          }
        } catch (e) {
          print('Bildirim gönderme hatası: $e');
        }
      }
    } catch (e) {
      print('Mesaj gönderme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mesaj gönderilemedi: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Hassas bilgi kontrolü için yeni yardımcı metod
  bool _checkForSensitiveInfo(String newMessage) {
    // Son mesajları birleştir
    _recentMessages.add(newMessage);
    if (_recentMessages.length > _messageHistoryLimit) {
      _recentMessages.removeAt(0);
    }

    String combinedText = _recentMessages.join(' ');

    // E-posta kontrolü - daha spesifik regex
    final emailRegex =
        RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b');

    // Telefon kontrolü - sadece gerçek telefon formatları
    final phoneRegex = RegExp(
        r'\b(?:0|90|\+90)?\s*[-.]?\s*([5]{1}[0-9]{2})\s*[-.]?\s*([0-9]{3})\s*[-.]?\s*([0-9]{2})\s*[-.]?\s*([0-9]{2})\b');

    bool containsSensitive =
        emailRegex.hasMatch(combinedText) || phoneRegex.hasMatch(combinedText);

    if (containsSensitive) {
      _recentMessages.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Telefon numarası veya e-posta paylaşımı yasaktır!'),
          backgroundColor: Colors.red,
        ),
      );
    }

    return containsSensitive;
  }

  Future<void> _sendPushNotification(
    String playerId,
    String message,
    String senderName,
    String senderProfileImage,
  ) async {
    try {
      if (playerId.isEmpty) {
        print('Player ID boş, bildirim gönderilemiyor');
        return;
      }

      // Gönderen kullanıcının güncel bilgilerini al
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final senderDoc =
          await _firestore.collection('users').doc(currentUser.uid).get();
      if (!senderDoc.exists) return;

      final senderData = senderDoc.data() as Map<String, dynamic>;
      final displayName = senderData['username'] ?? 'İsimsiz Kullanıcı';
      final profileImage = senderData['profileImageUrl'] ?? '';

      // OneSignal API isteği için body
      final notificationData = {
        'app_id': '10eef095-d1ee-4c36-a53d-454b1f5d6746',
        'include_player_ids': [playerId],
        'contents': {'en': message, 'tr': message},
        'headings': {
          'en': '$displayName\'den yeni mesaj',
          'tr': '$displayName\'den yeni mesaj'
        },
        'android_channel_id': 'de874a32-5881-4403-8cdb-bd5a7ce62ea0',
        'android_group': 'chat_messages',
        'priority': 10,
        'data': {
          'type': 'chat',
          'senderId': currentUser.uid,
          'senderName': displayName,
          'senderProfileImage': profileImage,
          'chatId': _getChatId(),
          'otherUserId': widget.otherUserId,
          'otherUserName': widget.otherUserName,
          'otherUserProfileImageUrl': widget.otherUserProfileImageUrl
        },
        'android_sound': 'notification',
        'android_visibility': 1,
        'collapse_id': 'chat_${_getChatId()}',
        'ttl': 259200,
        'small_icon': 'ic_notification_icon', // Uygulamanızın bildirim ikonu
        'large_icon': profileImage, // Gönderenin profil resmi
        'android_accent_color': 'FF2196F3' // Bildirim rengi
      };

      final response = await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization':
              'Basic os_v2_app_cdxpbfor5zgdnjj5ivfr6xlhi3wgpfskcrxee54wnloqfi6v23uv5r6lvquo3altr5q3ouryhgwnsslfbvlmnb75nroi2ioxeulodci'
        },
        body: jsonEncode(notificationData),
      );

      if (response.statusCode != 200) {
        print('Bildirim gönderme hatası: ${response.statusCode}');
        print('Hata detayı: ${response.body}');
        return;
      }

      print('Bildirim başarıyla gönderildi');
      print('Alıcı Player ID: $playerId');
      print('Gönderen: $displayName');
      print('Mesaj: $message');
      print('Response: ${response.body}');
    } catch (e) {
      print('Bildirim gönderme hatası: $e');
    }
  }

  Future<void> _handleApproval(String messageId, String approvalType,
      Map<String, dynamic> messageData) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final chatDocRef =
          FirebaseFirestore.instance.collection('chats').doc(_getChatId());

      final messageDocRef = chatDocRef.collection('messages').doc(messageId);

      if (approvalType == 'employerApproved') {
        await messageDocRef
            .update({'employerApproved': !messageData['employerApproved']});
      } else if (approvalType == 'applicantApproved') {
        await messageDocRef
            .update({'applicantApproved': !messageData['applicantApproved']});
      }
    } catch (e) {
      print('Onay işlemi sırasında bir hata oluştu: $e');
    }
  }

  void _replyToMessage(
      Map<String, dynamic> message, String messageId, String senderName) {
    setState(() {
      _replyMessage = message['text'];
      _replyMessageId = messageId;
      _replySenderName = message['senderId'] == _auth.currentUser!.uid
          ? message['senderName']
          : widget.otherUserName;
      _isReplying = true;
    });
    _replyController.forward();
  }

  void _clearReply() {
    _replyController.reverse().then((_) {
      setState(() {
        _replyMessage = null;
        _replyMessageId = null;
        _replySenderName = null;
        _isReplying = false;
      });
    });
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      await _firestore
          .collection('chats')
          .doc(_getChatId())
          .collection('messages')
          .doc(messageId)
          .delete();

      // Update last message
      DocumentSnapshot chatDoc =
          await _firestore.collection('chats').doc(_getChatId()).get();

      if (chatDoc.exists) {
        QuerySnapshot previousMessages = await _firestore
            .collection('chats')
            .doc(_getChatId())
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(1)
            .get();

        if (previousMessages.docs.isNotEmpty) {
          await _firestore.collection('chats').doc(_getChatId()).update({
            'lastMessage': previousMessages.docs.first.get('text'),
            'lastMessageTime': previousMessages.docs.first.get('timestamp'),
          });
        } else {
          await _firestore.collection('chats').doc(_getChatId()).update({
            'lastMessage': '',
            'lastMessageTime': FieldValue.serverTimestamp(),
          });
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mesaj silindi'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mesaj silinirken bir hata oluştu: $e'),
          backgroundColor: Colors.red,
        ),
      );
      print('Mesaj silme hatası: $e');
    }
  }

  Future<void> _editMessage(String messageId, String currentText) async {
    TextEditingController editController =
        TextEditingController(text: currentText);

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white.withOpacity(0.9),
        title: Text('Edit Message'),
        content: TextField(
          controller: editController,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          maxLines: null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (editController.text.trim().isNotEmpty) {
                try {
                  await _firestore
                      .collection('chats')
                      .doc(_getChatId())
                      .collection('messages')
                      .doc(messageId)
                      .update({
                    'text': editController.text.trim(),
                    'edited': true,
                    'editedAt': FieldValue.serverTimestamp(),
                  });
                  Navigator.pop(context);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to edit message: $e')),
                  );
                }
              }
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showMessageOptions(
    BuildContext context,
    Map<String, dynamic> message,
    String messageId,
    bool isSentByCurrentUser,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message['type'] != 'job_card')
                _buildOptionTile(
                  icon: Icons.reply_rounded,
                  title: 'Reply',
                  onTap: () {
                    Navigator.pop(context);
                    _replyToMessage(
                      message,
                      messageId,
                      message['senderName'] ?? widget.otherUserName,
                    );
                  },
                ),
              if (message['type'] != 'job_card')
                _buildOptionTile(
                  icon: Icons.copy_rounded,
                  title: 'Copy',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message['text']));
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Message copied')),
                    );
                  },
                ),
              if (isSentByCurrentUser) ...[
                if (message['type'] != 'job_card')
                  _buildOptionTile(
                    icon: Icons.edit_rounded,
                    title: 'Edit',
                    onTap: () {
                      Navigator.pop(context);
                      _editMessage(messageId, message['text']);
                    },
                  ),
                _buildOptionTile(
                  icon: Icons.delete_rounded,
                  title: 'Delete',
                  onTap: () {
                    Navigator.pop(context);
                    _deleteMessage(messageId);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue[700]),
      title: Text(title),
      onTap: onTap,
      horizontalTitleGap: 0,
    );
  }

  Widget _buildJobCardMessage(Map<String, dynamic> message,
      bool isSentByCurrentUser, String messageId) {
    final jobData = message['text'] as Map<String, dynamic>;
    List<int> gradientInts = (jobData['gradient'] as List).cast<int>();
    List<Color> gradientColors =
        gradientInts.map((intColor) => Color(intColor)).toList();
    final currentUser = FirebaseAuth.instance.currentUser;
    final isJobOwner = currentUser != null && currentUser.uid == _jobEmployerId;
    final isApplicant =
        currentUser != null && currentUser.uid != _jobEmployerId;

    return Container(
      margin: EdgeInsets.only(
        left: isSentByCurrentUser ? 60 : 10,
        right: isSentByCurrentUser ? 10 : 60,
        top: 4,
        bottom: 4,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            offset: Offset(0, 8),
            blurRadius: 15,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundImage: NetworkImage(jobData['profileImage']),
                  radius: 20,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        jobData['username'] ?? 'Unknown User',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            Text(
              jobData['jobTitle'],
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 5),
            Text(
              jobData['jobDescription'],
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '₺${(jobData['budget'] as num).toStringAsFixed(2)}',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.favorite_border, color: Colors.white),
                    SizedBox(width: 5),
                    Text('${jobData['likes']}',
                        style: TextStyle(color: Colors.white)),
                    SizedBox(width: 10),
                    Icon(Icons.comment_outlined, color: Colors.white),
                    SizedBox(width: 5),
                    Text('${jobData['comments']}',
                        style: TextStyle(color: Colors.white)),
                  ],
                ),
              ],
            ),
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: isJobOwner
                      ? () => _handleApproval(
                          messageId, 'employerApproved', message)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: message['employerApproved']
                        ? Colors.green
                        : Colors.blueGrey,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                      message['employerApproved']
                          ? 'İşveren Onayladı'
                          : 'İşveren Onayla',
                      style: TextStyle(fontSize: 13)),
                ),
                ElevatedButton(
                  onPressed: isApplicant
                      ? () => _handleApproval(
                          messageId, 'applicantApproved', message)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: message['applicantApproved']
                        ? Colors.green
                        : Colors.blueGrey,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                      message['applicantApproved']
                          ? 'İşi Alan Onayladı'
                          : 'İşi Alan Onayla',
                      style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutomaticMessage(
      Map<String, dynamic> message, bool isSentByCurrentUser) {
    return Container(
      margin: EdgeInsets.only(
        left: isSentByCurrentUser ? 60 : 10,
        right: isSentByCurrentUser ? 10 : 60,
        top: 4,
        bottom: 4,
      ),
      decoration: BoxDecoration(
        color: isSentByCurrentUser ? Color(0xFFDCF8C6) : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isSentByCurrentUser ? 12 : 0),
          topRight: Radius.circular(isSentByCurrentUser ? 0 : 12),
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(10),
        child: Text(
          message['text'],
          style: TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    Map<String, dynamic> message,
    bool isSentByCurrentUser,
    String messageId,
  ) {
    DateTime? timestamp = message['timestamp']?.toDate();
    bool isEdited = message['edited'] ?? false;

    if (message['type'] == 'automatic_message') {
      return GestureDetector(
        onLongPress: () => _showMessageOptions(
            context, message, messageId, isSentByCurrentUser),
        child: _buildAutomaticMessage(message, isSentByCurrentUser),
      );
    }
    if (message['type'] == 'job_card') {
      return GestureDetector(
        onLongPress: () => _showMessageOptions(
            context, message, messageId, isSentByCurrentUser),
        child: _buildJobCardMessage(message, isSentByCurrentUser, messageId),
      );
    }

    return GestureDetector(
      onLongPress: () => _showMessageOptions(
        context,
        message,
        messageId,
        isSentByCurrentUser,
      ),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          mainAxisAlignment: isSentByCurrentUser
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (!isSentByCurrentUser && message['replyTo'] == null)
              CircleAvatar(
                radius: 12,
                backgroundImage: NetworkImage(widget.otherUserProfileImageUrl),
              ),
            SizedBox(width: 8),
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                decoration: BoxDecoration(
                  color: isSentByCurrentUser
                      ? Color(0xFF2196F3)
                      : Color(0xFF424242),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message['replyTo'] != null) ...[
                        Container(
                          padding: EdgeInsets.all(8),
                          margin: EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message['replySenderName'] ??
                                    (message['senderId'] ==
                                            _auth.currentUser!.uid
                                        ? _auth.currentUser!.displayName ??
                                            'İsimsiz Kullanıcı'
                                        : widget.otherUserName),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                message['replyTo'],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                      Text(
                        message['text'],
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isEdited)
                            Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Text(
                                'düzenlendi',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          Text(
                            timestamp != null
                                ? DateFormat('HH:mm').format(timestamp)
                                : '',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyArea() {
    return SizeTransition(
      sizeFactor: _replyAnimation,
      child: _isReplying
          ? ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    border: Border(
                      top: BorderSide(color: Colors.white24, width: 0.5),
                      bottom: BorderSide(color: Colors.white24, width: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.blue[400],
                          borderRadius: BorderRadius.circular(2),
                        ),
                        margin: EdgeInsets.only(right: 12),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _replySenderName ?? widget.otherUserName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[400],
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              _replyMessage ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: Colors.white70),
                        onPressed: _clearReply,
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints(),
                        iconSize: 20,
                      ),
                    ],
                  ),
                ),
              ),
            )
          : SizedBox.shrink(),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(color: Colors.white24, width: 0.5),
        ),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              CircleAvatar(
                radius: 20,
                backgroundImage: NetworkImage(widget.otherUserProfileImageUrl),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.otherUserName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Online',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.video_call_rounded, color: Colors.white),
                onPressed: () {},
              ),
              IconButton(
                icon: Icon(Icons.call_rounded, color: Colors.white),
                onPressed: () {},
              ),
              IconButton(
                icon: Icon(Icons.more_vert_rounded, color: Colors.white),
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _messagesStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              'Henüz mesaj yok',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        // Mesajları ters çeviriyoruz
        final messages = snapshot.data!.docs.reversed.toList();

        return ListView.builder(
          controller: _scrollController,
          reverse: false, // Normal sıralama
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            DocumentSnapshot doc = messages[index];
            Map<String, dynamic> message = doc.data() as Map<String, dynamic>;
            bool isSentByCurrentUser =
                message['senderId'] == _auth.currentUser!.uid;
            return _buildMessageBubble(message, isSentByCurrentUser, doc.id);
          },
        );
      },
    );
  }

  Widget _buildScrollButton() {
    return Positioned(
      right: 16,
      bottom: 16,
      child: FloatingActionButton(
        mini: true,
        backgroundColor: Colors.white.withOpacity(0.9),
        onPressed: () {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        },
        child: Icon(
          Icons.keyboard_arrow_down_rounded,
          color: Colors.blue[700],
        ),
      ),
    );
  }

  Widget _buildChatBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.3, 0.6, 1.0],
          colors: [
            Color(0xFF2B2E4A), // Koyu mor
            Color(0xFF353866), // Mor-mavi geçiş
            Color(0xFF3E4491), // Mavi-mor
            Color(0xFF4B51AC), // Parlak mavi
          ],
        ),
      ),
    );
  }

  void _scrollToBottom({bool animate = true}) {
    if (_scrollController.hasClients) {
      if (animate) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1A237E),
              Color(0xFF0D47A1),
              Color(0xFF01579B),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildAppBar(),
              Expanded(
                child: Stack(
                  children: [
                    _buildChatBackground(),
                    _buildMessageList(),
                    if (_showScrollButton) _buildScrollButton(),
                  ],
                ),
              ),
              _buildReplyArea(),
              _buildMessageInput(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            border: Border(
              top: BorderSide(color: Colors.white24, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: Colors.white24,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          style: TextStyle(color: Colors.black),
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle: TextStyle(color: Colors.white70),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.emoji_emotions_outlined,
                            color: Colors.white70),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: Icon(Icons.attach_file_rounded,
                            color: Colors.white70),
                        onPressed: () {},
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue[400]!, Colors.blue[600]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(
                    _isLoading ? Icons.hourglass_empty : Icons.send_rounded,
                    color: Colors.white,
                  ),
                  onPressed: _isLoading
                      ? null
                      : () {
                          if (_messageController.text.trim().isNotEmpty) {
                            _sendMessage(
                              replyTo: _replyMessage,
                              replyToId: _replyMessageId,
                              replySenderName: _replySenderName,
                            );
                          }
                        },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendMessageToFirestore(
    User currentUser,
    String? replyTo,
    String? replyToId,
    String? replySenderName,
  ) async {
    final chatId = _getChatId();
    final chatDocRef = _firestore.collection('chats').doc(chatId);

    // Mesaj metnini kontrol et
    String messageText = _messageController.text.trim();
    bool containsSensitiveInfo = _checkForSensitiveInfo(messageText);

    // Hassas bilgi varsa şifrele
    if (containsSensitiveInfo) {
      // E-posta şifreleme
      final emailRegex =
          RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}');
      messageText = messageText.replaceAll(emailRegex, '******');

      // Telefon numarası şifreleme
      final phoneRegex =
          RegExp(r'(?:\+90|0)?\s*([0-9]{3}[\s-]?[0-9]{3}[\s-]?[0-9]{4})');
      messageText = messageText.replaceAll(phoneRegex, '******');
    }

    // Kullanıcı bilgilerini al
    final userDoc =
        await _firestore.collection('users').doc(currentUser.uid).get();
    final userData = userDoc.data() as Map<String, dynamic>;
    final displayName = userData['username'] ??
        userData['name'] ??
        currentUser.displayName ??
        'İsimsiz Kullanıcı';

    // Mesajı gönder
    Map<String, dynamic> messageData = {
      'senderId': currentUser.uid,
      'senderName': displayName,
      'text': messageText,
      'timestamp': FieldValue.serverTimestamp(),
      'type': 'text',
      'edited': false,
    };

    if (replyTo != null) {
      messageData['replyTo'] = replyTo;
      messageData['replyToId'] = replyToId;
      messageData['replySenderName'] = replySenderName;
    }

    // Chat dokümanını kontrol et ve oluştur
    final chatDoc = await chatDocRef.get();
    if (!chatDoc.exists) {
      await chatDocRef.set({
        'users': [currentUser.uid, widget.otherUserId],
        'lastMessage': messageData['text'],
        'lastMessageTime': FieldValue.serverTimestamp(),
      });
    }

    // Mesajı kaydet
    final jobCardMessageDoc =
        await chatDocRef.collection('messages').add(messageData);
    await chatDocRef.update({
      'lastMessage': messageData['text'],
      'lastMessageTime': FieldValue.serverTimestamp(),
    });

    // Yeni mesaj gönderildiğinde en alta kaydır
    _scrollToBottom(animate: true);

    // Eğer hassas bilgi tespit edildiyse uyarı mesajı gönder
    if (containsSensitiveInfo) {
      Map<String, dynamic> warningMessage = {
        'senderId': 'system',
        'senderName': 'Sistem',
        'text':
            'Telefon numarası veya eposta gibi önemli verilerin paylaşılması yasaktır.',
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'automatic_message',
      };

      await chatDocRef.collection('messages').add(warningMessage);
      await chatDocRef.update({
        'lastMessage': warningMessage['text'],
        'lastMessageTime': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _approveJob(String messageId, String approverType) async {
    try {
      final chatId = generateChatId(
        FirebaseAuth.instance.currentUser!.uid,
        widget.otherUserId,
      );

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({
        '${approverType}Approved': true,
        '${approverType}ApprovedAt': FieldValue.serverTimestamp(),
      });

      // Karşı tarafa bildirim gönder
      final otherUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherUserId)
          .get();

      if (otherUserDoc.exists) {
        final otherUserData = otherUserDoc.data() as Map<String, dynamic>;
        final playerId = otherUserData['oneSignalPlayerId'];

        if (playerId != null) {
          final message = approverType == 'employer'
              ? 'İşveren anlaşmayı onayladı!'
              : 'İşi alan kişi anlaşmayı onayladı!';

          await _sendPushNotification(
            playerId,
            message,
            widget.otherUserName,
            widget.otherUserProfileImageUrl,
          );
        }
      }
    } catch (e) {
      print('Onaylama hatası: $e');
    }
  }

  String generateChatId(String user1, String user2) {
    List<String> ids = [user1, user2];
    ids.sort();
    return '${ids[0]}_${ids[1]}';
  }

  Widget _buildMessageCard(Map<String, dynamic> message, bool isMe) {
    if (message['type'] == 'job_card') {
      final jobData = message['text'] as Map<String, dynamic>;
      final currentUser = FirebaseAuth.instance.currentUser;
      final isEmployer = jobData['employerId'] == currentUser?.uid;
      final isApplicant =
          currentUser?.uid == message['senderId'] && !isEmployer;
      final employerApproved = message['employerApproved'] ?? false;
      final applicantApproved = message['applicantApproved'] ?? false;

      return Container(
        margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  jobData['jobTitle'] ?? '',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  alignment: WrapAlignment.spaceEvenly,
                  children: [
                    if (isEmployer)
                      SizedBox(
                        width: 140,
                        child: ElevatedButton(
                          onPressed: !employerApproved
                              ? () => _approveJob(
                                  message['messageId'] as String, 'employer')
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                employerApproved ? Colors.green : Colors.grey,
                          ),
                          child: Text(
                            employerApproved
                                ? 'İşveren Onayladı ✓'
                                : 'İşveren Onayı',
                            style: TextStyle(
                              fontSize: 13,
                              color: employerApproved
                                  ? Colors.white
                                  : Colors.black54,
                            ),
                          ),
                        ),
                      ),
                    if (isApplicant)
                      SizedBox(
                        width: 140,
                        child: ElevatedButton(
                          onPressed: !applicantApproved
                              ? () => _approveJob(
                                  message['messageId'] as String, 'applicant')
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                applicantApproved ? Colors.green : Colors.grey,
                          ),
                          child: Text(
                            applicantApproved
                                ? 'İşi Alan Onayladı ✓'
                                : 'İşi Alan Onayı',
                            style: TextStyle(
                              fontSize: 13,
                              color: applicantApproved
                                  ? Colors.white
                                  : Colors.black54,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    return _buildNormalMessage(message, isMe);
  }

  Widget _buildNormalMessage(Map<String, dynamic> message, bool isMe) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMe ? Colors.blue[100] : Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message['text'] as String,
        style: TextStyle(fontSize: 16),
      ),
    );
  }

  // Otomatik mesaj gönderimi için yeni kontrol metodu
  Future<bool> _canSendAutoMessage() async {
    if (_isProcessingAutoMessage) return false;
    
    final now = DateTime.now();
    if (_lastAutoMessageTime != null) {
      final difference = now.difference(_lastAutoMessageTime!);
      if (difference.inSeconds < 2) { // 2 saniye minimum bekleme süresi
        return false;
      }
    }
    
    _isProcessingAutoMessage = true;
    _lastAutoMessageTime = now;
    
    // 2 saniye sonra işlem kilidini kaldır
    await Future.delayed(Duration(seconds: 2));
    _isProcessingAutoMessage = false;
    
    return true;
  }

  // Otomatik mesaj gönderme metodunu güncelle
  Future<void> _sendAutomaticMessage(String message) async {
    if (!await _canSendAutoMessage()) return;

    try {
      final chatId = _getChatId();
      final automaticMessage = {
        'senderId': 'system',
        'senderName': 'Sistem',
        'text': message,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'automatic_message',
      };

      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add(automaticMessage);

      await _firestore.collection('chats').doc(chatId).update({
        'lastMessage': automaticMessage['text'],
        'lastMessageTime': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Otomatik mesaj gönderme hatası: $e');
    }
  }
}

class TexturedBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final path = Path();
    final cellSize = 30.0;
    final patternSize = 15.0;

    for (double x = 0; x < size.width; x += cellSize) {
      for (double y = 0; y < size.height; y += cellSize) {
        path.reset();

        // Desenli doku oluştur
        path.moveTo(x, y);
        path.addArc(
          Rect.fromCenter(
            center: Offset(x + patternSize / 2, y + patternSize / 2),
            width: patternSize,
            height: patternSize,
          ),
          0,
          3.14,
        );

        // İkinci desen katmanı
        path.addArc(
          Rect.fromCenter(
            center: Offset(x + patternSize, y + patternSize),
            width: patternSize * 0.8,
            height: patternSize * 0.8,
          ),
          3.14,
          3.14,
        );

        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
