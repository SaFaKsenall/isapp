import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:myapp/chat/ChatListScreen.dart';
import 'package:myapp/screens/ispaylasmaprfili/job_post_card.dart';

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
      profileImage: data['profileImage'] ?? 'https://randomuser.me/api/portraits/men/1.jpg',
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
    _fetchJobPosts();
  }

  Future<void> _fetchJobPosts() async {
    try {
      QuerySnapshot querySnapshot = await _firestore.collection('jobs').get();
      
      List<JobPost> jobPosts = querySnapshot.docs
          .map((doc) => JobPost.fromFirestore(doc))
          .toList();

      // Her iş ilanı için kullanıcı adlarını çek
      for (var jobPost in jobPosts) {
        await jobPost.fetchUsername();
      }

      setState(() {
        _jobPosts = jobPosts;
        _isLoading = false;
      });
    } catch (e) {
      print('İş ilanları çekilirken hata: $e');
      setState(() {
        _isLoading = false;
      });
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
                MaterialPageRoute(builder: (context) =>  ChatListScreen()),
              );
            },
          ),
        
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : AnimationLimiter(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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