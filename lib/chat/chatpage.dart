import 'dart:math';
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
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  void _initScrollListener() {
    _scrollController.addListener(() {
      setState(() => _showScrollButton = _scrollController.offset >= 400);
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
      {String? replyTo,
      String? replyToId,
      String? replySenderName,
      Map<String, dynamic>? jobCard}) async {
    if ((_messageController.text.trim().isEmpty && jobCard == null) ||
        _isLoading) return;

    setState(() => _isLoading = true);

    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('Kullanıcı oturum açmamış');
      }

      Map<String, dynamic> messageData = {
        'senderId': currentUser.uid,
        'senderName': currentUser.displayName ?? 'İsimsiz Kullanıcı',
        'timestamp': FieldValue.serverTimestamp(),
        'edited': false,
      };

      if (jobCard != null) {
        messageData['type'] = 'job_card';
        messageData['text'] = jobCard;
        messageData['employerApproved'] = false;
        messageData['applicantApproved'] = false;
      } else {
        messageData['type'] = 'text';
        messageData['text'] = _messageController.text.trim();
      }

      if (replyTo != null && replyToId != null && replySenderName != null) {
        messageData['replyTo'] = replyTo;
        messageData['replyToId'] = replyToId;
        messageData['replySenderName'] = replySenderName;
      }

      final chatId = _getChatId();
      final chatDocRef = _firestore.collection('chats').doc(chatId);

      final chatDoc = await chatDocRef.get();
      if (!chatDoc.exists) {
        await chatDocRef.set({
          'users': [currentUser.uid, widget.otherUserId],
          'lastMessage': messageData['text'],
          'lastMessageTime': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await chatDocRef.collection('messages').add(messageData);

      if (jobCard != null) {
        await chatDocRef.update({
          'lastMessage': 'Job Card',
          'lastMessageTime': FieldValue.serverTimestamp(),
        });
      } else {
        await chatDocRef.update({
          'lastMessage': messageData['text'],
          'lastMessageTime': FieldValue.serverTimestamp(),
        });
      }

      if (_isReplying) {
        _clearReply();
      }

      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 100,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }

      // Alıcının OneSignal Player ID'sini al
      DocumentSnapshot receiverDoc =
          await _firestore.collection('users').doc(widget.otherUserId).get();

      String? receiverPlayerId = receiverDoc.get('oneSignalPlayerId');

      if (receiverPlayerId != null) {
        // OneSignal ile bildirim gönder
        await _sendPushNotification(
          receiverPlayerId,
          _messageController.text.trim(),
          _auth.currentUser!.displayName ?? 'İsimsiz Kullanıcı',
          _auth.currentUser!.photoURL ?? '',
        );
      }
    } catch (e) {
      print('Mesaj gönderme hatası: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendPushNotification(String playerId, String message,
      String senderName, String senderProfileImage) async {
    try {
      final response = await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': '10eef095-d1ee-4c36-a53d-454b1f5d6746'
        },
        body: jsonEncode({
          'app_id': '10eef095-d1ee-4c36-a53d-454b1f5d6746',
          'include_player_ids': [playerId],
          'contents': {'en': message},
          'headings': {'en': '$senderName yeni mesaj gönderdi'},
          'data': {
            'type': 'chat',
            'senderId': _auth.currentUser!.uid,
            'senderName': senderName,
            'senderProfileImage': senderProfileImage,
          },
        }),
      );
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

  void _replyToMessage(String message, String messageId, String senderName) {
    setState(() {
      _replyMessage = message;
      _replyMessageId = messageId;
      _replySenderName = senderName;
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
                      message['text'],
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                      ? Colors.white.withOpacity(0.9)
                      : Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(isSentByCurrentUser ? 20 : 5),
                    bottomRight: Radius.circular(isSentByCurrentUser ? 5 : 20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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
                                color: Colors.black.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message['replySenderName'] ??
                                        widget.otherUserName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isSentByCurrentUser
                                          ? Colors.black87
                                          : Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    message['replyTo'],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isSentByCurrentUser
                                          ? Colors.black54
                                          : Colors.white70,
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
                              color: isSentByCurrentUser
                                  ? Colors.black87
                                  : Colors.white,
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
                                    'edited',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isSentByCurrentUser
                                          ? Colors.black54
                                          : Colors.white70,
                                    ),
                                  ),
                                ),
                              Text(
                                timestamp != null
                                    ? DateFormat('HH:mm').format(timestamp)
                                    : '',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isSentByCurrentUser
                                      ? Colors.black54
                                      : Colors.white70,
                                ),
                              ),
                              if (isSentByCurrentUser)
                                Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Icon(
                                    Icons.done_all_rounded,
                                    size: 16,
                                    color: Colors.blue[400],
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
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
          return Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          );
        }

        if (snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(
              'No messages yet',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: EdgeInsets.only(bottom: 16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            DocumentSnapshot doc = snapshot.data!.docs[index];
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
    return CustomPaint(
      painter: BubblePatternPainter(),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withOpacity(0.1),
            ],
          ),
        ),
      ),
    );
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

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _replyController.dispose();
    super.dispose();
  }
}

class BubblePatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.fill;

    final random = Random();
    for (var i = 0; i < 50; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final radius = random.nextDouble() * 30 + 10;
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
