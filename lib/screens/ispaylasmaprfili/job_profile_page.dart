import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myapp/qrscanner.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:geocoding/geocoding.dart';
import 'package:myapp/model/job_and_rivevws.dart';
import 'package:myapp/model/user_model.dart';
import 'package:myapp/screens/ispaylasmaprfili/drawer.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class JobProfilePage extends StatefulWidget {
  final UserModel user;

  const JobProfilePage({super.key, required this.user});

  @override
  _JobProfilePageState createState() => _JobProfilePageState();
}

class _JobProfilePageState extends State<JobProfilePage> {
  final _jobNameController = TextEditingController();
  final _jobDescriptionController = TextEditingController();
  final _jobPriceController = TextEditingController();
  final _categoryController = TextEditingController();
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final NetworkInfo _networkInfo = NetworkInfo();

  List<Job> _jobs = [];
  List<Review> _reviews = [];
  double _averageRating = 0.0;
  bool _shareLocation = false;
  bool _isLoading = true;
  List<String> _categories = [];
  List<String> _filteredCategories = [];
  bool _isCategoryListVisible = false;
  final FocusNode _categoryFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool isCurrentUser = false;
  late SharedPreferences _prefs;
  bool _hasLoadedCache = false;

  @override
  void initState() {
    super.initState();
    isCurrentUser = FirebaseAuth.instance.currentUser?.uid == widget.user.uid;
    _initializeData();
  }

