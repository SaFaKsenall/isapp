import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:geocoding/geocoding.dart';
import 'package:myapp/model/job_and_rivevws.dart';
import 'package:myapp/model/user_model.dart';

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
  bool _isLoading = false;
  List<String> _categories = [];
  List<String> _filteredCategories = [];
  bool _isCategoryListVisible = false;
  final FocusNode _categoryFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchJobs();
    _fetchReviews();
    _fetchCategories();
    _categoryFocusNode.addListener(_handleCategoryFocusChange);
  }

  @override
  void dispose() {
    _categoryFocusNode.removeListener(_handleCategoryFocusChange);
    _categoryFocusNode.dispose();
    _jobNameController.dispose();
    _jobDescriptionController.dispose();
    _jobPriceController.dispose();
    _categoryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleCategoryFocusChange() {
    if (!_categoryFocusNode.hasFocus) {
      setState(() {
        _isCategoryListVisible = false;
      });
    }
  }

  // Kategori çekme fonksiyonu
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

  // Kategori filtreleme fonksiyonu
  void _filterCategories(String query) {
    setState(() {
      _filteredCategories = _categories
          .where((category) =>
              category.toLowerCase().contains(query.toLowerCase()))
          .take(3)
          .toList();
    });
  }

  // Konum bilgisi alma fonksiyonu (İş ilanı için ayrı)
  Future<Map<String, dynamic>?> _getLocationForJob() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // Konum izni kontrolü
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

      // Konum servisleri kontrolü
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Konum servisleri kapalı');
      }

      // GPS konumu alma
      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.reduced,
          timeLimit: const Duration(seconds: 10),
        );

        // Mahalle bilgisi alma
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
        // GPS başarısız olursa WiFi konumunu dene
        String? wifiName = await _networkInfo.getWifiName();
        String? wifiBSSID = await _networkInfo.getWifiBSSID();

        if (wifiName != null && wifiBSSID != null) {
          // WiFi bilgilerini kaydet
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

  // İş ilanlarını çekme fonksiyonu
  Future<void> _fetchJobs() async {
    try {
      setState(() {
        _isLoading = true;
      });

      QuerySnapshot<Map<String, dynamic>> jobSnapshot = await FirebaseFirestore
          .instance
          .collection('jobs')
          .where('employerId', isEqualTo: widget.user.uid)
          .get();

      setState(() {
        _jobs = jobSnapshot.docs.map((doc) {
          // Her bir dokümanın ID'sini ve verilerini birleştiriyoruz
          Map<String, dynamic> data = doc.data();
          data['id'] = doc.id; // Doküman ID'sini data'ya ekliyoruz
          return Job.fromMap(data);
        }).toList();
      });
    } catch (e) {
      print('Jobs fetch error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İş ilanları yüklenirken hata oluştu')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Değerlendirmeleri çekme fonksiyonu
  Future<void> _fetchReviews() async {
    try {
      setState(() {
        _isLoading = true;
      });

      QuerySnapshot reviewSnapshot = await FirebaseFirestore.instance
          .collection('reviews')
          .where('employerId', isEqualTo: widget.user.uid)
          .get();

      List<Review> reviewList = [];
      for (var doc in reviewSnapshot.docs) {
        Map<String, dynamic> reviewData = doc.data() as Map<String, dynamic>;

        DocumentSnapshot userSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(reviewData['reviewerId'])
            .get();

        reviewList.add(Review(
          employerId: reviewData['employerId'],
          reviewerId: reviewData['reviewerId'],
          rating: reviewData['rating'],
          comment: reviewData['comment'],
          reviewerUsername: userSnapshot['username'] ?? 'Anonim Kullanıcı',
        ));
      }

      setState(() {
        _reviews = reviewList;
      });

      _calculateAverageRating();
    } catch (e) {
      print('Reviews fetch error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Değerlendirmeler yüklenirken hata oluştu')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // İş ilanı ekleme fonksiyonu
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

      // Önce Firestore'da iş dokümanını oluştur
      DocumentReference jobRef =
          FirebaseFirestore.instance.collection('jobs').doc();
      String jobId = jobRef.id; // ID'yi önceden al

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

      // Konum paylaşımı aktifse
      if (_shareLocation) {
        try {
          print('Konum alma işlemi başlatılıyor...');
          Map<String, dynamic>? locationData = await _getLocationForJob();

          if (locationData != null) {
            print('Konum alındı: $locationData');

            await _database
                .child('job_locations')
                .child(jobId)
                .set(locationData);
            print('Konum Realtime Database\'e kaydedildi');

            jobData['neighborhood'] = locationData['neighborhood'];
            print('Job verisi güncellendi: $jobData');
          } else {
            jobData['hasLocation'] = false;
            print('HATA: Konum alınamadı - locationData null');
          }
        } catch (e, stackTrace) {
          jobData['hasLocation'] = false;
          print('Konum alma hatası: $e');
          print('Stack trace: $stackTrace');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Konum alınamadı: ${e.toString()}')),
          );
        }
      }

      // Firestore'a kaydet
      await jobRef.set(jobData);

      _jobNameController.clear();
      _jobDescriptionController.clear();
      _jobPriceController.clear();
      _categoryController.clear();
      setState(() {
        _shareLocation = false;
      });

      await _fetchJobs();
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

  // İş ilanı silme fonksiyonu
  void _deleteJob(Job job) async {
    try {
      if (job.id.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Geçersiz iş ID\'si')),
        );
        return;
      }

      // UI'da silme işlemini hemen yansıtmak için listeyi güncelliyoruz
      setState(() {
        _jobs.remove(job);
      });

      // Silme işlemi için circle gösteriyoruz
      showDialog(
        context: context,
        barrierDismissible:
            false, // Kullanıcı dialog dışına tıklayarak kapatamaz
        builder: (BuildContext context) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
      );

      await FirebaseFirestore.instance.collection('jobs').doc(job.id).delete();

      // İşin konumu varsa Realtime Database'den sil
      if (job.toMap().containsKey('locationId')) {
        await _database
            .child('job_locations')
            .child(job.toMap()['locationId'])
            .remove();
      }

      // Circle indicator'ı kapat
      Navigator.of(context).pop();

      // İşlemin başarılı olduğunu bildiren snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İş ilanı silindi')),
      );

      _fetchJobs();
    } catch (e) {
      print('İş silme hatası: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('İş ilanı silinirken hata oluştu: ${e.toString()}')),
      );
      // Circle indicator'ı kapat
      Navigator.of(context).pop();
      _fetchJobs(); // Hata durumunda listeyi yeniden yükle
    }
  }

  // Değerlendirme ekleme fonksiyonu
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Bu kullanıcıya zaten değerlendirme yaptınız')),
        );
        return;
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          double rating = 0;
          final reviewController = TextEditingController();

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
                      const SizedBox(height: 10),
                      RatingBar.builder(
                        initialRating: rating,
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
                          if (rating == 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Lütfen bir puan verin')),
                            );
                            return;
                          }
                          if (reviewController.text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Lütfen bir yorum yazın')),
                            );
                            return;
                          }

                          try {
                            setState(() {
                              _isLoading = true;
                            });

                            await FirebaseFirestore.instance
                                .collection('reviews')
                                .add(
                                  Review(
                                    employerId: widget.user.uid,
                                    reviewerId:
                                        FirebaseAuth.instance.currentUser!.uid,
                                    rating: rating,
                                    comment: reviewController.text,
                                  ).toMap(),
                                );

                            await _fetchReviews();
                            Navigator.pop(context);

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Değerlendirme başarıyla eklendi')),
                            );
                          } catch (e) {
                            print('Değerlendirme ekleme hatası: $e');
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Değerlendirme eklenirken hata oluştu: ${e.toString()}')),
                            );
                          } finally {
                            setState(() {
                              _isLoading = false;
                            });
                          }
                        },
                        child: const Text('Değerlendirmeyi Kaydet'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bir hata oluştu: ${e.toString()}')),
      );
    }
  }

  // Ortalama puan hesaplama fonksiyonu
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

  // İş ilanı ekleme bottom sheet'i gösterme fonksiyonu
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
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _jobPriceController,
                      decoration: const InputDecoration(
                        labelText: 'İş Ücreti',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('İş Veren Profil Sayfası'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _fetchJobs();
                await _fetchReviews();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Profil Resmi
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
                      // Kullanıcı Adı
                      Text(
                        widget.user.username,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Ortalama Puan
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
                      // Aksiyon Butonları
                      if (FirebaseAuth.instance.currentUser!.uid ==
                          widget.user.uid)
                        ElevatedButton.icon(
                          onPressed: _showAddJobBottomSheet,
                          icon: const Icon(Icons.add),
                          label: const Text('Yeni İş Ekle'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            minimumSize: const Size(200, 45),
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          onPressed: _addReview,
                          icon: const Icon(Icons.rate_review),
                          label: const Text('Değerlendir'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            minimumSize: const Size(200, 45),
                          ),
                        ),
                      const SizedBox(height: 20),
                      // İş İlanları
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
                                  : ListView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: _jobs.length,
                                      itemBuilder: (context, index) {
                                        Job job = _jobs[index];
                                        return Card(
                                          margin:
                                              const EdgeInsets.symmetric(vertical: 8),
                                          child: ListTile(
                                            title: Text(
                                              job.jobName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const SizedBox(height: 5),
                                                Text(job.jobDescription),
                                                const SizedBox(height: 5),
                                                Text(
                                                  'Ücret: ₺${job.jobPrice.toStringAsFixed(2)}',
                                                  style: const TextStyle(
                                                    color: Colors.green,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                if (job.username != null)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 5),
                                                    child: Row(
                                                      children: [
                                                        const Icon(
                                                          Icons.person,
                                                          size: 16,
                                                          color: Colors.grey,
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          'İş Veren: ${job.username!}',
                                                          style: const TextStyle(
                                                            color: Colors.grey,
                                                            fontStyle: FontStyle
                                                                .italic,
                                                          ),
                                                        )
                                                      ],
                                                    ),
                                                  ),
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 5),
                                                  child: Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.category,
                                                        size: 16,
                                                        color: Colors.grey,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        'Katagori: ${job.category}',
                                                        style: const TextStyle(
                                                          color: Colors.grey,
                                                          fontStyle: FontStyle
                                                              .italic,
                                                        ),
                                                      )
                                                    ],
                                                  ),
                                                ),
                                                // Konum bilgisini göster
                                                if (job.toMap().containsKey(
                                                    'neighborhood'))
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 5),
                                                    child: Row(
                                                      children: [
                                                        if (job.toMap()[
                                                                'neighborhood'] !=
                                                            null)
                                                          const Icon(
                                                              Icons.location_on,
                                                              size: 16,
                                                              color:
                                                                  Colors.blue),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          job.toMap()[
                                                                  'neighborhood'] ??
                                                              'Konum Belirtilmemiş',
                                                          style: const TextStyle(
                                                            color: Colors.blue,
                                                            fontStyle: FontStyle
                                                                .italic,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            trailing: FirebaseAuth.instance
                                                        .currentUser!.uid ==
                                                    widget.user.uid
                                                ? IconButton(
                                                    icon: const Icon(Icons.delete,
                                                        color: Colors.red),
                                                    onPressed: () =>
                                                        _deleteJob(job),
                                                  )
                                                : null,
                                          ),
                                        );
                                      },
                                    ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Değerlendirmeler
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
                              const Row(
                                children: [
                                  Icon(Icons.rate_review, color: Colors.amber),
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
                                  : ListView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: _reviews.length,
                                      itemBuilder: (context, index) {
                                        Review review = _reviews[index];
                                        return Card(
                                          margin:
                                              const EdgeInsets.symmetric(vertical: 8),
                                          child: ListTile(
                                            leading: const CircleAvatar(
                                              child: Icon(Icons.person_outline),
                                            ),
                                            title: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  review.reviewerUsername ??
                                                      'Anonim Kullanıcı',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Row(
                                                  children: List.generate(
                                                    5,
                                                    (starIndex) => Icon(
                                                      starIndex <
                                                              review.rating
                                                                  .round()
                                                          ? Icons.star
                                                          : Icons.star_border,
                                                      color: Colors.amber,
                                                      size: 16,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            subtitle: Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 8.0),
                                              child: Text(
                                                review.comment,
                                                style: const TextStyle(
                                                  color: Colors.black87,
                                                ),
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
            ),
    );
  }
}
