import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SupportTicketsPage extends StatefulWidget {
  @override
  _SupportTicketsPageState createState() => _SupportTicketsPageState();
}

class _SupportTicketsPageState extends State<SupportTicketsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _supportTickets = [];
  bool _isLoading = true;
  String? _currentAgentName;
  bool _isLiveChat = false;
  final TextEditingController _messageController = TextEditingController();
  Map<String, bool> _isTyping = {};

  @override
  void initState() {
    super.initState();
    _loadSupportTickets();
    _checkActiveSessions();
  }

  Future<void> _loadSupportTickets() async {
    try {
      QuerySnapshot ticketSnapshot = await _firestore
          .collection('support_tickets')
          .orderBy('createdAt', descending: true)
          .get();

      _supportTickets = await Future.wait(ticketSnapshot.docs.map((doc) async {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        DocumentSnapshot userDoc =
            await _firestore.collection('users').doc(data['userId']).get();

        return {
          'id': doc.id,
          'userId': data['userId'],
          'status': data['status'],
          'createdAt': data['createdAt'],
          'messages': data['messages'] ?? [],
          'username': (userDoc.data() as Map<String, dynamic>?)?['username'] ??
              'Bilinmeyen Kullanıcı',
        };
      }).toList());

      setState(() => _isLoading = false);
    } catch (e) {
      print('Destek talepleri yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkActiveSessions() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final activeTickets = await _firestore
          .collection('support_tickets')
          .where('currentAgent', isNull: true)
          .where('isLive', isEqualTo: true)
          .get();

      for (var doc in activeTickets.docs) {
        final data = doc.data();
        if (data['currentAgent'].toString().contains(currentUser.uid)) {
          setState(() => _isLiveChat = true);
          break;
        }
      }
    } catch (e) {
      print('Aktif oturum kontrolü hatası: $e');
    }
  }

  String _formatDate(int timestamp) {
    DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Destek Talepleri'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadSupportTickets,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: EdgeInsets.all(16),
              itemCount: _supportTickets.length,
              itemBuilder: (context, index) {
                final ticket = _supportTickets[index];
                return Card(
                  margin: EdgeInsets.only(bottom: 16),
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.all(16),
                    leading: CircleAvatar(
                      backgroundColor: Colors.teal.shade100,
                      child: Icon(Icons.support_agent, color: Colors.teal),
                    ),
                    title: Text(
                      ticket['username'],
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 8),
                        Text('Talep ID: ${ticket['id']}'),
                        SizedBox(height: 4),
                        Text(
                          'Tarih: ${_formatDate(ticket['createdAt'])}',
                        ),
                      ],
                    ),
                    trailing: Chip(
                      label: Text(
                        ticket['status'] == 'pending' ? 'Bekliyor' : 'İşlendi',
                        style: TextStyle(color: Colors.white),
                      ),
                      backgroundColor: ticket['status'] == 'pending'
                          ? Colors.orange
                          : Colors.green,
                    ),
                    onTap: () => _showTicketDetails(ticket),
                  ),
                );
              },
            ),
    );
  }

  void _showTicketDetails(Map<String, dynamic> ticket) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Destek Talebi Detayı',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_currentAgentName != null)
                        Text(
                          'Temsilci: $_currentAgentName',
                          style: TextStyle(
                            color: Colors.teal,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      if (ticket['status'] == 'pending')
                        ElevatedButton.icon(
                          icon: Icon(Icons.headset_mic),
                          label: Text('Görüşmeyi Başlat'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                          ),
                          onPressed: () async {
                            await _startLiveChat(ticket);
                            setState(() => _isLiveChat = true);
                          },
                        ),
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
              Divider(),
              Expanded(
                child: StreamBuilder<DocumentSnapshot>(
                  stream: _firestore
                      .collection('support_tickets')
                      .doc(ticket['id'])
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Center(child: CircularProgressIndicator());
                    }

                    final updatedTicket =
                        snapshot.data!.data() as Map<String, dynamic>;
                    final messages = updatedTicket['messages'] as List;

                    if (updatedTicket['typing'] != null) {
                      final typing =
                          updatedTicket['typing'] as Map<String, dynamic>;
                      if (typing.values.any((isTyping) => isTyping == true)) {
                        final whoIsTyping = typing.entries
                            .firstWhere((e) => e.value == true)
                            .key;
                        return Column(
                          children: [
                            ListView.builder(
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final message = messages[index];
                                return Container(
                                  margin: EdgeInsets.symmetric(vertical: 8),
                                  padding: EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: message['isUser']
                                        ? Colors.blue.shade50
                                        : message['isSystemMessage'] == true
                                            ? Colors.grey.shade200
                                            : Colors.teal.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            message['isUser']
                                                ? ticket['username']
                                                : message['isSystemMessage'] ==
                                                        true
                                                    ? 'Sistem'
                                                    : _currentAgentName ??
                                                        'Temsilci',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: message['isUser']
                                                  ? Colors.blue
                                                  : message['isSystemMessage'] ==
                                                          true
                                                      ? Colors.grey
                                                      : Colors.teal,
                                            ),
                                          ),
                                          Text(
                                            _formatDate(message['timestamp']),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 4),
                                      Text(message['text']),
                                    ],
                                  ),
                                );
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text(
                                '$whoIsTyping yazıyor...',
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                    }

                    return ListView.builder(
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        return Container(
                          margin: EdgeInsets.symmetric(vertical: 8),
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: message['isUser']
                                ? Colors.blue.shade50
                                : message['isSystemMessage'] == true
                                    ? Colors.grey.shade200
                                    : Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    message['isUser']
                                        ? ticket['username']
                                        : message['isSystemMessage'] == true
                                            ? 'Sistem'
                                            : _currentAgentName ?? 'Temsilci',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: message['isUser']
                                          ? Colors.blue
                                          : message['isSystemMessage'] == true
                                              ? Colors.grey
                                              : Colors.teal,
                                    ),
                                  ),
                                  Text(
                                    _formatDate(message['timestamp']),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 4),
                              Text(message['text']),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: _isLiveChat
                              ? 'Mesajınızı yazın...'
                              : 'Görüşmeyi başlatın...',
                          border: OutlineInputBorder(),
                        ),
                        enabled: _isLiveChat,
                        onSubmitted: (text) {
                          if (_isLiveChat) {
                            _sendMessage(ticket['id'], text);
                          }
                        },
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.send),
                      onPressed: _isLiveChat
                          ? () => _sendMessage(
                              ticket['id'], _messageController.text)
                          : null,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: ElevatedButton.icon(
                  icon: Icon(Icons.stop_circle),
                  label: Text('Sohbeti Sonlandır'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _endChat(ticket['id']),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startLiveChat(Map<String, dynamic> ticket) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      final userDoc =
          await _firestore.collection('users').doc(currentUser.uid).get();

      final username = (userDoc.data() as Map<String, dynamic>)['username'] ??
          'Bilinmeyen Temsilci';

      setState(() {
        _isLiveChat = true;
        _currentAgentName = "Temsilci $username";
      });

      Map<String, dynamic> systemMessage = {
        'text': "$_currentAgentName görüşmeye katıldı.",
        'isUser': false,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isSystemMessage': true,
        'agentName': _currentAgentName,
      };

      await _firestore.collection('support_tickets').doc(ticket['id']).update({
        'isLive': true,
        'currentAgent': _currentAgentName,
        'messages': FieldValue.arrayUnion([systemMessage]),
        'status': 'active',
      });

      Navigator.pop(context);
      _showTicketDetails(ticket);
    } catch (e) {
      print('Canlı görüşme başlatma hatası: $e');
    }
  }

  Future<void> _sendMessage(String ticketId, String message) async {
    if (message.trim().isEmpty) return;
    _messageController.clear();

    await _firestore.collection('support_tickets').doc(ticketId).update({
      'typing': {_currentAgentName ?? 'Temsilci': true}
    });

    try {
      await _firestore.collection('support_tickets').doc(ticketId).update({
        'messages': FieldValue.arrayUnion([
          {
            'text': message,
            'isUser': false,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'isSystemMessage': false,
            'agentName': _currentAgentName,
          }
        ]),
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        'typing': {_currentAgentName ?? 'Temsilci': false}
      });
    } catch (e) {
      print('Mesaj gönderme hatası: $e');
    }
  }

  Future<void> _endChat(String ticketId) async {
    try {
      Map<String, dynamic> systemMessage = {
        'text': "$_currentAgentName görüşmeyi sonlandırdı.",
        'isUser': false,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isSystemMessage': true,
        'agentName': _currentAgentName,
      };

      await _firestore.collection('support_tickets').doc(ticketId).update({
        'isLive': false,
        'status': 'completed',
        'currentAgent': null,
        'messages': FieldValue.arrayUnion([systemMessage]),
        'typing': {},
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });

      Navigator.pop(context);

      setState(() {
        _isLiveChat = false;
        _currentAgentName = null;
      });
    } catch (e) {
      print('Sohbet sonlandırma hatası: $e');
    }
  }
}