  Future<void> _initializeData() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadCachedData();
    _fetchData();
  }

  Future<void> _loadCachedData() async {
    try {
      final cachedJobs = _prefs.getString('cached_jobs_${widget.user.uid}');
      if (cachedJobs != null) {
        final List<dynamic> jobsList = json.decode(cachedJobs);
        _jobs = jobsList.map((job) => Job.fromJson(job)).toList();
      }

      final cachedReviews =
          _prefs.getString('cached_reviews_${widget.user.uid}');
      if (cachedReviews != null) {
        final List<dynamic> reviewsList = json.decode(cachedReviews);
        _reviews =
            reviewsList.map((review) => Review.fromJson(review)).toList();
        _calculateAverageRating();
      }

      setState(() {
        _hasLoadedCache = true;
        _isLoading = false;
      });
    } catch (e) {
      print('Önbellek yükleme hatası: $e');
    }
  }

  Future<void> _fetchData() async {
    try {
      final jobs = await _fetchJobs();
      final reviews = await _fetchReviews();

      setState(() {
        if (jobs != null) _jobs = jobs;
        if (reviews != null) {
          _reviews = reviews;
          _calculateAverageRating();
        }
        _isLoading = false;
      });
    } catch (e) {
      print('Veri çekme hatası: $e');
    }
  }

  Future<List<Job>?> _fetchJobs() async {
    final jobSnapshot = await FirebaseFirestore.instance
        .collection('jobs')
        .where('employerId', isEqualTo: widget.user.uid)
        .get();

    return jobSnapshot.docs
        .map((doc) =>
            Job.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>))
        .toList();
  }

  Future<List<Review>?> _fetchReviews() async {
    final reviewSnapshot = await FirebaseFirestore.instance
        .collection('reviews')
        .where('employerId', isEqualTo: widget.user.uid)
        .get();

    return reviewSnapshot.docs
        .map((doc) => Review.fromMap(doc.data() as Map<String, dynamic>))
        .toList();
  }

  void _handleCategoryFocusChange() {
    if (!_categoryFocusNode.hasFocus) {
      setState(() {
        _isCategoryListVisible = false;
      });
    }
  }

  Future<void> _fetchCategories() async {
    try {
      setState(() {
        _isLoading = true;
      });

      QuerySnapshot categorySnapshot =
          await FirebaseFirestore.instance.collection('category').get();

      setState(() {
        _categories =
            categorySnapshot.docs.map((doc) => doc['name'] as String).toList();
        _filteredCategories = _categories;
      });
    } catch (e) {
      print('Kategori çekme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kategoriler yüklenirken hata oluştu')));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterCategories(String query) {
    setState(() {
      _filteredCategories = _categories
          .where((category) =>
              category.toLowerCase().contains(query.toLowerCase()))
          .take(3)
          .toList();
    });
  }

  Future<Map<String, dynamic>?> _getLocationForJob() async {
    try {
      setState(() {
        _isLoading = true;
      });

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Konum izni reddedildi');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Konum izni kalıcı olarak reddedildi');
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Konum servisleri kapalı');
      }

      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.reduced,
          timeLimit: const Duration(seconds: 10),
        );

        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        String neighborhood = 'Bilinmeyen Mahalle';
        if (placemarks.isNotEmpty) {
          neighborhood = placemarks.first.subLocality ??
              placemarks.first.locality ??
              'Bilinmeyen Mahalle';
        }

        Map<String, dynamic> locationData = {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': ServerValue.timestamp,
          'neighborhood': neighborhood,
          'accuracy': 'gps',
          'accuracyMeters': position.accuracy
        };

        return locationData;
      } catch (e) {
        print('GPS konum hatası: $e');
        String? wifiName = await _networkInfo.getWifiName();
        String? wifiBSSID = await _networkInfo.getWifiBSSID();

        if (wifiName != null && wifiBSSID != null) {
          Map<String, dynamic> locationData = {
            'timestamp': ServerValue.timestamp,
            'wifiName': wifiName,
            'wifiBSSID': wifiBSSID,
            'accuracy': 'wifi',
            'neighborhood': 'WiFi Bölgesi'
          };

          return locationData;
        }

        throw Exception('Konum alınamadı');
      }
    } catch (e) {
      print('Konum alma hatası: $e');
      rethrow;
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _addJob() async {
    if (_jobNameController.text.isEmpty ||
        _jobDescriptionController.text.isEmpty ||
        _jobPriceController.text.isEmpty ||
        _categoryController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen tüm alanları doldurun')),
      );
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      DocumentSnapshot userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .get();

      String username = userSnapshot['username'] ?? 'Bilinmeyen Kullanıcı';

      DocumentReference jobRef =
          FirebaseFirestore.instance.collection('jobs').doc();
      String jobId = jobRef.id;

      Map<String, dynamic> jobData = Job(
        id: jobId,
        jobName: _jobNameController.text,
        jobDescription: _jobDescriptionController.text,
        jobPrice: double.parse(_jobPriceController.text),
        employerId: widget.user.uid,
        username: username,
        category: _categoryController.text,
        hasLocation: _shareLocation,
      ).toMap();

      if (_shareLocation) {
        try {
          Map<String, dynamic>? locationData = await _getLocationForJob();

          if (locationData != null) {
            await _database.child('job_locations').child(jobId).set({
              'latitude': locationData['latitude'],
              'longitude': locationData['longitude'],
              'timestamp': ServerValue.timestamp,
              'neighborhood': locationData['neighborhood'],
              'accuracy': locationData['accuracy'],
              'accuracyMeters': locationData['accuracyMeters']
            });

            jobData['neighborhood'] = locationData['neighborhood'];
            jobData['hasLocation'] = true;
          }
        } catch (e) {
          print('Konum kaydetme hatası: $e');
          jobData['hasLocation'] = false;
        }
      }

      await jobRef.set(jobData);

      _jobNameController.clear();
      _jobDescriptionController.clear();
      _jobPriceController.clear();
      _categoryController.clear();
      setState(() {
        _shareLocation = false;
      });

      await _fetchData();
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İş başarıyla eklendi')),
      );
    } catch (e) {
      print('İş ekleme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İş eklenirken hata oluştu: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteJob(Job job) async {
    try {
      await FirebaseFirestore.instance.collection('jobs').doc(job.id).delete();

      List<Job> cachedJobs = _jobs.where((j) => j.id != job.id).toList();
      await _prefs.setString('cached_jobs_${widget.user.uid}',
          json.encode(cachedJobs.map((job) => job.toJson()).toList()));

      setState(() {
        _jobs = cachedJobs;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('İş ilanı başarıyla silindi')),
        );
      }
    } catch (e) {
      print('İş silme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('İş ilanı silinirken bir hata oluştu')),
        );
      }
    }
  }

  void _addReview() async {
    if (FirebaseAuth.instance.currentUser!.uid == widget.user.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Kendi profilinize değerlendirme ekleyemezsiniz')),
      );
      return;
    }

    try {
      QuerySnapshot existingReviewSnapshot = await FirebaseFirestore.instance
          .collection('reviews')
          .where('employerId', isEqualTo: widget.user.uid)
          .where('reviewerId',
              isEqualTo: FirebaseAuth.instance.currentUser!.uid)
          .get();

      if (existingReviewSnapshot.docs.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Bu kullanıcıya zaten değerlendirme yaptınız')),
          );
        }
        return;
      }

      double rating = 0;
      final reviewController = TextEditingController();
      bool isSubmitting = false;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setModalState) {
              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Container(
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
                      const SizedBox(height: 20),
                      RatingBar.builder(
                        initialRating: rating,
                        minRating: 1,
                        direction: Axis.horizontal,
                        allowHalfRating: true,
                        itemCount: 5,
                        itemPadding:
                            const EdgeInsets.symmetric(horizontal: 4.0),
                        itemBuilder: (context, _) => const Icon(
                          Icons.star,
                          color: Colors.amber,
                        ),
                        onRatingUpdate: (newRating) {
                          setModalState(() {
                            rating = newRating;
                          });
                        },
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: reviewController,
                        decoration: const InputDecoration(
                          labelText: 'Yorumunuz',
                          border: OutlineInputBorder(),
                          hintText: 'Deneyiminizi paylaşın...',
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                  if (rating == 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content:
                                              Text('Lütfen bir puan verin')),
                                    );
                                    return;
                                  }
                                  if (reviewController.text.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content:
                                              Text('Lütfen bir yorum yazın')),
                                    );
                                    return;
                                  }

                                  setModalState(() {
                                    isSubmitting = true;
                                  });

                                  try {
                                    DocumentSnapshot currentUserDoc =
                                        await FirebaseFirestore.instance
                                            .collection('users')
                                            .doc(FirebaseAuth
                                                .instance.currentUser!.uid)
                                            .get();

                                    String reviewerUsername =
                                        (currentUserDoc.data() as Map<String,
                                                dynamic>)['username'] ??
                                            'Anonim Kullanıcı';

                                    await FirebaseFirestore.instance
                                        .collection('reviews')
                                        .add({
                                      'employerId': widget.user.uid,
                                      'reviewerId': FirebaseAuth
                                          .instance.currentUser!.uid,
                                      'reviewerUsername': reviewerUsername,
                                      'rating': rating,
                                      'comment': reviewController.text,
                                      'createdAt': FieldValue.serverTimestamp(),
                                    });

                                    if (mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Değerlendirmeniz başarıyla eklendi')),
                                      );
                                      _fetchData();
                                    }
                                  } catch (e) {
                                    print('Değerlendirme ekleme hatası: $e');
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                'Değerlendirme eklenirken hata oluştu: $e')),
                                      );
                                    }
                                  } finally {
                                    setModalState(() {
                                      isSubmitting = false;
                                    });
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            backgroundColor: Colors.blue,
                          ),
                          child: Text(
                            isSubmitting
                                ? 'Gönderiliyor...'
                                : 'Değerlendirmeyi Gönder',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } catch (e) {
      print('Değerlendirme dialog hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bir hata oluştu: $e')),
        );
      }
    }
  }

  void _calculateAverageRating() {
    if (_reviews.isEmpty) {
      setState(() {
        _averageRating = 0.0;
      });
      return;
    }

    double totalRating = _reviews.fold(0, (sum, review) => sum + review.rating);
    setState(() {
      _averageRating = totalRating / _reviews.length;
    });
  }

  void _showAddJobBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Yeni İş İlanı',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: _jobNameController,
                      decoration: const InputDecoration(
                        labelText: 'İş Adı',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.work),
                      ),
                      maxLength: 20,
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: _categoryController,
                      focusNode: _categoryFocusNode,
                      decoration: const InputDecoration(
                          labelText: 'İş Katagorisi',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category)),
                      onChanged: (query) {
                        _filterCategories(query);
                        setModalState(() {
                          _isCategoryListVisible = query.isNotEmpty;
                        });
                      },
                      maxLength: 20,
                    ),
                    if (_isCategoryListVisible)
                      SizedBox(
                        height: 60,
                        child: ListView.builder(
                          controller: _scrollController,
                          scrollDirection: Axis.horizontal,
                          itemCount: _filteredCategories.length,
                          itemBuilder: (context, index) {
                            String category = _filteredCategories[index];
                            return GestureDetector(
                              onTap: () {
                                _categoryController.text = category;
                                _isCategoryListVisible = false;
                                _categoryFocusNode.unfocus();
                                setModalState(() {});
                              },
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8.0),
                                child: Chip(
                                  label: Text(category),
                                  backgroundColor: Colors.blue[100],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _jobDescriptionController,
                      decoration: const InputDecoration(
                        labelText: 'İş Açıklaması',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.description),
                      ),
                      maxLines: 3,
                      maxLength: 150,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _jobPriceController,
                      decoration: const InputDecoration(
                        labelText: 'İş Ücreti',
                        border: OutlineInputBorder(),
                        prefixText: '₺ ',
                      ),
                      maxLength: 6,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Checkbox(
                          value: _shareLocation,
                          onChanged: (bool? newValue) {
                            setModalState(() {
                              _shareLocation = newValue ?? false;
                            });
                          },
                        ),
                        const Expanded(
                          child: Text(
                            'Yakındaki kullanıcılara göster (Konumunuz paylaşılacak)',
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _addJob,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.add),
                      label: Text(_isLoading ? 'Ekleniyor...' : 'İşi Kaydet'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        minimumSize: const Size(double.infinity, 45),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showJobDetails(Job job) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(16),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          job.jobName,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.category, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          job.category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.attach_money, color: Colors.green),
                      Text(
                        '${job.jobPrice.toStringAsFixed(2)} ₺',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'İş Açıklaması:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    job.jobDescription,
                    style: const TextStyle(height: 1.4),
                  ),
                  if (job.hasLocation) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            job.neighborhood ?? 'Konum bilgisi yok',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (FirebaseAuth.instance.currentUser?.uid == widget.user.uid)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteJob(job);
                          },
                          icon: const Icon(Icons.delete, color: Colors.red),
                          label: const Text(
                            'İlanı Sil',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSkeletonCard() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        child: Card(
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 200,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  height: 15,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 100,
                  height: 15,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('İş Veren Profil Sayfası'),
        centerTitle: true,
        leading: isCurrentUser
            ? Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
        actions: [
          if (isCurrentUser) // Sadece kendi profilinde QR okuyucu göster
            IconButton(
              icon: const Icon(Icons.share),
              color: Colors.blue,
              onPressed: () {
                // Mevcut paylaşma fonksiyonu
              },
            ),
         IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => QRScannerapp(
                    currentUser: FirebaseAuth.instance.currentUser!,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      drawer: isCurrentUser ? MyDrawer(user: widget.user) : null,
      body: !_hasLoadedCache
          ? ListView.builder(
              itemCount: 3,
              itemBuilder: (context, index) => _buildSkeletonCard(),
            )
          : RefreshIndicator(
              onRefresh: _fetchData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Hero(
                        tag: 'profile-${widget.user.uid}',
                        child: CircleAvatar(
                          radius: 60,
                          backgroundImage: widget.user.profileImageUrl != null
                              ? NetworkImage(widget.user.profileImageUrl!)
                              : null,
                          child: widget.user.profileImageUrl == null
                              ? const Icon(Icons.person, size: 60)
                              : null,
                        ),
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star, color: Colors.amber),
                            const SizedBox(width: 5),
                            Text(
                              _averageRating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              ' (${_reviews.length} Değerlendirme)',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.work, color: Colors.blue),
                                      SizedBox(width: 8),
                                      Text(
                                        'İş İlanları',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (FirebaseAuth.instance.currentUser?.uid ==
                                      widget.user.uid)
                                    ElevatedButton.icon(
                                      onPressed: _showAddJobBottomSheet,
                                      icon: const Icon(Icons.add, size: 18),
                                      label: const Text('Yeni İş Ekle'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                      ),
                                    ),
                                  IconButton(
                                      onPressed: () {},
                                      icon: Icon(Icons.share),
                                      color: Colors.blue,
                                      style: IconButton.styleFrom())
                                ],
                              ),
                              const SizedBox(height: 10),
                              _jobs.isEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(20.0),
                                        child: Text(
                                          'Henüz iş ilanı yok',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    )
                                  : SizedBox(
                                      height: 120,
                                      child: PageView.builder(
                                        controller: PageController(
                                            viewportFraction: 0.9),
                                        itemCount: _jobs.length,
                                        itemBuilder: (context, index) {
                                          Job job = _jobs[index];
                                          final colors = [
                                            Color(0xFFE3F2FD),
                                            Color(0xFFF3E5F5),
                                            Color(0xFFF1F8E9),
                                            Color(0xFFFFF3E0),
                                          ];
                                          return GestureDetector(
                                            onTap: () => _showJobDetails(job),
                                            child: Container(
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8),
                                              child: Card(
                                                elevation: 3,
                                                color: colors[
                                                    index % colors.length],
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(15),
                                                ),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(12),
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: Text(
                                                              job.jobName,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style:
                                                                  const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 16,
                                                              ),
                                                            ),
                                                          ),
                                                          Text(
                                                            '${job.jobPrice.toStringAsFixed(2)} ₺',
                                                            style:
                                                                const TextStyle(
                                                              color:
                                                                  Colors.green,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        job.jobDescription,
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      if (job.hasLocation)
                                                        Row(
                                                          children: [
                                                            const Icon(
                                                                Icons
                                                                    .location_on,
                                                                size: 14,
                                                                color: Colors
                                                                    .grey),
                                                            const SizedBox(
                                                                width: 4),
                                                            Expanded(
                                                              child: Text(
                                                                job.neighborhood ??
                                                                    'Konum bilgisi yok',
                                                                style:
                                                                    const TextStyle(
                                                                  color: Colors
                                                                      .grey,
                                                                  fontSize: 12,
                                                                ),
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.rate_review,
                                          color: Colors.amber),
                                      SizedBox(width: 8),
                                      Text(
                                        'Değerlendirmeler',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (FirebaseAuth.instance.currentUser?.uid !=
                                      widget.user.uid)
                                    ElevatedButton.icon(
                                      onPressed: _addReview,
                                      icon: const Icon(Icons.star, size: 18),
                                      label: const Text('Değerlendir'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 8),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _reviews.isEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(20.0),
                                        child: Text(
                                          'Henüz değerlendirme yok',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    )
                                  : SizedBox(
                                      height: 120,
                                      child: PageView.builder(
                                        controller: PageController(
                                            viewportFraction: 0.9),
                                        itemCount: _reviews.length,
                                        itemBuilder: (context, index) {
                                          Review review = _reviews[index];
                                          final colors = [
                                            Color(0xFFFCE4EC),
                                            Color(0xFFE8EAF6),
                                            Color(0xFFE0F2F1),
                                            Color(0xFFFFF8E1),
                                          ];
                                          return Container(
                                            margin: const EdgeInsets.symmetric(
                                                horizontal: 8),
                                            child: Card(
                                              elevation: 3,
                                              color:
                                                  colors[index % colors.length],
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(15),
                                              ),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        const CircleAvatar(
                                                          child: Icon(Icons
                                                              .person_outline),
                                                        ),
                                                        const SizedBox(
                                                            width: 8),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                review.reviewerUsername ??
                                                                    'Anonim Kullanıcı',
                                                                style:
                                                                    const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                ),
                                                              ),
                                                              Row(
                                                                children: List
                                                                    .generate(
                                                                  5,
                                                                  (starIndex) =>
                                                                      Icon(
                                                                    starIndex <
                                                                            review.rating
                                                                                .round()
                                                                        ? Icons
                                                                            .star
                                                                        : Icons
                                                                            .star_border,
                                                                    color: Colors
                                                                        .amber,
                                                                    size: 16,
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Expanded(
                                                      child: Text(
                                                        review.comment,
                                                        style: const TextStyle(
                                                          color: Colors.black87,
                                                        ),
                                                        maxLines: 3,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      floatingActionButton:
          FirebaseAuth.instance.currentUser?.uid == widget.user.uid
              ? FloatingActionButton(
                  onPressed: _showAddJobBottomSheet,
                  child: const Icon(Icons.add),
                )
              : null,
    );
  }
}
