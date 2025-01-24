import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:animations/animations.dart';
import 'package:myapp/chat/chatpage.dart';
import 'package:myapp/model/job_and_rivevws.dart';
import 'package:myapp/model/user_model.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';

class JobPostCard extends StatelessWidget {
  final Job job;
  final bool isDetailPage;
  final void Function(String jobId) onApplicationChanged;
  final double? distance;

  const JobPostCard({
    Key? key,
    required this.job,
    required this.onApplicationChanged,
    this.isDetailPage = false,
    this.distance,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        height: 70, // Sabit yükseklik
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Theme.of(context).primaryColor.withOpacity(0.05),
              Theme.of(context).cardColor,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          image: DecorationImage(
            image: AssetImage('assets/pattern.png'), // Desen resmi ekleyin
            opacity: 0.03,
            repeat: ImageRepeat.repeat,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Sol taraf - Profil resmi
                  Hero(
                    tag: 'profile-${job.id}',
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                Theme.of(context).primaryColor.withOpacity(0.2),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        backgroundColor:
                            Theme.of(context).primaryColor.withOpacity(0.1),
                        backgroundImage: job.profileImage != null
                            ? NetworkImage(job.profileImage!)
                            : null,
                        child: job.profileImage == null
                            ? const Icon(Icons.person,
                                size: 30, color: Colors.white70)
                            : null,
                      ),
                    ),
                  ).animate().scale(duration: 400.ms, curve: Curves.easeOut),

                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Text(
                      job.jobName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ).animate().fadeIn(duration: 400.ms).slideX(),
                  ),

                  // Konum Bilgisi
                  if (job.neighborhood != null || distance != null)
                    Expanded(
                      flex: 1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_on,
                                size: 14, color: Colors.blue[400]),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                distance != null
                                    ? _formatDistance(distance)
                                    : job.neighborhood ?? "",
                                style: TextStyle(
                                  color: Colors.blue[700],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: 200.ms).slideX(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).scale(delay: 100.ms);
  }

  String _formatDistance(double? distance) {
    if (distance == null) return '';

    if (distance == 0.0) {
      return 'Aynı konumdasınız';
    } else if (distance < 1.0) {
      // 1 km'den küçük mesafeleri metre cinsinden göster
      return '${(distance * 1000).toInt()} metre';
    } else {
      // 1 km ve üzeri mesafeleri km cinsinden göster
      return '${distance.toStringAsFixed(1)} km';
    }
  }
}

class JobSearchPage extends StatefulWidget {
  const JobSearchPage({Key? key}) : super(key: key);

  @override
  _JobSearchPageState createState() => _JobSearchPageState();
}

