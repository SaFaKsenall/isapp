import 'package:flutter/material.dart';
import 'dart:async';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class YardimDestekPage extends StatefulWidget {
  @override
  _YardimDestekPageState createState() => _YardimDestekPageState();
}

class _YardimDestekPageState extends State<YardimDestekPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _showSupportButton = false;
  final List<String> _triggerWords = [
    'hata',
    'sorun',
    'problem',
    'müşteri hizmetleri',
    'yardım',
    'destek',
    'çalışmıyor',
    'bağlanamıyorum',
    'müşteri',
    'temsilci',
  ];

  // Gemini API anahtarınızı buraya ekleyin
  final model = GenerativeModel(
    model: 'gemini-pro',
    apiKey: 'AIzaSyCCTvjdNRfYB_LGEj019i8jrO2hwbBvTrY',
  );

  late ChatSession chat;
  bool _isConnectedToAgent = false; // Temsilci bağlantı durumu
  String? _currentTicketId; // Aktif destek talebi ID'si
  StreamSubscription? _ticketSubscription; // Firestore stream subscription
  String? _currentAgentName;

  @override
  void initState() {
    super.initState();
    chat = model.startChat(history: [
      Content.text('''Sen bir yardım destek asistanısın. Adın TurSaf Asistan. 
      TurSaf uygulaması hakkında detaylı bilgi veriyorsun.
      
      TurSaf Uygulaması Hakkında Detaylı Bilgiler:
      
      İş İlanları ve Başvurular:
      - İş verenler detaylı iş ilanları oluşturabilir (pozisyon, maaş, lokasyon, gereksinimler)
      - İş arayanlar filtreleme yaparak kendilerine uygun ilanları bulabilir
      - Tek tıkla hızlı başvuru yapılabilir
      - Başvuru durumu anlık olarak takip edilebilir
      
      Profil Yönetimi:
      - Detaylı CV oluşturma imkanı
      - Eğitim ve iş deneyimi bilgileri
      - Yetenek ve sertifika ekleme
      - Referans ve portföy bölümleri
      - Profil görünürlük ayarları
      
      Mesajlaşma Özellikleri:
      - İş verenlerle anlık mesajlaşma
      - Görüntülü görüşme imkanı
      - Dosya ve belge paylaşımı
      - Otomatik bildirimler
      
      Bildirim Sistemi:
      - Yeni iş ilanı bildirimleri
      - Başvuru durum güncellemeleri
      - Mesaj bildirimleri
      - Görüşme hatırlatmaları
      
      Ek Özellikler:
      - Maaş hesaplama aracı
      - Kariyer tavsiyeleri
      - Sektör analizleri
      - Online eğitimler
      
      Yanıtlama Kuralları:
      1. Her zaman nazik ve profesyonel ol
      2. Bilgileri net ve anlaşılır şekilde aktar
      3. Uygulama dışı konularda: "Bu konu uygulama kapsamı dışındadır. Uygulama hakkında başka nasıl yardımcı olabilirim?" şeklinde yanıt ver
      4. Kullanıcıyı doğru yönlendir ve gerektiğinde ek bilgi iste
      5. Teknik sorunlarda müşteri hizmetlerine yönlendir
      6. Müşteri temsilcisine bağlanmak istiyorsan yardım yazabilirisin diyerek yanıt ver
      ''')
    ]);

    _addBotMessage(
        "Merhaba! Ben TurSaf Asistan. Size TurSaf uygulaması hakkında detaylı bilgi verebilirim. Hangi konuda yardımcı olabilirim?");
  }

  void _addBotMessage(String message) {
    setState(() {
      _messages.add(ChatMessage(
        text: message,
        isUser: false,
      ));
    });
    _scrollToBottom();
  }

  void _addUserMessage(String message) {
    setState(() {
      _messages.add(ChatMessage(
        text: message,
        isUser: true,
      ));
    });
    _scrollToBottom();
  }

  Future<void> _handleSubmit(String text) async {
    if (text.trim().isEmpty) return;

    _messageController.clear();
    _addUserMessage(text);

    if (_isConnectedToAgent && _currentTicketId != null) {
      // Temsilciye bağlıysa, mesajı Firestore'a gönder
      try {
        await FirebaseFirestore.instance
            .collection('support_tickets')
            .doc(_currentTicketId)
            .update({
          'messages': FieldValue.arrayUnion([
            {
              'text': text,
              'isUser': true,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'isSystemMessage': false,
            }
          ]),
          'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        });
      } catch (e) {
        print('Mesaj gönderme hatası: $e');
        _addBotMessage("Mesaj gönderilemedi. Lütfen tekrar deneyin.");
      }
    } else {
      // Yapay zeka ile devam et
      // Trigger kelimeleri kontrol et
      bool shouldShowSupport = _triggerWords.any(
        (word) => text.toLowerCase().contains(word.toLowerCase()),
      );

      setState(() {
        _isTyping = true;
        _showSupportButton = shouldShowSupport;
      });

      try {
        final response = await chat.sendMessage(Content.text(text));
        final botResponse = response.text ?? 'Üzgünüm, bir hata oluştu.';

        setState(() {
          _isTyping = false;
        });

        _simulateTyping(botResponse);
      } catch (e) {
        print('Yapay zeka hatası: $e');
        setState(() {
          _isTyping = false;
        });
        _addBotMessage('Üzgünüm, bir hata oluştu. Lütfen tekrar deneyin.');
      }
    }
  }

  void _simulateTyping(String message) {
    const int typingSpeed = 30; // Milisaniye cinsinden yazma hızı
    const int maxChunkSize = 3; // Her seferde eklenecek maksimum kelime sayısı

    List<String> words = message.split(' ');
    String currentText = '';

    Timer.periodic(Duration(milliseconds: typingSpeed), (timer) {
      if (words.isEmpty) {
        timer.cancel();
        setState(() {
          if (_messages.last.isUser) {
            _messages.add(ChatMessage(text: message, isUser: false));
          } else {
            _messages.last.text = message;
          }
        });
        return;
      }

      // Rastgele 1-3 kelime ekle
      int chunkSize =
          1 + Random().nextInt(maxChunkSize).clamp(0, words.length - 1);
      List<String> chunk = words.take(chunkSize).toList();
      words.removeRange(0, chunkSize);

      currentText += chunk.join(' ') + ' ';

      setState(() {
        if (_messages.last.isUser) {
          _messages.add(ChatMessage(text: currentText.trim(), isUser: false));
        } else {
          _messages.last.text = currentText.trim();
        }
      });

      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Yardım & Destek'),
            if (_currentAgentName != null)
              Text(
                _currentAgentName!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue[800]!, Colors.blue[600]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.grey[100]!, Colors.grey[200]!],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return _buildMessage(_messages[index]);
                },
              ),
            ),
            if (_isTyping)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[100],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          _buildDot(0),
                          SizedBox(width: 4),
                          _buildDot(1),
                          SizedBox(width: 4),
                          _buildDot(2),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            _buildMessageInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 600),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, sin(value * 3.14 * 2 + index) * 4),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.blue[800],
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessage(ChatMessage message) {
    return Column(
      crossAxisAlignment:
          message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Align(
          alignment:
              message.isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: EdgeInsets.symmetric(vertical: 4),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: message.isUser ? Colors.blue[600] : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75),
            child: Text(
              message.text,
              style: TextStyle(
                color: message.isUser ? Colors.white : Colors.black87,
                fontSize: 16,
              ),
            ),
          ),
        ),
        if (!message.isUser &&
            _messages.last == message &&
            _showSupportButton &&
            !_isConnectedToAgent) ...[
          SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () => _connectToSupport(),
            icon: Icon(Icons.support_agent),
            label: Text('Müşteri Temsilcisine Bağlan'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Mesajınızı yazın...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onSubmitted: _handleSubmit,
            ),
          ),
          SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue[600]!, Colors.blue[800]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.send_rounded, color: Colors.white),
              onPressed: () => _handleSubmit(_messageController.text),
            ),
          ),
        ],
      ),
    );
  }

  void _connectToSupport() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        _addBotMessage("Oturum açmanız gerekiyor. Lütfen giriş yapın.");
        return;
      }

      setState(() => _isTyping = true);

      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();

        if (!userDoc.exists) {
          throw Exception('Kullanıcı profili bulunamadı');
        }

        // Destek talebi oluştur
        DocumentReference supportRef =
            await FirebaseFirestore.instance.collection('support_tickets').add({
          'userId': currentUser.uid,
          'userEmail': currentUser.email,
          'username': userDoc.data()?['username'] ?? 'İsimsiz Kullanıcı',
          'status': 'pending',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'lastUpdated': DateTime.now().millisecondsSinceEpoch,
          'messages': [
            {
              'text': "Müşteri temsilcisi bekleniyor...",
              'isUser': false,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'isSystemMessage': true,
            }
          ],
          'isLive': false,
          'currentAgent': null,
        });

        // Ticket ID'sini kaydet ve stream'i başlat
        _currentTicketId = supportRef.id;
        _startListeningToTicket(supportRef.id);

        // Mevcut sohbeti temizle
        setState(() {
          _messages.clear();
          _isConnectedToAgent = true;
          _showSupportButton = false;
          _addBotMessage("Müşteri temsilcisi bekleniyor...");
          _addBotMessage("Destek Talep Numaranız: ${supportRef.id}");
        });
      } catch (e) {
        print('Firestore işlem hatası: $e');
        _addBotMessage("Bağlantı hatası oluştu: ${e.toString()}");
      }
    } catch (e) {
      print('Genel hata: $e');
      _addBotMessage(
          "Beklenmeyen bir hata oluştu. Lütfen daha sonra tekrar deneyin.");
    } finally {
      setState(() => _isTyping = false);
    }
  }

  void _startListeningToTicket(String ticketId) {
    _ticketSubscription?.cancel();
    _ticketSubscription = FirebaseFirestore.instance
        .collection('support_tickets')
        .doc(ticketId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) return;

      final ticketData = snapshot.data() as Map<String, dynamic>;
      final messages = ticketData['messages'] as List;
      final isLive = ticketData['isLive'] ?? false;
      final currentAgent = ticketData['currentAgent'];
      final status = ticketData['status'] as String?; // Status kontrolü ekle

      // Önceki bağlantı durumunu kontrol et
      bool wasConnected = _isConnectedToAgent;

      setState(() {
        _messages.clear();
        _currentAgentName = currentAgent;
        _isConnectedToAgent = isLive && currentAgent != null;

        // Görüşme sonlandırıldıysa
        if (status == 'completed' && !isLive) {
          _isConnectedToAgent = false;
          _currentTicketId = null;
          _showSupportButton = false;

          // Yapay zekayı yeniden başlat
          chat = model.startChat(history: [
            Content.text(
                '''Sen bir yardım destek asistanısın. Adın TurSaf Asistan. 
            TurSaf uygulaması hakkında detaylı bilgi veriyorsun.
            
            TurSaf Uygulaması Hakkında Detaylı Bilgiler:
            
            İş İlanları ve Başvurular:
            - İş verenler detaylı iş ilanları oluşturabilir (pozisyon, maaş, lokasyon, gereksinimler)
            - İş arayanlar filtreleme yaparak kendilerine uygun ilanları bulabilir
            - Tek tıkla hızlı başvuru yapılabilir
            - Başvuru durumu anlık olarak takip edilebilir
            
            Profil Yönetimi:
            - Detaylı CV oluşturma imkanı
            - Eğitim ve iş deneyimi bilgileri
            - Yetenek ve sertifika ekleme
            - Referans ve portföy bölümleri
            - Profil görünürlük ayarları
            
            Mesajlaşma Özellikleri:
            - İş verenlerle anlık mesajlaşma
            - Görüntülü görüşme imkanı
            - Dosya ve belge paylaşımı
            - Otomatik bildirimler
            
            Bildirim Sistemi:
            - Yeni iş ilanı bildirimleri
            - Başvuru durum güncellemeleri
            - Mesaj bildirimleri
            - Görüşme hatırlatmaları
            
            Ek Özellikler:
            - Maaş hesaplama aracı
            - Kariyer tavsiyeleri
            - Sektör analizleri
            - Online eğitimler
            
            Yanıtlama Kuralları:
            1. Her zaman nazik ve profesyonel ol
            2. Bilgileri net ve anlaşılır şekilde aktar
            3. Uygulama dışı konularda: "Bu konu uygulama kapsamı dışındadır. Uygulama hakkında başka nasıl yardımcı olabilirim?" şeklinde yanıt ver
            4. Kullanıcıyı doğru yönlendir ve gerektiğinde ek bilgi iste
            5. Teknik sorunlarda müşteri hizmetlerine yönlendir. Müşteri temsilcisene bağlanmak istiyorsan yardım yazabilirisin diyerek yanıt ver
            6. Müşteri temsilcisene bağlanmak istiyorsan yardım yazabilirisin diyerek yanıt ver
            ''')
          ]);

          _addBotMessage(
              "Görüşme sonlandırıldı. Yapay Zeka Olarak Size nasıl yardımcı olabilirim?");
          return;
        }

        // Normal akış devam etsin
        if (!wasConnected && _isConnectedToAgent) {
          _messages.add(ChatMessage(
            text: "$currentAgent bağlandı",
            isUser: false,
          ));
        } else if (!_isConnectedToAgent) {
          _messages.add(ChatMessage(
            text: "Müşteri temsilcisi bekleniyor...",
            isUser: false,
          ));
          _messages.add(ChatMessage(
            text: "Destek Talep Numaranız: $ticketId",
            isUser: false,
          ));
        }

        // Mesajları ekle
        for (var msg in messages) {
          if (msg['isSystemMessage'] == true) continue;
          _messages.add(ChatMessage(
            text: msg['text'],
            isUser: msg['isUser'],
          ));
        }
      });
    });
  }

  @override
  void dispose() {
    _ticketSubscription?.cancel();
    super.dispose();
  }
}

class ChatMessage {
  String text;
  final bool isUser;

  ChatMessage({
    required this.text,
    required this.isUser,
  });
}
