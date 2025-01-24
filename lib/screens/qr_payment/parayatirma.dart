import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:myapp/model/user_model.dart';

class DepositConfig {
  // Güvenlik ayarları
  static const double MIN_DEPOSIT_AMOUNT = 10.0; // En az 10 TL
  static const double MAX_DAILY_DEPOSIT = 5000.0; // Günlük maks 5000 TL
  static const double MAX_SINGLE_DEPOSIT = 2000.0; // Tek seferde maks 2000 TL
}

class DepositScreen extends StatefulWidget {
  const DepositScreen({super.key});

  @override
  _DepositScreenState createState() => _DepositScreenState();
}

class _DepositScreenState extends State<DepositScreen> {
  final TextEditingController _amountController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isLoading = false;
  double _currentBalance = 0.0;
  String _errorMessage = '';
  double _dailyTotalDeposit = 0.0;
  String _userName = '';
  String _userEmail = '';

  @override
  void initState() {
    super.initState();
    _fetchUserDataAndDailyDeposits();
  }

  Future<void> _fetchUserDataAndDailyDeposits() async {
    try {
      User? currentUser = _auth.currentUser;

      if (currentUser == null) {
        setState(() {
          _errorMessage = 'Lütfen önce giriş yapın';
        });
        return;
      }

      // Kullanıcı bilgilerini al
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(currentUser.uid).get();

      if (userDoc.exists) {
        Map<String, dynamic>? userData =
            userDoc.data() as Map<String, dynamic>?;
        if (userData != null) {
          UserModel user = UserModel.fromMap(userData);
          setState(() {
            _userName = user.username;
            _userEmail = user.email ?? '';
          });
        }
      }

      // Kullanıcı bakiyesini al
      DocumentSnapshot balanceDoc =
          await _firestore.collection('balances').doc(currentUser.uid).get();

      setState(() {
        _currentBalance = balanceDoc.exists
            ? (balanceDoc.data() as Map<String, dynamic>)['amount']
                    as double? ??
                0.0
            : 0.0;
      });

      // Günlük toplam depozitoları hesapla
      DateTime now = DateTime.now();
      DateTime startOfDay = DateTime(now.year, now.month, now.day);
      DateTime endOfDay = startOfDay.add(const Duration(days: 1));

      // Deposits koleksiyonunun varlığını ve içeriğini kontrol et
      QuerySnapshot dailyDeposits = await _firestore
          .collection('deposits')
          .where('uid', isEqualTo: currentUser.uid)
          .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
          .where('timestamp', isLessThan: endOfDay)
          .get();

      // Eğer hiç depozito yoksa
      if (dailyDeposits.docs.isEmpty) {
        setState(() {
          _dailyTotalDeposit = 0.0;
        });
        return;
      }

      setState(() {
        _dailyTotalDeposit = dailyDeposits.docs.fold(0.0, (total, doc) {
          var data = doc.data() as Map<String, dynamic>?;
          return total + ((data?['amount'] as num?)?.toDouble() ?? 0.0);
        });
      });
    } catch (e) {
      print('Error fetching daily deposits: $e');
      setState(() {
        _errorMessage = 'İşlem yapılmamamış';
        _dailyTotalDeposit = 0.0;
      });
    }
  }

  void _depositMoney() async {
    if (_amountController.text.isEmpty) {
      _showErrorSnackBar('Lütfen bir tutar girin');
      return;
    }

    double? amount = double.tryParse(_amountController.text);

    if (amount == null) {
      _showErrorSnackBar('Geçerli bir tutar girin');
      return;
    }

    // Minimum ve maksimum tutar kontrolleri
    if (amount < DepositConfig.MIN_DEPOSIT_AMOUNT) {
      _showErrorSnackBar(
          'En az ${DepositConfig.MIN_DEPOSIT_AMOUNT} TL yatırabilirsiniz');
      return;
    }

    if (amount > DepositConfig.MAX_SINGLE_DEPOSIT) {
      _showErrorSnackBar(
          'Tek seferde maks ${DepositConfig.MAX_SINGLE_DEPOSIT} TL yatırabilirsiniz');
      return;
    }

    // Günlük limit kontrolü
    if (_dailyTotalDeposit + amount > DepositConfig.MAX_DAILY_DEPOSIT) {
      _showErrorSnackBar('Günlük para yatırma limitini aştınız. '
          'Günlük toplam: ${_dailyTotalDeposit.toStringAsFixed(2)} TL, '
          'Kalan limit: ${(DepositConfig.MAX_DAILY_DEPOSIT - _dailyTotalDeposit).toStringAsFixed(2)} TL');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      User? currentUser = _auth.currentUser;

      if (currentUser == null) {
        throw Exception('Kullanıcı oturumu açık değil');
      }

      // Yeni depozito kaydını oluştur
      await _firestore.collection('deposits').add({
        'uid': currentUser.uid,
        'amount': amount,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'completed',
        'method': 'direct_deposit'
      });

      // Kullanıcı bakiyesini güncelle
      await _firestore.collection('balances').doc(currentUser.uid).set({
        'uid': currentUser.uid,
        'amount': FieldValue.increment(amount),
        'updatedAt': FieldValue.serverTimestamp()
      }, SetOptions(merge: true));

      await _firestore.collection('transaction_logs').add({
        'uid': currentUser.uid,
        'type': 'deposit',
        'amount': amount,
        'timestamp': FieldValue.serverTimestamp(),
        'ip_address': '127.0.0.1' // Statik IP adresi
      });

      // Yerel state'i güncelle
      setState(() {
        _currentBalance += amount;
        _dailyTotalDeposit += amount;
        _isLoading = false;
      });

      _showSuccessSnackBar('Para başarıyla yatırıldı');
      _amountController.clear();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('İşlem gerçekleştirilemedi: $e');
      print('Para yatırma hatası: $e');
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 3),
    ));
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: Colors.green,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Güvenli Para Yatırma'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_errorMessage.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.red[100],
                    borderRadius: BorderRadius.circular(5)),
                child: Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            Text(
              'Merhaba, $_userName ($_userEmail)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Mevcut Bakiye: ${_currentBalance.toStringAsFixed(2)} TL',
              style: const TextStyle(fontSize: 16, color: Colors.blue),
            ),
            const SizedBox(height: 10),
            Text(
              'Günlük Toplam Depozito: ${_dailyTotalDeposit.toStringAsFixed(2)} TL',
              style: const TextStyle(fontSize: 16, color: Colors.blue),
            ),
            const SizedBox(height: 20),
            const Text(
              'Günlük Maks Yatırma: ${DepositConfig.MAX_DAILY_DEPOSIT} TL\n'
              'Tek Seferde Maks Yatırma: ${DepositConfig.MAX_SINGLE_DEPOSIT} TL\n'
              'Minimum Yatırma: ${DepositConfig.MIN_DEPOSIT_AMOUNT} TL',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Yatırmak İstediğiniz Tutar',
                hintText: 'Tutarı girin',
                border: OutlineInputBorder(),
                prefixText: '₺ ',
              ),
            ),
            const SizedBox(height: 20),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _depositMoney,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text('Para Yatır'),
                  ),
          ],
        ),
      ),
    );
  }
}
