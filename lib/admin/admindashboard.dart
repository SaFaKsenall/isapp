import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:myapp/model/user_model.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:myapp/model/job_and_rivevws.dart';
import 'dart:math';
import 'package:myapp/admin/support_tickets_page.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  _AdminDashboardState createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<UserModel> _users = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedRole = 'all';
  bool _showDisabledAccounts = false;
  double _totalMoneyFlow = 0.0;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _jobPosts = [];
  List<Map<String, dynamic>> _reviews = [];
  List<Map<String, dynamic>> _supportTickets = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _loadTransactions();
    _loadJobPosts();
    _loadReviews();
    _loadSupportTickets();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      QuerySnapshot userSnapshot = await _firestore.collection('users').get();

      _users = userSnapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['uid'] = doc.id;
        return UserModel.fromMap(data);
      }).toList();

      setState(() => _isLoading = false);
    } catch (e) {
      print('Kullanıcılar yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  List<UserModel> get filteredUsers {
    return _users.where((user) {
      bool matchesSearch =
          user.username.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (user.email?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
                  false);

      bool matchesRole = _selectedRole == 'all' || user.role == _selectedRole;

      bool matchesStatus =
          _showDisabledAccounts ? !user.isActive : user.isActive;

      return matchesSearch && matchesRole && matchesStatus;
    }).toList();
  }

  Future<void> _updateUserRole(String uid, String newRole) async {
    try {
      await _firestore.collection('users').doc(uid).update({'role': newRole});
      await _loadUsers();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kullanıcı rolü güncellendi')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  Future<void> _toggleUserStatus(String uid, bool currentStatus) async {
    try {
      // Sadece Firestore'da kullanıcı durumunu güncelle
      await _firestore
          .collection('users')
          .doc(uid)
          .update({'isActive': !currentStatus});

      await _loadUsers(); // Kullanıcı listesini yenile

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(currentStatus
              ? 'Hesap devre dışı bırakıldı'
              : 'Hesap aktifleştirildi'),
          backgroundColor: currentStatus ? Colors.red : Colors.green,
        ),
      );
    } catch (e) {
      print('Hesap durumu güncellenirken hata: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteUser(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).delete();
      await _loadUsers();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kullanıcı silindi')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e')),
      );
    }
  }

  Future<void> _loadTransactions() async {
    try {
      QuerySnapshot transactionSnapshot = await _firestore
          .collection('transactions')
          .orderBy('timestamp', descending: true)
          .get();

      _transactions = transactionSnapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        _totalMoneyFlow += (data['amount'] as num).toDouble();
        return {
          'id': doc.id,
          'senderId': data['senderId'],
          'receiverId': data['receiverId'],
          'amount': data['amount'],
          'timestamp': data['timestamp'],
          'senderName': '',
          'receiverName': '',
        };
      }).toList();

      // Kullanıcı isimlerini al
      for (var transaction in _transactions) {
        DocumentSnapshot senderDoc = await _firestore
            .collection('users')
            .doc(transaction['senderId'])
            .get();
        DocumentSnapshot receiverDoc = await _firestore
            .collection('users')
            .doc(transaction['receiverId'])
            .get();

        transaction['senderName'] =
            (senderDoc.data() as Map<String, dynamic>)['username'] ??
                'Silinmiş Kullanıcı';
        transaction['receiverName'] =
            (receiverDoc.data() as Map<String, dynamic>)['username'] ??
                'Silinmiş Kullanıcı';
      }

      setState(() {});
    } catch (e) {
      print('İşlemler yüklenirken hata: $e');
    }
  }

  Future<void> _loadJobPosts() async {
    try {
      QuerySnapshot jobSnapshot = await _firestore
          .collection('jobs')
          .orderBy('createdAt', descending: true)
          .get();

      _jobPosts = await Future.wait(jobSnapshot.docs.map((doc) async {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        Job job = Job.fromMap({
          ...data,
          'id': doc.id,
        });

        // İş sahibinin bilgilerini al
        DocumentSnapshot userDoc =
            await _firestore.collection('users').doc(job.employerId).get();

        return {
          'id': job.id,
          'title': job.jobName,
          'description': job.jobDescription,
          'price': job.jobPrice,
          'category': job.category,
          'employerId': job.employerId,
          'employerName':
              (userDoc.data() as Map<String, dynamic>?)?['username'] ??
                  'Silinmiş Kullanıcı',
          'timestamp': data['createdAt'] ?? Timestamp.now(),
          'likes': job.likes,
          'comments': job.comments,
          'status': job.status,
          'neighborhood': job.neighborhood,
        };
      }).toList());

      setState(() {});
      print('Yüklenen iş ilanı sayısı: ${_jobPosts.length}');
    } catch (e) {
      print('İş ilanları yüklenirken hata: $e');
    }
  }

  Future<void> _loadReviews() async {
    try {
      QuerySnapshot reviewSnapshot = await _firestore
          .collection('reviews')
          .orderBy('createdAt', descending: true)
          .get();

      _reviews = await Future.wait(reviewSnapshot.docs.map((doc) async {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        Review review = Review.fromMap(data);

        DocumentSnapshot reviewerDoc =
            await _firestore.collection('users').doc(review.reviewerId).get();
        DocumentSnapshot employerDoc =
            await _firestore.collection('users').doc(review.employerId).get();

        return {
          'id': doc.id,
          'rating': review.rating,
          'comment': review.comment,
          'reviewerId': review.reviewerId,
          'employerId': review.employerId,
          'reviewerName':
              (reviewerDoc.data() as Map<String, dynamic>?)?['username'] ??
                  'Silinmiş Kullanıcı',
          'employerName':
              (employerDoc.data() as Map<String, dynamic>?)?['username'] ??
                  'Silinmiş Kullanıcı',
          'timestamp': data['createdAt'] ?? Timestamp.now(),
          'status': review.status,
          'jobId': review.jobId,
        };
      }).toList());

      setState(() {});
      print('Yüklenen değerlendirme sayısı: ${_reviews.length}');
    } catch (e) {
      print('Değerlendirmeler yüklenirken hata: $e');
    }
  }

  Future<void> _loadSupportTickets() async {
    try {
      QuerySnapshot ticketSnapshot = await _firestore
          .collection('support_tickets')
          .orderBy('createdAt', descending: true)
          .get();

      _supportTickets = await Future.wait(ticketSnapshot.docs.map((doc) async {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

        // Kullanıcı bilgilerini al
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

      setState(() {});
    } catch (e) {
      print('Destek talepleri yüklenirken hata: $e');
    }
  }

  void _showUserActionDialog(UserModel user) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.blue.shade50, Colors.white],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Kullanıcı Profil Başlığı
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.blue.withOpacity(0.1),
                child: Icon(Icons.person, size: 40, color: Colors.blue),
              ).animate().scale(),

              SizedBox(height: 16),
              Text(
                user.username,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  foreground: Paint()
                    ..shader = LinearGradient(
                      colors: [Colors.blue, Colors.blue.shade900],
                    ).createShader(Rect.fromLTWH(0.0, 0.0, 200.0, 70.0)),
                ),
              ).animate().fadeIn().slideY(),

              Text(
                user.email ?? "E-posta belirtilmemiş",
                style: TextStyle(color: Colors.grey[600], fontSize: 16),
              ).animate().fadeIn().slideY(delay: Duration(milliseconds: 200)),

              SizedBox(height: 24),

              // Rol Seçimi
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kullanıcı Rolü',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                    ),
                    SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: ['user', 'wip', 'admin'].map((role) {
                        bool isSelected = user.role == role;
                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                isSelected ? Colors.blue : Colors.grey.shade200,
                            foregroundColor:
                                isSelected ? Colors.white : Colors.grey[800],
                            elevation: isSelected ? 8 : 0,
                            padding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            _updateUserRole(user.uid, role);
                            Navigator.pop(context);
                          },
                          child: Text(
                            role.toUpperCase(),
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(delay: Duration(milliseconds: 300)),

              SizedBox(height: 24),

              // Hesap Durumu ve Silme Butonları
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: Icon(
                        user.isActive ? Icons.block : Icons.check_circle,
                        color: Colors.white,
                      ),
                      label: Text(
                        user.isActive ? 'Devre Dışı Bırak' : 'Aktifleştir',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            user.isActive ? Colors.orange : Colors.green,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        _toggleUserStatus(user.uid, user.isActive);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ).animate().fadeIn().slideY(delay: Duration(milliseconds: 400)),

              SizedBox(height: 12),

              TextButton.icon(
                icon: Icon(Icons.delete_forever, color: Colors.red),
                label: Text(
                  'Hesabı Sil',
                  style:
                      TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _showDeleteConfirmationDialog(user, context),
              ).animate().fadeIn().slideY(delay: Duration(milliseconds: 500)),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmationDialog(UserModel user, [BuildContext? context]) {
    context ??= this.context;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Dikkat!').animate().fadeIn(),
        content: Text(
          '${user.username} kullanıcısını silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.',
        ).animate().fadeIn().slideY(),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('İptal'),
          ),
          ElevatedButton.icon(
            icon: Icon(Icons.delete_forever, color: Colors.white),
            label: Text('Sil', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              _deleteUser(user.uid);
              Navigator.pop(context);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Admin Paneli'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () {
              _loadUsers();
              _loadTransactions();
              _loadJobPosts();
              _loadReviews();
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Container(
                    height: 150, // DrawerHeader yüksekliğini azalttık
                    padding: EdgeInsets.only(top: 0), // Üst padding'i kaldırdık
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.blue.shade700, Colors.blue.shade900],
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: Colors.white.withOpacity(0.9),
                                child: Icon(
                                  Icons.admin_panel_settings,
                                  size: 35,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Admin Paneli',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Yönetici Kontrol Merkezi',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Menü Öğeleri
                  _buildAnimatedMenuItem(
                    icon: Icons.people,
                    title: 'Kullanıcılar',
                    count: _users.length,
                    color: Colors.blue,
                    delay: 500,
                    onTap: () => Navigator.pop(context),
                  ),

                  _buildAnimatedMenuItem(
                    icon: Icons.work,
                    title: 'İş İlanları',
                    count: _jobPosts.length,
                    color: Colors.green,
                    delay: 600,
                    onTap: () {
                      Navigator.pop(context);
                      _showJobPostsDialog();
                    },
                  ),

                  _buildAnimatedMenuItem(
                    icon: Icons.star,
                    title: 'Değerlendirmeler',
                    count: _reviews.length,
                    color: Colors.amber,
                    delay: 700,
                    onTap: () {
                      Navigator.pop(context);
                      _showReviewsDialog();
                    },
                  ),

                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.money, color: Colors.green),
                      ),
                      title: Text(
                        'Para Akışı',
                        style: TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        'Toplam: ₺${_totalMoneyFlow.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _showTransactionsDialog();
                      },
                    ),
                  )
                      .animate()
                      .fadeIn()
                      .slideX(delay: Duration(milliseconds: 800)),

                  Divider(color: Colors.blue.withOpacity(0.2), thickness: 1),

                  Container(
                    margin: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.red.shade400, Colors.red.shade700],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ListTile(
                      leading: Icon(Icons.logout, color: Colors.white),
                      title: Text(
                        'Çıkış Yap',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () async {
                        await FirebaseAuth.instance.signOut();
                        Navigator.of(context).pushReplacementNamed('/login');
                      },
                    ),
                  )
                      .animate()
                      .fadeIn()
                      .slideX(delay: Duration(milliseconds: 900)),

                  _buildAnimatedMenuItem(
                    icon: Icons.support_agent,
                    title: 'Destek Talepleri',
                    count: _supportTickets.length,
                    color: Colors.teal,
                    delay: 800,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => SupportTicketsPage()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Arama Alanı
                      TextField(
                        decoration: InputDecoration(
                          labelText: 'Kullanıcı Ara',
                          prefixIcon: Icon(Icons.search, color: Colors.blue),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.blue.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: Colors.blue, width: 2),
                          ),
                          filled: true,
                          fillColor: Colors.blue.shade50,
                        ),
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                      ).animate().fadeIn().slideX(),

                      SizedBox(height: 16),

                      // Filtreler
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _selectedRole,
                              decoration: InputDecoration(
                                labelText: 'Rol Filtrele',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                              ),
                              items: [
                                DropdownMenuItem(
                                    value: 'all', child: Text('Tümü')),
                                DropdownMenuItem(
                                    value: 'user', child: Text('Kullanıcı')),
                                DropdownMenuItem(
                                    value: 'wip', child: Text('WIP')),
                                DropdownMenuItem(
                                    value: 'admin', child: Text('Admin')),
                              ],
                              onChanged: (value) =>
                                  setState(() => _selectedRole = value!),
                            ),
                          )
                              .animate()
                              .fadeIn()
                              .slideX(delay: Duration(milliseconds: 100)),
                          SizedBox(width: 16),
                          FilterChip(
                            label: Text(
                              'Devre Dışı Hesaplar',
                              style: TextStyle(
                                color: _showDisabledAccounts
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                            selected: _showDisabledAccounts,
                            selectedColor: Colors.blue,
                            checkmarkColor: Colors.white,
                            onSelected: (value) =>
                                setState(() => _showDisabledAccounts = value),
                          )
                              .animate()
                              .fadeIn()
                              .slideX(delay: Duration(milliseconds: 200)),
                        ],
                      ),
                    ],
                  ),
                ).animate().fadeIn().slideY(),

                SizedBox(height: 16),

                // Kullanıcı Listesi
                Expanded(
                  child: ListView.builder(
                    itemCount: filteredUsers.length,
                    itemBuilder: (context, index) {
                      final user = filteredUsers[index];
                      return Card(
                        margin:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.all(12),
                          leading: Hero(
                            tag: 'profile-${user.uid}',
                            child: CircleAvatar(
                              radius: 30,
                              backgroundColor: Colors.blue.shade100,
                              backgroundImage: user.profileImageUrl != null
                                  ? NetworkImage(user.profileImageUrl!)
                                  : null,
                              child: user.profileImageUrl == null
                                  ? Icon(Icons.person,
                                      color: Colors.blue.shade700)
                                  : null,
                            ),
                          ),
                          title: Text(
                            user.username,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.email ?? 'E-posta yok',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              Container(
                                margin: EdgeInsets.only(top: 4),
                                padding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color:
                                      _getRoleColor(user.role).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Rol: ${user.role ?? "Belirtilmemiş"}',
                                  style: TextStyle(
                                    color: _getRoleColor(user.role),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: user.isActive
                                      ? Colors.green.shade50
                                      : Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  user.isActive
                                      ? Icons.check_circle
                                      : Icons.block,
                                  color:
                                      user.isActive ? Colors.green : Colors.red,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.message, color: Colors.blue),
                                onPressed: () => _showMessageDialog(user),
                                tooltip: 'Mesaj Gönder',
                              ),
                              IconButton(
                                icon: Icon(Icons.more_vert, color: Colors.blue),
                                onPressed: () => _showUserActionDialog(user),
                              ),
                            ],
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(delay: Duration(milliseconds: 100 * index))
                          .slideX();
                    },
                  ),
                ),
              ],
            ),
    );
  }

  void _showJobPostsDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.blue.shade50, Colors.white],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'İş İlanları',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      foreground: Paint()
                        ..shader = LinearGradient(
                          colors: [Colors.blue, Colors.blue.shade900],
                        ).createShader(Rect.fromLTWH(0.0, 0.0, 200.0, 70.0)),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.refresh),
                        onPressed: _loadJobPosts,
                      ),
                      IconButton(
                        icon: Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ).animate().fadeIn().slideX(),
              Divider(thickness: 2),
              Text(
                'Toplam ${_jobPosts.length} İlan',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
              ).animate().fadeIn(),
              SizedBox(height: 16),
              Expanded(
                child: _jobPosts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.work_off, size: 64, color: Colors.grey)
                                .animate()
                                .fadeIn()
                                .scale(),
                            SizedBox(height: 16),
                            Text(
                              'Henüz iş ilanı yok',
                              style:
                                  TextStyle(fontSize: 18, color: Colors.grey),
                            ).animate().fadeIn(),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _jobPosts.length,
                        itemBuilder: (context, index) {
                          final job = _jobPosts[index];
                          return Card(
                            elevation: 4,
                            margin: EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white,
                                    job['status'] == 'active'
                                        ? Colors.green.withOpacity(0.1)
                                        : Colors.red.withOpacity(0.1),
                                  ],
                                ),
                              ),
                              child: ListTile(
                                contentPadding: EdgeInsets.all(16),
                                title: Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child:
                                          Icon(Icons.work, color: Colors.blue),
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            job['title'],
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                          ),
                                          Text(
                                            job['category'],
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(height: 8),
                                    Text(
                                      job['description'],
                                      style: TextStyle(fontSize: 16),
                                    ),
                                    SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                Colors.green.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            '₺${job['price']}',
                                            style: TextStyle(
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            Icon(Icons.thumb_up,
                                                size: 16, color: Colors.blue),
                                            Text(' ${job['likes']} '),
                                            Icon(Icons.comment,
                                                size: 16, color: Colors.orange),
                                            Text(' ${job['comments']}'),
                                          ],
                                        ),
                                      ],
                                    ),
                                    if (job['neighborhood'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Row(
                                          children: [
                                            Icon(Icons.location_on,
                                                size: 16, color: Colors.red),
                                            SizedBox(width: 4),
                                            Text(
                                              job['neighborhood'],
                                              style: TextStyle(
                                                  color: Colors.grey[600]),
                                            ),
                                          ],
                                        ),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'İlan Sahibi: ${job['employerName']}',
                                            style: TextStyle(
                                              fontStyle: FontStyle.italic,
                                              color: Colors.blue,
                                            ),
                                          ),
                                          Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: job['status'] == 'active'
                                                  ? Colors.green
                                                      .withOpacity(0.1)
                                                  : Colors.red.withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              job['status'] == 'active'
                                                  ? 'Aktif'
                                                  : 'Pasif',
                                              style: TextStyle(
                                                color: job['status'] == 'active'
                                                    ? Colors.green
                                                    : Colors.red,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                              .animate()
                              .fadeIn(duration: Duration(milliseconds: 500))
                              .slideX(duration: Duration(milliseconds: 300));
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReviewsDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.amber.shade50, Colors.white],
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star_rounded, color: Colors.amber, size: 32),
                  SizedBox(width: 12),
                  Text(
                    'Değerlendirmeler',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      foreground: Paint()
                        ..shader = LinearGradient(
                          colors: [
                            Colors.amber.shade700,
                            Colors.amber.shade900
                          ],
                        ).createShader(Rect.fromLTWH(0.0, 0.0, 200.0, 70.0)),
                    ),
                  ),
                ],
              ).animate().fadeIn().slideY(),
              SizedBox(height: 24),
              Expanded(
                child: _reviews.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.rate_review_outlined,
                                size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'Henüz değerlendirme yok',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ).animate().fadeIn().scale(),
                      )
                    : ListView.builder(
                        itemCount: _reviews.length,
                        itemBuilder: (context, index) {
                          final review = _reviews[index];
                          return Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            margin: EdgeInsets.symmetric(vertical: 8),
                            child: Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Colors.white, Colors.amber.shade50],
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Colors.amber.shade100,
                                        child: Icon(Icons.person,
                                            color: Colors.amber.shade700),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${review['reviewerName']}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            Text(
                                              '→ ${review['employerName']}',
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade100,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '${review['rating']}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.amber.shade900,
                                              ),
                                            ),
                                            SizedBox(width: 4),
                                            Icon(Icons.star,
                                                color: Colors.amber, size: 16),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 12),
                                  Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.amber.shade200,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      review['comment'],
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[800],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                              .animate()
                              .fadeIn(
                                  delay: Duration(milliseconds: 100 * index))
                              .slideX();
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTransactionsDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.8,
          padding: EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.green.shade50, Colors.white],
            ),
          ),
          child: Column(
            children: [
              // Başlık Kısmı
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.1),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.account_balance,
                            color: Colors.green.shade700, size: 32),
                        SizedBox(width: 12),
                        Text(
                          'Para Transferleri',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            foreground: Paint()
                              ..shader = LinearGradient(
                                colors: [
                                  Colors.green.shade700,
                                  Colors.green.shade900
                                ],
                              ).createShader(
                                  Rect.fromLTWH(0.0, 0.0, 200.0, 70.0)),
                          ),
                        ),
                      ],
                    ).animate().fadeIn().slideY(),
                    SizedBox(height: 16),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.green.shade100, Colors.green.shade50],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.attach_money,
                              color: Colors.green.shade700),
                          Text(
                            'Toplam Akış: ₺${_totalMoneyFlow.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                    )
                        .animate()
                        .fadeIn()
                        .scale(delay: Duration(milliseconds: 200)),
                  ],
                ),
              ),

              SizedBox(height: 24),

              // Transfer Listesi
              Expanded(
                child: _transactions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.money_off,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Henüz transfer yok',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ).animate().fadeIn().scale(),
                      )
                    : ListView.builder(
                        itemCount: _transactions.length,
                        itemBuilder: (context, index) {
                          final transaction = _transactions[index];
                          return Card(
                            margin: EdgeInsets.symmetric(vertical: 8),
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [Colors.white, Colors.green.shade50],
                                ),
                              ),
                              child: ListTile(
                                contentPadding: EdgeInsets.all(16),
                                leading: CircleAvatar(
                                  backgroundColor: Colors.green.shade100,
                                  child: Icon(
                                    Icons.swap_horiz,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                                title: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: RichText(
                                            text: TextSpan(
                                              style: TextStyle(
                                                  color: Colors.black),
                                              children: [
                                                TextSpan(
                                                  text:
                                                      transaction['senderName'],
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        Colors.green.shade700,
                                                  ),
                                                ),
                                                TextSpan(text: ' → '),
                                                TextSpan(
                                                  text: transaction[
                                                      'receiverName'],
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        Colors.green.shade900,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade100,
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            '₺${(transaction['amount'] as num).toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: Colors.green.shade700,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        size: 16,
                                        color: Colors.grey.shade600,
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        DateFormat('dd/MM/yyyy HH:mm').format(
                                          (transaction['timestamp']
                                                  as Timestamp)
                                              .toDate(),
                                        ),
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                              .animate()
                              .fadeIn(
                                  delay: Duration(milliseconds: 100 * index))
                              .slideX();
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUserManagementDialog(UserModel user) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor:
                    Theme.of(context).primaryColor.withOpacity(0.1),
                child: Icon(
                  Icons.person,
                  size: 40,
                  color: Theme.of(context).primaryColor,
                ),
              ).animate().scale(),
              SizedBox(height: 16),
              Text(
                user.username,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ).animate().fadeIn().slideY(),
              Text(
                user.email ?? 'E-posta yok',
                style: TextStyle(color: Colors.grey[600]),
              ).animate().fadeIn().slideY(delay: Duration(milliseconds: 100)),
              SizedBox(height: 24),
              // Rol Değiştirme
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey[100],
                ),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kullanıcı Rolü',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: ['user', 'admin'].map((role) {
                        bool isSelected = user.role == role;
                        return ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isSelected
                                ? Theme.of(context).primaryColor
                                : Colors.grey[300],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => _updateUserRole(user.uid, role),
                          child: Text(
                            role.toUpperCase(),
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.black,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(delay: Duration(milliseconds: 200)),
              SizedBox(height: 16),
              // Hesap Durumu
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: Icon(
                          user.isActive ? Icons.block : Icons.check_circle),
                      label: Text(user.isActive
                          ? 'Hesabı Dondur'
                          : 'Hesabı Aktifleştir'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            user.isActive ? Colors.red : Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () =>
                          _toggleUserStatus(user.uid, user.isActive),
                    ),
                  ),
                ],
              ).animate().fadeIn().slideY(delay: Duration(milliseconds: 300)),
              SizedBox(height: 8),
              // Hesabı Sil
              TextButton.icon(
                icon: Icon(Icons.delete_forever, color: Colors.red),
                label: Text('Hesabı Sil', style: TextStyle(color: Colors.red)),
                onPressed: () {
                  Navigator.pop(context);
                  _showDeleteConfirmationDialog(user, context);
                },
              ).animate().fadeIn().slideY(delay: Duration(milliseconds: 400)),
              SizedBox(height: 8),
              // Mesaj Gönder butonu ekle
              ElevatedButton.icon(
                icon: Icon(Icons.message),
                label: Text('Mesaj Gönder'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context); // Mevcut dialogu kapat
                  _showMessageDialog(user);
                },
              ).animate().fadeIn().slideY(delay: Duration(milliseconds: 350)),
            ],
          ),
        ),
      ),
    );
  }

  // Yeni mesaj gönderme dialog metodu
  void _showMessageDialog(UserModel user) {
    final TextEditingController messageController = TextEditingController();
    final TextEditingController subjectController = TextEditingController();
    String selectedTemplate = 'custom'; // Varsayılan şablon

    // HTML şablonlarını tutan map
    final Map<String, String> emailTemplates = {
      'resetpassword': '''
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f9f9f9;">
          <div style="background-color: #007bff; padding: 20px; border-radius: 10px 10px 0 0; text-align: center;">
            <h1 style="color: white; margin: 0;">Şifre Sıfırlama</h1>
          </div>
          <div style="background-color: white; padding: 20px; border-radius: 0 0 10px 10px; box-shadow: 0 2px 5px rgba(0,0,0,0.1);">
            <p>Merhaba ${user.username},</p>
            <p>Şifrenizi sıfırlamak için aşağıdaki butona tıklayabilirsiniz:</p>
            <div style="text-align: center; margin: 30px 0;">
              <a href="https://iskayyapp.com/reset-password?uid=${user.uid}" style="background-color: #007bff; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; font-weight: bold;">Şifremi Sıfırla</a>
            </div>
            <p style="color: #666; font-size: 14px;">Bu e-postayı talep etmediyseniz, lütfen dikkate almayınız.</p>
          </div>
          <div style="text-align: center; margin-top: 20px; color: #666;">
            <p>© 2024 İşKay. Tüm hakları saklıdır.</p>
          </div>
        </div>
      ''',
      'activateaccount': '''
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f9f9f9;">
          <div style="background-color: #28a745; padding: 20px; border-radius: 10px 10px 0 0; text-align: center;">
            <h1 style="color: white; margin: 0;">Hesap Aktivasyonu</h1>
          </div>
          <div style="background-color: white; padding: 20px; border-radius: 0 0 10px 10px; box-shadow: 0 2px 5px rgba(0,0,0,0.1);">
            <p>Merhaba ${user.username},</p>
            <p>Hesabınız şu anda devre dışı durumda. Hesabınızı aktifleştirmek için lütfen İşKay uygulamasını açın ve aşağıdaki kodu girin:</p>
            <div style="text-align: center; margin: 30px 0;">
              <div style="background-color: #f8f9fa; padding: 15px; border-radius: 8px; border: 2px dashed #28a745; display: inline-block;">
                <span style="font-size: 24px; font-weight: bold; letter-spacing: 3px; color: #28a745;" id="activation-code">CODE_PLACEHOLDER</span>
              </div>
              <div style="margin-top: 10px;">
                <button onclick="navigator.clipboard.writeText(document.getElementById('activation-code').textContent)" style="background: none; border: none; color: #28a745; cursor: pointer; text-decoration: underline;">
                  Kodu Kopyala
                </button>
              </div>
            </div>
            <p>Ya da yöneticinizle iletişime geçerek hesabınızın aktifleştirilmesini talep edebilirsiniz.</p>
            <p style="color: #666; font-size: 14px;">Güvenliğiniz için bu e-postayı kimseyle paylaşmayın.</p>
          </div>
          <div style="text-align: center; margin-top: 20px; color: #666;">
            <p>© 2024 İşKay. Tüm hakları saklıdır.</p>
          </div>
        </div>
      ''',
      'welcome': '''
        <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; background-color: #f9f9f9;">
          <div style="background-color: #6f42c1; padding: 20px; border-radius: 10px 10px 0 0; text-align: center;">
            <h1 style="color: white; margin: 0;">İşKay'a Hoş Geldiniz!</h1>
          </div>
          <div style="background-color: white; padding: 20px; border-radius: 0 0 10px 10px; box-shadow: 0 2px 5px rgba(0,0,0,0.1);">
            <p>Merhaba ${user.username},</p>
            <p>İşKay ailesine hoş geldiniz! Size platformumuzun özelliklerini tanıtmak isteriz:</p>
            <ul style="list-style-type: none; padding: 0;">
              <li style="margin: 10px 0; padding-left: 20px; position: relative;">
                <span style="color: #6f42c1; position: absolute; left: 0;">✓</span>
                İş ilanları oluşturma ve başvurma
              </li>
              <li style="margin: 10px 0; padding-left: 20px; position: relative;">
                <span style="color: #6f42c1; position: absolute; left: 0;">✓</span>
                Güvenli ödeme sistemi
              </li>
              <li style="margin: 10px 0; padding-left: 20px; position: relative;">
                <span style="color: #6f42c1; position: absolute; left: 0;">✓</span>
                Değerlendirme sistemi
              </li>
            </ul>
            <div style="text-align: center; margin: 30px 0;">
              <a href="https://iskayyapp.com/tutorial" style="background-color: #6f42c1; color: white; padding: 12px 30px; text-decoration: none; border-radius: 5px; font-weight: bold;">Başlangıç Rehberini İncele</a>
            </div>
          </div>
          <div style="text-align: center; margin-top: 20px; color: #666;">
            <p>© 2024 İşKay. Tüm hakları saklıdır.</p>
          </div>
        </div>
      '''
    };

    // Konu değiştiğinde şablonu güncelle
    void updateTemplate(String template) {
      setState(() {
        if (emailTemplates.containsKey(template)) {
          selectedTemplate = template;
          messageController.text = emailTemplates[template]!;
          // Konu başlığını da güncelle
          switch (template) {
            case 'welcome':
              subjectController.text = 'İşKay\'a Hoş Geldiniz!';
              break;
            case 'resetpassword':
              subjectController.text = 'Şifre Sıfırlama Talebi';
              break;
            case 'activateaccount':
              subjectController.text = 'Hesap Aktivasyonu';
              break;
          }
        } else {
          selectedTemplate = 'custom';
        }
      });
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${user.username} kullanıcısına mesaj gönder',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              TextField(
                controller: subjectController,
                decoration: InputDecoration(
                  hintText:
                      'E-posta Konusu (/ yazarak şablonları görüntüleyin)',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  suffixIcon: subjectController.text.startsWith('/')
                      ? PopupMenuButton<String>(
                          icon: Icon(Icons.arrow_drop_down),
                          onSelected: (String template) {
                            updateTemplate(template);
                          },
                          itemBuilder: (BuildContext context) {
                            return emailTemplates.keys.map((String template) {
                              String displayName = template.toUpperCase();
                              String description = '';

                              // Her şablon için açıklama ekle
                              switch (template) {
                                case 'welcome':
                                  description = 'Hoş geldiniz e-postası';
                                  break;
                                case 'resetpassword':
                                  description = 'Şifre sıfırlama e-postası';
                                  break;
                                case 'activateaccount':
                                  description = 'Hesap aktivasyon e-postası';
                                  break;
                              }

                              return PopupMenuItem<String>(
                                value: template,
                                child: ListTile(
                                  title: Text(displayName),
                                  subtitle: Text(description),
                                  leading: Icon(_getTemplateIcon(template)),
                                ),
                              );
                            }).toList();
                          },
                        )
                      : null,
                ),
                onChanged: (value) {
                  setState(() {
                    if (value.startsWith('/')) {
                      // Otomatik popup menüyü tetikle
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        // Popup menüyü programatik olarak aç
                        final RenderBox button =
                            context.findRenderObject() as RenderBox;
                        final RenderBox overlay = Overlay.of(context)
                            .context
                            .findRenderObject() as RenderBox;
                        final RelativeRect position = RelativeRect.fromRect(
                          Rect.fromPoints(
                            button.localToGlobal(Offset.zero,
                                ancestor: overlay),
                            button.localToGlobal(
                                button.size.bottomRight(Offset.zero),
                                ancestor: overlay),
                          ),
                          Offset.zero & overlay.size,
                        );
                        showMenu(
                          context: context,
                          position: position,
                          items: emailTemplates.keys.map((String template) {
                            String displayName = template.toUpperCase();
                            String description = '';

                            switch (template) {
                              case 'welcome':
                                description = 'Hoş geldiniz e-postası';
                                break;
                              case 'resetpassword':
                                description = 'Şifre sıfırlama e-postası';
                                break;
                              case 'activateaccount':
                                description = 'Hesap aktivasyon e-postası';
                                break;
                            }

                            return PopupMenuItem<String>(
                              value: template,
                              child: ListTile(
                                title: Text(displayName),
                                subtitle: Text(description),
                                leading: Icon(_getTemplateIcon(template)),
                              ),
                            );
                          }).toList(),
                        ).then((selected) {
                          if (selected != null) {
                            subjectController.text = selected;
                            updateTemplate(selected);
                          }
                        });
                      });
                    }
                  });
                },
              ),
              SizedBox(height: 16),
              TextField(
                controller: messageController,
                maxLines: 8,
                decoration: InputDecoration(
                  hintText: 'HTML formatında mesajınızı yazın...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
              SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('İptal'),
                  ),
                  SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      if (messageController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Lütfen bir mesaj yazın')),
                        );
                        return;
                      }

                      try {
                        final currentUser = FirebaseAuth.instance.currentUser;
                        if (currentUser == null)
                          throw Exception('Kullanıcı oturumu bulunamadı');

                        String username = 'jewelkaan01@gmail.com';
                        String password = 'pxaj buxl ddmd unio';
                        final smtpServer = gmail(username, password);

                        // Aktivasyon kodu e-postası için özel işlem
                        if (selectedTemplate == 'activateaccount') {
                          final activationCode = _generateActivationCode();
                          final updatedEmailContent = messageController.text
                              .replaceAll('CODE_PLACEHOLDER', activationCode);

                          final emailMessage = Message()
                            ..from = Address(username, 'İşKay Destek')
                            ..recipients.add(user.email!)
                            ..subject = subjectController.text
                            ..html = '''
                              <script>
                              function copyToClipboard(text) {
                                const textarea = document.createElement('textarea');
                                textarea.value = text;
                                document.body.appendChild(textarea);
                                textarea.select();
                                document.execCommand('copy');
                                document.body.removeChild(textarea);
                                alert('Kod kopyalandı: ' + text);
                              }
                              </script>
                              $updatedEmailContent
                            ''';

                          await send(emailMessage, smtpServer);

                          // Firebase'e aktivasyon kodunu kaydet
                          await _firestore
                              .collection('activation_codes')
                              .doc(user.uid)
                              .set({
                            'code': activationCode,
                            'createdAt': FieldValue.serverTimestamp(),
                            'isUsed': false,
                            'expiresAt': Timestamp.fromDate(
                                DateTime.now().add(Duration(hours: 24))),
                          });
                        } else {
                          // Normal e-posta gönderimi
                          final emailMessage = Message()
                            ..from = Address(username, 'İşKay Destek')
                            ..recipients.add(user.email!)
                            ..subject = subjectController.text
                            ..html = messageController.text;

                          await send(emailMessage, smtpServer);
                        }

                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('E-posta başarıyla gönderildi')),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Hata: $e')),
                        );
                      }
                    },
                    child: Text('Gönder'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Rol renklerini belirleyen yardımcı fonksiyon
  Color _getRoleColor(String? role) {
    switch (role) {
      case 'admin':
        return Colors.purple;
      case 'wip':
        return Colors.orange;
      case 'user':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  // Yardımcı widget
  Widget _buildAnimatedMenuItem({
    required IconData icon,
    required String title,
    required int count,
    required Color color,
    required int delay,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ListTile(
        leading: Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: TextStyle(fontSize: 14),
        ),
        trailing: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        onTap: onTap,
      ),
    ).animate().fadeIn().slideX(delay: Duration(milliseconds: delay));
  }

  // Aktivasyon kodu oluşturma fonksiyonu
  String _generateActivationCode() {
    const chars =
        '23456789ABCDEFGHJKLMNPQRSTUVWXYZ'; // Karışıklığı önlemek için 0,1,I,O çıkarıldı
    final random = Random();
    return List.generate(6, (index) => chars[random.nextInt(chars.length)])
        .join();
  }

  // Şablon ikonlarını belirlemek için yardımcı fonksiyon
  IconData _getTemplateIcon(String template) {
    switch (template) {
      case 'welcome':
        return Icons.waving_hand;
      case 'resetpassword':
        return Icons.lock_reset;
      case 'activateaccount':
        return Icons.verified_user;
      default:
        return Icons.email;
    }
  }

  void _showSupportTicketsDialog() {
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
              Text(
                'Destek Talepleri',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 20),
              Expanded(
                child: ListView.builder(
                  itemCount: _supportTickets.length,
                  itemBuilder: (context, index) {
                    final ticket = _supportTickets[index];
                    return Card(
                      margin: EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        title: Text(ticket['username']),
                        subtitle: Text('Talep ID: ${ticket['id']}'),
                        trailing: Chip(
                          label: Text(ticket['status']),
                          backgroundColor: ticket['status'] == 'pending'
                              ? Colors.orange
                              : Colors.green,
                        ),
                        onTap: () => _showTicketDetails(ticket),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTicketDetails(Map<String, dynamic> ticket) {
    // Burada destek talebi detaylarını ve mesajlaşma arayüzünü gösterebilirsiniz
    // TODO: Implement ticket details dialog
  }
}
