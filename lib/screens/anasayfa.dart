import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:myapp/chat/ChatListScreen.dart';
import 'package:myapp/screens/ispaylasmaprfili/job_post_card.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class JobPost {
  final String id;
  final String profileImage;
  final String jobTitle;
  final String jobDescription;
  final double budget;
  final String category;
  final int likes;
  final int comments;
  final List<Color> gradient;
  final String employerId; // New field to store the user who posted the job
  String? username; // Optional field to store the dynamically fetched username

  JobPost({
    required this.id,
    this.profileImage = 'https://randomuser.me/api/portraits/men/1.jpg',
    required this.jobTitle,
    required this.jobDescription,
    required this.budget,
    required this.category,
    required this.employerId, // Make this a required field
    this.likes = 0,
    this.comments = 0,
    this.gradient = const [Color(0xFF6A11CB), Color(0xFF2575FC)],
    this.username,
  });

  // Factory constructor to create a JobPost from Firestore document
  factory JobPost.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return JobPost(
      id: doc.id,
      jobTitle: data['jobName'] ?? '',
      jobDescription: data['jobDescription'] ?? '',
      budget: (data['jobPrice'] ?? 0).toDouble(),
      category: data['category'] ?? 'Diğer',
      profileImage: data['profileImage'] ??
          'https://randomuser.me/api/portraits/men/1.jpg',
      employerId: data['employerId'] ?? '', // Add employerId
      likes: data['likes'] ?? 0,
      comments: data['comments'] ?? 0,
    );
  }

  Future<void> fetchUsername() async {
    if (employerId.isEmpty) return;

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(employerId)
          .get();

      if (userDoc.exists) {
        username = userDoc['username'] ?? '';
      }
    } catch (e) {
      print('Error fetching username: $e');
      username = '';
    }
  }

  // Method to convert JobPost to a map for Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'jobName': jobTitle,
      'jobDescription': jobDescription,
      'jobPrice': budget,
      'category': category,
      'profileImage': profileImage,
      'employerId': employerId, // Include employerId when saving
      'likes': likes,
      'comments': comments,
    };
  }
}

class InstagramStyleJobListing extends StatefulWidget {
  const InstagramStyleJobListing({super.key});

  @override
  _InstagramStyleJobListingState createState() =>
      _InstagramStyleJobListingState();
}

class _InstagramStyleJobListingState extends State<InstagramStyleJobListing> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<JobPost> _jobPosts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCachedPosts(); // Önce önbellekten yükle
    _fetchJobPosts(); // Sonra güncel verileri getir
    _initOneSignal();
  }

  // Önbellekten iş ilanlarını yükle
  Future<void> _loadCachedPosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('cached_job_posts');

      if (cachedData != null) {
        final List<dynamic> decodedData = json.decode(cachedData);
        final List<JobPost> cachedPosts = decodedData.map((item) {
          return JobPost(
            id: item['id'],
            jobTitle: item['jobTitle'],
            jobDescription: item['jobDescription'],
            budget: item['budget'].toDouble(),
            category: item['category'],
            profileImage: item['profileImage'],
            employerId: item['employerId'],
            username: item['username'],
          );
        }).toList();

        if (mounted) {
          setState(() {
            _jobPosts = cachedPosts;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Önbellek yükleme hatası: $e');
    }
  }

  Future<void> _fetchJobPosts() async {
    try {
      QuerySnapshot querySnapshot = await _firestore.collection('jobs').get();

      List<JobPost> jobPosts =
          querySnapshot.docs.map((doc) => JobPost.fromFirestore(doc)).toList();

      for (var jobPost in jobPosts) {
        await jobPost.fetchUsername();
      }

      // Verileri önbelleğe kaydet
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> serializedPosts = jobPosts
          .map((post) => {
                'id': post.id,
                'jobTitle': post.jobTitle,
                'jobDescription': post.jobDescription,
                'budget': post.budget,
                'category': post.category,
                'profileImage': post.profileImage,
                'employerId': post.employerId,
                'username': post.username,
              })
          .toList();

      await prefs.setString('cached_job_posts', json.encode(serializedPosts));

      if (mounted) {
        setState(() {
          _jobPosts = jobPosts;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('İş ilanları çekilirken hata: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Skeleton widget
  Widget _buildSkeletonItem() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profil ve kullanıcı adı skeleton
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 100,
                  height: 12,
                  color: Colors.grey[300],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // İş başlığı skeleton
            Container(
              width: double.infinity,
              height: 16,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 8),
            // İş açıklaması skeleton
            Container(
              width: double.infinity,
              height: 60,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            // Fiyat ve kategori skeleton
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 80,
                  height: 12,
                  color: Colors.grey[300],
                ),
                Container(
                  width: 60,
                  height: 12,
                  color: Colors.grey[300],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _initOneSignal() async {
    try {
      print('OneSignal başlatılıyor...');
      OneSignal.initialize('10eef095-d1ee-4c36-a53d-454b1f5d6746');

      print('Bildirim izni isteniyor...');
      final permissionResult =
          await OneSignal.Notifications.requestPermission(true);
      print(
          'Bildirim izni durumu: ${permissionResult ? "İzin Verildi ✅" : "İzin Reddedildi ❌"}');

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
          print('Bildirim sistemi hazır ✅ - Artık bildirim alabilirsiniz!');
        }
      } else {
        print('Player ID alınamadı ❌ - Bildirim sistemi çalışmayabilir!');
      }

      // SharedPreferences'ı güncelle
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('allNotifications', permissionResult);
    } catch (e) {
      print('OneSignal başlatma hatası ❌: $e');
      print('Hata detayı: ${e.toString()}');
      print('Bildirim sistemi aktifleştirilemedi ❌');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'İş Platformu',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble, color: Colors.black, size: 30),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ChatListScreen()),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? ListView.builder(
              itemCount: 5, // Skeleton sayısı
              itemBuilder: (context, index) => _buildSkeletonItem(),
            )
          : AnimationLimiter(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                itemCount: _jobPosts.length,
                itemBuilder: (BuildContext context, int index) {
                  final job = _jobPosts[index];
                  return AnimationConfiguration.staggeredList(
                    position: index,
                    duration: const Duration(milliseconds: 750),
                    child: SlideAnimation(
                      verticalOffset: 100.0,
                      child: FadeInAnimation(
                        child: JobPostCard(job: job),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
