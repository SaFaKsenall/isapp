import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';

// Import your models
import 'package:myapp/model/user_model.dart';
import 'package:myapp/model/job_and_rivevws.dart';

class ReviewsPage extends StatefulWidget {
  final UserModel user;

  const ReviewsPage({super.key, required this.user});

  @override
  _ReviewsPageState createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage> {
  List<Review> _reviews = [];
  double _averageRating = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchReviews();
  }

  Future<void> _fetchReviews() async {
    try {
      QuerySnapshot reviewSnapshot = await FirebaseFirestore.instance
          .collection('reviews')
          .where('employerId', isEqualTo: widget.user.uid)
          .get();

      // Fetch reviewer details for each review
      List<Review> fetchedReviews = [];
      for (var doc in reviewSnapshot.docs) {
        var reviewData = doc.data() as Map<String, dynamic>;
        
        // Fetch reviewer username
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(reviewData['reviewerId'])
            .get();
        
        var reviewWithUsername = {
          ...reviewData,
          'reviewerUsername': userDoc.exists ? userDoc['username'] : 'Anonim Kullanıcı'
        };

        fetchedReviews.add(Review.fromMap(reviewWithUsername));
      }

      setState(() {
        _reviews = fetchedReviews;
        _calculateAverageRating();
      });
    } catch (e) {
      print('Reviews fetch error: $e');
    }
  }

  void _addReview() async {
    // Prevent self-review
    if (FirebaseAuth.instance.currentUser!.uid == widget.user.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kendi profilinize değerlendirme ekleyemezsiniz')),
      );
      return;
    }

    // Check if the current user has already reviewed this profile
    try {
      QuerySnapshot existingReviewSnapshot = await FirebaseFirestore.instance
          .collection('reviews')
          .where('employerId', isEqualTo: widget.user.uid)
          .where('reviewerId', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .get();

      if (existingReviewSnapshot.docs.isNotEmpty) {
        // User has already submitted a review
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu kullanıcıya zaten değerlendirme yaptınız')),
        );
        return;
      }

      // If no existing review, show the review bottom sheet
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          double rating = 0;
          final reviewController = TextEditingController();

          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setModalState) {
              return Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'İş Değerlendirmesi',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    RatingBar.builder(
                      initialRating: 0,
                      minRating: 1,
                      direction: Axis.horizontal,
                      allowHalfRating: true,
                      itemCount: 5,
                      itemPadding: const EdgeInsets.symmetric(horizontal: 4.0),
                      itemBuilder: (context, _) => const Icon(
                        Icons.star,
                        color: Colors.amber,
                      ),
                      onRatingUpdate: (rating) {
                        setModalState(() {
                          rating = rating;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: reviewController,
                      decoration: const InputDecoration(
                        labelText: 'Yorumunuz',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () async {
                        try {
                          // Add review to Firestore
                          await FirebaseFirestore.instance.collection('reviews').add(
                            Review(
                              employerId: widget.user.uid,
                              reviewerId: FirebaseAuth.instance.currentUser!.uid,
                              rating: rating,
                              comment: reviewController.text,
                            ).toMap(),
                          );

                          // Refresh reviews
                          _fetchReviews();

                          // Close bottom sheet
                          Navigator.pop(context);

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Değerlendirme başarıyla eklendi')),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Değerlendirme eklenirken hata oluştu: $e')),
                          );
                        }
                      },
                      child: const Text('Değerlendirmeyi Kaydet'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bir hata oluştu: $e')),
      );
    }
  }

  void _calculateAverageRating() {
    if (_reviews.isNotEmpty) {
      _averageRating = _reviews.map((r) => r.rating).reduce((a, b) => a + b) / _reviews.length;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Değerlendirmeler'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 60,
                backgroundImage: widget.user.profileImageUrl != null
                    ? NetworkImage(widget.user.profileImageUrl!)
                    : null,
                child: widget.user.profileImageUrl == null 
                  ? const Icon(Icons.person, size: 60): null,
              ),
              const SizedBox(height: 10),
              Text(
                widget.user.username,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, color: Colors.amber),
                  Text(
                    ' ${_averageRating.toStringAsFixed(1)} (${_reviews.length} Değerlendirme)',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              // Kendi profiline bakmıyorsa "Değerlendir" butonu göster
              if (FirebaseAuth.instance.currentUser!.uid != widget.user.uid)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _addReview,
                      icon: const Icon(Icons.rate_review),
                      label: const Text('Değerlendir'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                      ),
                    ),
                  ],
                ),
              
              const SizedBox(height: 20),
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Değerlendirmeler',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Tüm kullanıcılar için değerlendirmeleri göster
                      _reviews.isEmpty
                          ? const Center(child: Text('Henüz değerlendirme yok'))
                          : ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _reviews.length,
                              itemBuilder: (context, index) {
                                Review review = _reviews[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 8),
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.person_outline,
                                      color: Colors.blue,
                                    ),
                                    title: Row(
                                      children: [
                                        Text(
                                          review.reviewerUsername ?? 'Anonim Kullanıcı',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        ...List.generate(
                                          review.rating.toInt(), 
                                          (index) => const Icon(Icons.star, color: Colors.amber, size: 16)
                                        ),
                                      ],
                                    ),
                                    subtitle: Text(
                                      review.comment,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}