import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:myapp/chat/chatpage.dart';
import 'package:myapp/model/user_model.dart';
import 'package:myapp/screens/anasayfa.dart';
import 'package:myapp/screens/ispaylasmaprfili/applicants_page.dart';
import 'package:myapp/screens/ispaylasmaprfili/job_profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class JobPostCard extends StatefulWidget {
  final JobPost job;
  final bool isDetailPage;
  final Function(String jobId)? onApplicationChanged;

  const JobPostCard(
      {super.key,
      required this.job,
      this.isDetailPage = false,
      this.onApplicationChanged});

  @override
  _JobPostCardState createState() => _JobPostCardState();
}

class _JobPostCardState extends State<JobPostCard> {
  bool _isApplied = false;
  int _applicantsCount = 0;
  String? otherUserName;
  String? otherUserProfileImageUrl;
  String? _messageId;
  String? _jobCardMessageId;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadCachedApplicationStatus();
    _checkApplicationStatus();
    _fetchOtherUserInfo();
    if (widget.isDetailPage) {
      _fetchApplicantsCount();
    }
  }

  Future<void> _loadCachedApplicationStatus() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final prefs = await SharedPreferences.getInstance();
      final key = 'job_application_${widget.job.id}_${currentUser.uid}';

      if (mounted) {
        setState(() {
          _isApplied = prefs.getBool(key) ?? false;
        });
      }
    } catch (e) {
      print('Önbellek yükleme hatası: $e');
    }
  }

  Future<void> _checkApplicationStatus() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final applicationSnapshot = await FirebaseFirestore.instance
          .collection('job_applications')
          .where('jobId', isEqualTo: widget.job.id)
          .where('applicantId', isEqualTo: currentUser.uid)
          .get();

      final isApplied = applicationSnapshot.docs.isNotEmpty;

      final prefs = await SharedPreferences.getInstance();
      final key = 'job_application_${widget.job.id}_${currentUser.uid}';
      await prefs.setBool(key, isApplied);

      if (mounted) {
        setState(() {
          _isApplied = isApplied;
        });
      }
    } catch (e) {
      print('Başvuru durumu kontrol hatası: $e');
    }
  }

  Future<void> _fetchOtherUserInfo() async {
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.job.employerId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        otherUserName = userData['username'];
        otherUserProfileImageUrl = userData['profileImageUrl'];
      }
    } catch (e) {
      print('Error fetching user info: $e');
    }
  }

  Future<void> _fetchApplicantsCount() async {
    try {
      final applicantsSnapshot = await FirebaseFirestore.instance
          .collection('job_applications')
          .where('jobId', isEqualTo: widget.job.id)
          .get();

      setState(() {
        _applicantsCount = applicantsSnapshot.docs.length;
      });
    } catch (e) {
      print('Error fetching applicants count: $e');
    }
  }

  void _viewApplicants() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ApplicantsPage(jobId: widget.job.id),
      ),
    );
  }

  Future<void> _toggleJobApplication() async {
    if (_isProcessing) return;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      if (_isApplied) {
        // Remove application
        final querySnapshot = await FirebaseFirestore.instance
            .collection('job_applications')
            .where('jobId', isEqualTo: widget.job.id)
            .where('applicantId', isEqualTo: currentUser.uid)
            .get();

        for (var doc in querySnapshot.docs) {
          await doc.reference.delete();
        }

        // Önbelleği güncelle - başvuru kaldırıldı
        final prefs = await SharedPreferences.getInstance();
        final key = 'job_application_${widget.job.id}_${currentUser.uid}';
        await prefs.setBool(key, false); // false olarak güncelle

        await _deleteAutomaticMessage();

        setState(() {
          _isApplied = false; // State'i güncelle
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('İş başvurunuz geri çekildi')),
        );
      } else {
        // Add application
        await FirebaseFirestore.instance.collection('job_applications').add({
          'jobId': widget.job.id,
          'applicantId': currentUser.uid,
          'applicationDate': FieldValue.serverTimestamp(),
          'jobTitle': widget.job.jobTitle,
          'employerId': widget.job.employerId,
        });

        // Önbelleği güncelle - başvuru eklendi
        final prefs = await SharedPreferences.getInstance();
        final key = 'job_application_${widget.job.id}_${currentUser.uid}';
        await prefs.setBool(key, true); // true olarak güncelle

        setState(() {
          _isApplied = true; // State'i güncelle
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('İş başvurunuz alındı')),
        );

        // Otomatik mesaj gönderme
        await _sendAutomaticMessage(currentUser.uid);
      }

      // Update application status and recount applicants
      if (widget.onApplicationChanged != null) {
        widget.onApplicationChanged!(widget.job.id);
      }
    } catch (e) {
      print('İşlem hatası: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _sendAutomaticMessage(String applicantId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      // Kullanıcı adını Firestore'dan çekme
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      String senderName = 'Kullanıcı'; // Varsayılan isim
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        senderName = userData['username'] ?? 'Kullanıcı';
      }

      final message = {
        'jobTitle': widget.job.jobTitle,
        'jobDescription': widget.job.jobDescription,
        'username': widget.job.username,
        'profileImage': widget.job.profileImage,
        'budget': widget.job.budget,
        'likes': widget.job.likes,
        'comments': widget.job.comments,
        'gradient': widget.job.gradient.map((color) => color.value).toList(),
        'employerApproved': false,
        'applicantApproved': false,
      };

      final automaticMessage =
          'Merhaba, Ben $senderName. Paylaştığınız ${widget.job.jobTitle} işi hakkında daha detaylı bilgi alabilir miyim?';

      final chatDocRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(generateChatId(currentUser.uid, widget.job.employerId));
      final chatDoc = await chatDocRef.get();
      if (!chatDoc.exists) {
        await chatDocRef.set({
          'users': [currentUser.uid, widget.job.employerId]
        });
      }
      final messageDoc = await chatDocRef.collection('messages').add({
        'senderId': applicantId,
        'senderName': senderName,
        'type': 'automatic_message',
        'text': automaticMessage,
        'timestamp': FieldValue.serverTimestamp(),
      });
      final jobCardMessageDoc = await chatDocRef.collection('messages').add({
        'senderId': applicantId,
        'senderName': senderName,
        'type': 'job_card',
        'text': message,
        'timestamp': FieldValue.serverTimestamp(),
        'employerApproved': false,
        'applicantApproved': false,
      });
      setState(() {
        _messageId = messageDoc.id;
        _jobCardMessageId = jobCardMessageDoc.id;
      });
      print('Mesaj başarıyla gönderildi');
    } catch (e) {
      print('Otomatik mesaj gönderilirken hata oluştu: $e');
    }
  }

  Future<void> _deleteAutomaticMessage() async {
    try {
      final chatDocRef = FirebaseFirestore.instance.collection('chats').doc(
          generateChatId(
              FirebaseAuth.instance.currentUser!.uid, widget.job.employerId));
      if (_messageId != null) {
        await chatDocRef.collection('messages').doc(_messageId).delete();
      }
      if (_jobCardMessageId != null) {
        await chatDocRef.collection('messages').doc(_jobCardMessageId).delete();
      }

      print('Mesaj başarıyla silindi');
    } catch (e) {
      print('Mesaj silinirken hata oluştu: $e');
    }
    setState(() {
      _messageId = null;
      _jobCardMessageId = null;
    });
  }

  String generateChatId(String user1, String user2) {
    List<String> ids = [user1, user2];
    ids.sort(); // Listeyi alfabetik olarak sıralar
    return '${ids[0]}_${ids[1]}';
  }

  void _handleProfileTap() async {
    // Eğer kendi ilanımızsa profil sayfasına gitme
    if (FirebaseAuth.instance.currentUser?.uid == widget.job.employerId) {
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.job.employerId)
          .get();

      if (!userDoc.exists || !context.mounted) return;

      final userData = UserModel.fromFirestore(userDoc);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => JobProfilePage(user: userData),
        ),
      );
    } catch (e) {
      print('Profil sayfasına giderken hata: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isJobOwner =
        currentUser != null && currentUser.uid == widget.job.employerId;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: widget.job.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            offset: Offset(0, 8),
            blurRadius: 15,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.isDetailPage)
              Align(
                alignment: Alignment.topRight,
                child: isJobOwner
                    ? GestureDetector(
                        onTap: _viewApplicants,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.people,
                                  color: Colors.white, size: 16),
                              const SizedBox(width: 5),
                              Text(
                                '$_applicantsCount Başvuru',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            Row(
              children: [
                GestureDetector(
                  onTap: _handleProfileTap,
                  child: CircleAvatar(
                    backgroundImage: NetworkImage(widget.job.profileImage),
                    radius: 30,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 15),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => JobProfilePage(
                            user: UserModel(
                          uid: widget.job.employerId,
                          username: widget.job.username ?? 'Unknown User',
                          profileImageUrl: widget.job.profileImage,
                        )),
                      ),
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.job.username ?? 'Unknown User',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        widget.job.category,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              widget.job.jobTitle,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.job.jobDescription,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '₺${widget.job.budget.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.favorite_border, color: Colors.white),
                    const SizedBox(width: 5),
                    Text('${widget.job.likes}',
                        style: const TextStyle(color: Colors.white)),
                    const SizedBox(width: 15),
                    const Icon(Icons.comment_outlined, color: Colors.white),
                    const SizedBox(width: 5),
                    Text('${widget.job.comments}',
                        style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (!isJobOwner)
              Row(
                children: [
                  Expanded(
                    child: FirebaseAuth.instance.currentUser != null
                        ? ElevatedButton(
                            onPressed:
                                _isProcessing ? null : _toggleJobApplication,
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor:
                                  _isApplied ? Colors.red : Colors.blue,
                              minimumSize: const Size(double.infinity, 45),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(_isProcessing
                                ? 'İşleniyor...'
                                : (_isApplied
                                    ? 'Başvuruyu Geri Çek'
                                    : 'Başvur')),
                          )
                        : ElevatedButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Lütfen Giriş Yapınız'),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors
                                  .grey, // or some other color that indicates disabled state
                              minimumSize: const Size(double.infinity, 45),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text('Başvur',
                                style: TextStyle(color: Colors.white)),
                          ),
                  ),
                  const SizedBox(width: 10),
                  if (_isApplied)
                    SizedBox(
                        width: 40,
                        height: 37,
                        child: FirebaseAuth.instance.currentUser != null
                            ? IconButton(
                                onPressed: () async {
                                  final currentUser =
                                      FirebaseAuth.instance.currentUser;
                                  if (currentUser == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content:
                                              Text('Lütfen önce giriş yapın')),
                                    );
                                    return;
                                  }

                                  if (currentUser.uid ==
                                      widget.job.employerId) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Kendi ilanınıza mesaj gönderemezsiniz')),
                                    );
                                    return;
                                  }

                                  // Firestore'dan mesajı göndereceğimiz kullanıcının verilerini alıyoruz
                                  DocumentSnapshot userDoc =
                                      await FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(widget.job.employerId)
                                          .get();

                                  if (userDoc.exists) {
                                    final userData =
                                        userDoc.data() as Map<String, dynamic>;
                                    final otherUserName = userData['username'];
                                    final currentUserProfileImageUrl =
                                        currentUser.photoURL ?? '';
                                    // Chat sayfasına yönlendirme
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ChatPage(
                                          otherUserId: widget.job.employerId,
                                          otherUserName: otherUserName,
                                          otherUserProfileImageUrl: '',
                                        ),
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Kullanıcı bilgileri alınamadı')),
                                    );
                                    return;
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const Icon(Icons.chat),
                              )
                            : IconButton(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Lütfen Giriş Yapınız'),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: Colors.grey,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: const Icon(Icons.chat),
                              )),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