class _JobSearchPageState extends State<JobSearchPage> {
  List<Job> _jobs = [];
  List<Job> _filteredJobs = [];
  bool _isLoading = true;
  final Map<String, UserModel> _userCache = {};
  final TextEditingController _searchController = TextEditingController();
  RangeValues _priceRange = const RangeValues(0, 10000);
  bool _showNearbyUsers = false;
  Position? _currentPosition;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseReference _locationsRef =
      FirebaseDatabase.instance.ref('locations');
  final DatabaseReference _userLocationsRef =
      FirebaseDatabase.instance.ref('user_locations');
  final DatabaseReference _jobLocationsRef =
      FirebaseDatabase.instance.ref('job_locations');
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  @override
  void initState() {
    super.initState();
    _initializeJobs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onApplicationChanged(String jobId) {
    setState(() {
      _filteredJobs = _filteredJobs.map((job) {
        if (job.id == jobId) {
          return job.copyWith();
        }
        return job;
      }).toList();
      _jobs = _jobs.map((job) {
        if (job.id == jobId) {
          return job.copyWith();
        }
        return job;
      }).toList();
    });
  }

  Future<void> _initializeJobs() async {
    setState(() => _isLoading = true);
    try {
      await _fetchJobs();
      _filteredJobs = List.from(_jobs);
    } catch (e) {
      print('Initialization error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('İşler yüklenirken hata oluştu')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Konum izni verilmedi.')),
          );
          return;
        }
      }
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        await _updateLocationInDatabase(currentUser.uid, position);
      }

      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      print("konum alma hatası: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konum alınamadı.')),
      );
    }
  }

  Future<void> _updateLocationInDatabase(
      String userId, Position position) async {
    try {
      await _userLocationsRef.child(userId).set({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracyMeters': position.accuracy
      });
    } catch (e) {
      print("konum kayıt hatası: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konum kaydedilirken hata oluştu: $e')),
      );
    }
  }

  Future<UserModel?> _getUser(String userId) async {
    if (_userCache.containsKey(userId)) {
      return _userCache[userId];
    }

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        userData['uid'] = userId;
        final user = UserModel.fromMap(userData);
        _userCache[userId] = user;
        return user;
      }
      return null;
    } catch (e) {
      print('Error fetching user data: $e');
      return null;
    }
  }

  Future<void> _calculateAndSaveDistances(List<Job> jobs) async {
    if (_currentPosition == null) return;
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    // Kullanıcı konumunu bir kere al
    final userSnapshot = await _userLocationsRef.child(currentUser.uid).get();
    if (!userSnapshot.exists) return;

    final userDataFromDb = userSnapshot.value as Map<Object?, Object?>;
    final double userLat = (userDataFromDb['latitude'] as num).toDouble();
    final double userLng = (userDataFromDb['longitude'] as num).toDouble();

    // Önce kabaca mesafe hesaplaması yap ve sırala
    List<MapEntry<Job, double>> jobsWithRoughDistance = [];
    
    for (final job in jobs) {
      try {
        final jobLocationSnapshot = await _jobLocationsRef.child(job.id).get();
        if (!jobLocationSnapshot.exists) continue;

        final jobDataFromDb = jobLocationSnapshot.value as Map<Object?, Object?>;
        if (jobDataFromDb['latitude'] == null || jobDataFromDb['longitude'] == null) continue;

        final double jobLat = (jobDataFromDb['latitude'] as num).toDouble();
        final double jobLng = (jobDataFromDb['longitude'] as num).toDouble();

        // Kabaca mesafe hesapla (daha hızlı)
        final roughDistance = (jobLat - userLat).abs() + (jobLng - userLng).abs();
        jobsWithRoughDistance.add(MapEntry(job, roughDistance));
      } catch (e) {
        print('Kabaca mesafe hesaplama hatası (${job.id}): $e');
      }
    }

    // Kabaca mesafeye göre sırala ve ilk 20'yi al
    jobsWithRoughDistance.sort((a, b) => a.value.compareTo(b.value));
    final nearestJobs = jobsWithRoughDistance.take(20).map((e) => e.key).toList();

    // Batch işlemi için hazırlık
    final batch = _firestore.batch();
    final List<Future<void>> distanceCalculations = [];

    // Sadece en yakın 20 iş için detaylı mesafe hesapla
    for (final job in nearestJobs) {
      distanceCalculations.add(() async {
        try {
          final jobLocationSnapshot = await _jobLocationsRef.child(job.id).get();
          if (!jobLocationSnapshot.exists) return;

          final jobDataFromDb = jobLocationSnapshot.value as Map<Object?, Object?>;
          if (jobDataFromDb['latitude'] == null || jobDataFromDb['longitude'] == null) return;

          final double jobLat = (jobDataFromDb['latitude'] as num).toDouble();
          final double jobLng = (jobDataFromDb['longitude'] as num).toDouble();

          // Hassas mesafe hesapla
          final distance = _calculateDistanceBetweenPoints(userLat, userLng, jobLat, jobLng);

          // Batch'e ekle
          final distanceDoc = _firestore.collection('distances').doc('${currentUser.uid}_${job.id}');
          batch.set(distanceDoc, {
            'userId': currentUser.uid,
            'jobId': job.id,
            'distance': distance,
            'updatedAt': FieldValue.serverTimestamp(),
          });

          // UI güncellemesi için job nesnesini güncelle
          if (mounted) {
            setState(() {
              job.distance = distance;
            });
          }
        } catch (e) {
          print('Detaylı mesafe hesaplama hatası (${job.id}): $e');
        }
      }());
    }

    // Tüm hesaplamaları paralel yap
    await Future.wait(distanceCalculations);
    
    // Batch'i commit et
    try {
      await batch.commit();
    } catch (e) {
      print('Batch commit hatası: $e');
    }
  }

  Future<void> _updateDistanceInFirestore(
      String currentUserId, String employerId, double distance) async {
    final locationDoc = _firestore
        .collection('loc')
        .doc(currentUserId)
        .collection('loca')
        .doc(employerId);
    await locationDoc.set(
        {'distance': distance, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true)).then((_) {
      print('Firestore güncellendi - Yeni mesafe: $distance');
    }).catchError((error) {
      print('Firestore güncelleme hatası - Hata: $error');
    });
  }

  void _updateJobDistances(List<Job> jobs) {
    if (!mounted) return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    for (final job in jobs) {
      _firestore
          .collection('distances')
          .doc('${currentUser.uid}_${job.id}')
          .get()
          .then((doc) {
        if (doc.exists && mounted) {
          final data = doc.data() as Map<String, dynamic>;
          setState(() {
            job.distance = data['distance'] as double?;
          });
        }
      }).catchError((e) {
        print('Mesafe verisi okuma hatası (${job.id}): $e');
      });
    }
  }

  Future<void> _fetchJobs() async {
    try {
      final QuerySnapshot jobSnapshot = await FirebaseFirestore.instance
          .collection('jobs')
          .where('status', isEqualTo: 'active')
          .get();

      final List<Job> newJobs = [];
      for (var doc in jobSnapshot.docs) {
        try {
          final jobData = doc.data() as Map<String, dynamic>;
          final String employerId = jobData['employerId'] ?? '';
          final user = await _getUser(employerId);

          if (user != null) {
            jobData['username'] = user.username;
            jobData['profileImage'] = user.profileImageUrl;
          }

          final Job job =
              Job.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>);
          print('Fetched job with id: ${job.id}');
          newJobs.add(job);
        } catch (e) {
          print('Error processing job document: $e');
          continue;
        }
      }

      setState(() {
        _jobs = newJobs;
        _filteredJobs = List.from(newJobs);
      });
    } catch (e) {
      print('Jobs fetch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('İşler yüklenirken hata oluştu')),
        );
      }
    }
  }

  double _calculateDistanceBetweenPoints(
      double lat1, double lon1, double lat2, double lon2) {
    // Haversine formülü kullanarak mesafe hesaplama
    const double earthRadius = 6371; // Dünya yarıçapı (km)

    // Radyana çevirme
    final double dLat = (lat2 - lat1) * (pi / 180);
    final double dLon = (lon2 - lon1) * (pi / 180);

    // Haversine formülü
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180)) *
            cos(lat2 * (pi / 180)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final double distance = earthRadius * c;

    return double.parse(distance.toStringAsFixed(2)); // 2 decimal hassasiyet
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }

  void _filterJobs() {
    if (!mounted) return;

    setState(() {
      _filteredJobs = _jobs.where((job) {
        final searchText = _searchController.text.toLowerCase();
        final matchesSearch = job.jobName.toLowerCase().contains(searchText) ||
            job.jobDescription.toLowerCase().contains(searchText);

        final matchesPriceRange = job.jobPrice >= _priceRange.start &&
            job.jobPrice <= _priceRange.end;

        return matchesSearch && matchesPriceRange;
      }).toList();
    });
  }

  void _showFilterBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fiyat Filtresi',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Text(
                      'Fiyat Aralığı: ₺${_priceRange.start.toStringAsFixed(0)} - ₺${_priceRange.end.toStringAsFixed(0)}'),
                  RangeSlider(
                    values: _priceRange,
                    min: 0,
                    max: 10000,
                    divisions: 100,
                    labels: RangeLabels(
                      '₺${_priceRange.start.toStringAsFixed(0)}',
                      '₺${_priceRange.end.toStringAsFixed(0)}',
                    ),
                    onChanged: (RangeValues values) {
                      setModalState(() => _priceRange = values);
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[200],
                          ),
                          onPressed: () {
                            setModalState(() {
                              _priceRange = const RangeValues(0, 10000);
                            });
                          },
                          child: const Text(
                            'Sıfırla',
                            style: TextStyle(color: Colors.black),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            _filterJobs();
                            Navigator.pop(context);
                          },
                          child: const Text('Uygula'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
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
        title: const Text('İş Arama'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterBottomSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _initializeJobs,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'İş ara...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _filterJobs();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (_) => _filterJobs(),
            ).animate().fadeIn(duration: 300.ms),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Text(
                  "Yakındaki İşleri Göster",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(
                  width: 16,
                ),
                _buildCheckbox(),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredJobs.isEmpty
                    ? const Center(
                        child: Text(
                          'Herhangi bir iş bulunamadı',
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _filteredJobs.length,
                        itemBuilder: (context, index) {
                          final job = _filteredJobs[index];
                          return OpenContainer(
                            closedElevation: 0,
                            openElevation: 0,
                            closedShape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            transitionDuration:
                                const Duration(milliseconds: 500),
                            closedBuilder: (context, action) => JobPostCard(
                              job: job,
                              isDetailPage: false,
                              onApplicationChanged: _onApplicationChanged,
                              distance: job.distance,
                            ),
                            openBuilder: (context, action) => JobDetailPage(
                              job: job,
                              onApplicationChanged: _onApplicationChanged,
                            ),
                          ).animate().fadeIn(
                                duration: 300.ms,
                                delay: Duration(milliseconds: index * 50),
                              );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckbox() {
    return GestureDetector(
      onTap: () async {
        setState(() {
          _showNearbyUsers = !_showNearbyUsers;
        });
        if (_showNearbyUsers) {
          await _getCurrentLocation().then((_) {
            if (_currentPosition != null) {
              return _calculateAndSaveDistances(_jobs);
            }
          });
        } else {
          setState(() {
            _filteredJobs = List.from(_jobs);
          });
        }
      },
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color:
                _showNearbyUsers ? Theme.of(context).primaryColor : Colors.grey,
            width: 2,
          ),
          color: _showNearbyUsers
              ? Theme.of(context).primaryColor
              : Colors.transparent,
        ),
        child: _showNearbyUsers
            ? Icon(
                Icons.check,
                size: 18,
                color: Colors.white,
              )
            : null,
      ),
    );
  }
}

// JobDetailPage Implementation
class JobDetailPage extends StatefulWidget {
  final Job job;
  final void Function(String jobId) onApplicationChanged;

  const JobDetailPage({
    Key? key,
    required this.job,
    required this.onApplicationChanged,
  }) : super(key: key);

  @override
  _JobDetailPageState createState() => _JobDetailPageState();
}

class _JobDetailPageState extends State<JobDetailPage> {
  bool _isApplied = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkIfApplied();
  }

  Future<void> _checkIfApplied() async {
    setState(() {
      _isLoading = true;
    });
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      final snapshot = await FirebaseFirestore.instance
          .collection('job_applications')
          .where('jobId', isEqualTo: widget.job.id)
          .where('applicantId', isEqualTo: currentUser.uid)
          .get();
      setState(() {
        _isApplied = snapshot.docs.isNotEmpty;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleApplication() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen önce giriş yapın')),
      );
      return;
    }

    if (currentUser.uid == widget.job.employerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kendi ilanınıza başvuru yapamazsınız')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_isApplied) {
        // Başvuruyu geri çekme
        final snapshot = await FirebaseFirestore.instance
            .collection('job_applications')
            .where('jobId', isEqualTo: widget.job.id)
            .where('applicantId', isEqualTo: currentUser.uid)
            .get();

        if (snapshot.docs.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('job_applications')
              .doc(snapshot.docs.first.id)
              .delete();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Başvurunuz geri çekildi')),
            );
            widget.onApplicationChanged(widget.job.id);
          }
        }
      } else {
        // Başvuru yapma
        await FirebaseFirestore.instance.collection('job_applications').add({
          'jobId': widget.job.id,
          'applicantId': currentUser.uid,
          'employerId': widget.job.employerId,
          'applicationDate': FieldValue.serverTimestamp(),
          'status': 'pending',
        });
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Başvurunuz alındı')),
          );
          widget.onApplicationChanged(widget.job.id);
        }
      }
      setState(() {
        _isApplied = !_isApplied;
        _isLoading = false;
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem sırasında bir hata oluştu: $e')),
        );
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.job.jobName),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // Share implementation
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '₺${widget.job.jobPrice.toStringAsFixed(2)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              Text(
                                widget.job.category,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: Colors.blue,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'İş Açıklaması',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(widget.job.jobDescription),
                          if (widget.job.neighborhood != null) ...[
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const Icon(Icons.location_on,
                                    color: Colors.grey),
                                const SizedBox(width: 8),
                                Text(
                                  widget.job.neighborhood!,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              if (widget.job.profileImage != null)
                                CircleAvatar(
                                  backgroundImage:
                                      NetworkImage(widget.job.profileImage!),
                                  radius: 20,
                                )
                              else
                                const CircleAvatar(
                                  radius: 20,
                                  child: Icon(Icons.person),
                                ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.job.username ?? 'İsimsiz Kullanıcı',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'İş Veren',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Column(
                                children: [
                                  Text(
                                    widget.job.likes.toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const Text(
                                    'Beğeni',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                children: [
                                  Text(
                                    widget.job.comments.toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const Text(
                                    'Yorum',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                children: [
                                  Text(
                                    '₺${widget.job.budget.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const Text(
                                    'Bütçe',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (widget.job.reviews != null &&
                              widget.job.reviews!.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Text(
                              'Değerlendirmeler',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: widget.job.reviews!.length,
                              itemBuilder: (context, index) {
                                final review = widget.job.reviews![index];
                                return Card(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              backgroundImage:
                                                  review.reviewerProfileImage !=
                                                          null
                                                      ? NetworkImage(review
                                                          .reviewerProfileImage!)
                                                      : null,
                                              radius: 16,
                                              child:
                                                  review.reviewerProfileImage ==
                                                          null
                                                      ? const Icon(Icons.person,
                                                          size: 16)
                                                      : null,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              review.reviewerUsername ??
                                                  'İsimsiz Kullanıcı',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold),
                                            ),
                                            const Spacer(),
                                            Row(
                                              children: List.generate(
                                                5,
                                                (i) => Icon(
                                                  i < review.rating.round()
                                                      ? Icons.star
                                                      : Icons.star_border,
                                                  color: Colors.amber,
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(review.comment),
                                        if (review.createdAt != null)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 4),
                                            child: Text(
                                              _formatDate(review.createdAt!),
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.message),
                  label: const Text('Mesaj Gönder'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final currentUser = FirebaseAuth.instance.currentUser;
                    if (currentUser == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Lütfen önce giriş yapın')),
                      );
                      return;
                    }

                    if (currentUser.uid == widget.job.employerId) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Kendi ilanınıza mesaj gönderemezsiniz')),
                      );
                      return;
                    }

                    // Firestore'dan mesajı göndereceğimiz kullanıcının verilerini alıyoruz
                    DocumentSnapshot userDoc = await FirebaseFirestore.instance
                        .collection('users')
                        .doc(widget.job.employerId)
                        .get();

                    if (userDoc.exists) {
                      final userData = userDoc.data() as Map<String, dynamic>;
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
                            content: Text('Kullanıcı bilgileri alınamadı')),
                      );
                      return;
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.work),
                  label: Text(_isApplied ? 'Başvuruyu Geri Çek' : 'İşe Başvur'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _toggleApplication,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}.${date.month}.${date.year}';
  }
}

extension JobColorExtension on Job {
  List<Color> get gradient {
    switch (category.toLowerCase()) {
      case 'temizlik':
        return [Colors.blue, Colors.blue.shade700];
      case 'tamir':
        return [Colors.orange, Colors.orange.shade700];
      case 'bakım':
        return [Colors.green, Colors.green.shade700];
      default:
        return [Colors.purple, Colors.purple.shade700];
    }
  }
}
