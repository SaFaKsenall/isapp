import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:myapp/screens/qr_payment/parayatirma.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReferralQRCodePage extends StatefulWidget {
  const ReferralQRCodePage({super.key});

  @override
  _ReferralQRCodePageState createState() => _ReferralQRCodePageState();
}

class _ReferralQRCodePageState extends State<ReferralQRCodePage> {
  String _referralCode = '';
  bool _isInitialized = false;
  late SharedPreferences _prefs;
  final String _codeKey = 'referral_code_cache';

  @override
  void initState() {
    super.initState();
    _quickInit();
  }

  Future<void> _quickInit() async {
    // Önce cache'den yükle
    await _loadCachedCode();

    // Arka planda Firestore'dan yükle
    _fetchReferralCode();
  }

  Future<void> _loadCachedCode() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final cachedCode = _prefs.getString(_codeKey);

      if (cachedCode != null && mounted) {
        setState(() {
          _referralCode = cachedCode;
          _isInitialized = true;
        });
      }
    } catch (e) {
      print('Cache yükleme hatası: $e');
    }
  }

  Future<void> _fetchReferralCode() async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();

        if (userDoc.exists) {
          final code = userDoc['referralCode'] ?? '';

          // Cache'i güncelle
          await _prefs.setString(_codeKey, code);

          if (mounted && code != _referralCode) {
            setState(() {
              _referralCode = code;
              _isInitialized = true;
            });
          }
        }
      }
    } catch (e) {
      print('Referans kodu yükleme hatası: $e');
    }
  }

  void _scanQRCode() {
    final TextEditingController amountController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Para Gönderme'),
          content: TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Gönderilecek tutarı giriniz (Min. 10 TL)',
              suffixText: 'TL',
              border: OutlineInputBorder(),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () {
                // Validate input
                String input = amountController.text.trim();
                if (input.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Lütfen bir tutar girin'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                int amount = int.parse(input);
                if (amount < 10) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('En az 10 TL gönderebilirsiniz'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Close the dialog and open QR scanner
                Navigator.of(context).pop();
                _openQRScanner(amount);
              },
              child: const Text('Devam Et'),
            ),
          ],
        );
      },
    );
  }

  void _openQRScanner(int amount) {
    final mobileScannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text('QR Kodu Tarayın'),
              centerTitle: true,
            ),
            body: Stack(
              children: [
                MobileScanner(
                  controller: mobileScannerController,
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      if (barcode.rawValue != null) {
                        // Dispose the controller before popping
                        mobileScannerController.dispose();
                        Navigator.pop(context);
                        _handleScannedReferralCode(barcode.rawValue!, amount);
                      }
                    }
                  },
                ),
                Center(
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withOpacity(0.7),
                        width: 2.0,
                      ),
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          spreadRadius: 1,
                          blurRadius: 8,
                        )
                      ],
                    ),
                  ),
                ),
                const Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      'QR Kodu Tarayıcı Alanının İçine Yerleştirin',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        )).then((_) {
      // Safely dispose the controller
      mobileScannerController.dispose();
    });
  }

  Future<void> _handleScannedReferralCode(
      String scannedCode, int amount) async {
    try {
      User? currentUser = FirebaseAuth.instance.currentUser;

      // Kullanıcı girişi kontrolü
      if (currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kullanıcı girişi yapılmamış'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Kendi referans koduna transfer engelleme
      DocumentSnapshot currentUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (currentUserDoc.exists &&
          currentUserDoc['referralCode'] == scannedCode) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kendi referans kodunuza para gönderemezsiniz'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Hedef kullanıcı kontrolü
      QuerySnapshot referralCheck = await FirebaseFirestore.instance
          .collection('users')
          .where('referralCode', isEqualTo: scannedCode)
          .limit(1)
          .get();

      if (referralCheck.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Geçersiz referans kodu'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Gönderenin mevcut bakiyesini kontrol et
      DocumentSnapshot senderBalanceDoc = await FirebaseFirestore.instance
          .collection('balances')
          .doc(currentUser.uid)
          .get();

      int senderCurrentBalance = senderBalanceDoc.exists
          ? (senderBalanceDoc['amount'] as num).toInt()
          : 0;

      // Bakiye yetersizse hata ver
      if (senderCurrentBalance < amount) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bakiye yetersiz. Transfer yapılamaz.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Hedef kullanıcı bilgileri
      DocumentSnapshot targetUserDoc = referralCheck.docs.first;
      String targetUserId = targetUserDoc.id;

      // Firestore işlemleri için batch kullanarak atomik işlem gerçekleştir
      WriteBatch batch = FirebaseFirestore.instance.batch();

      // Gönderenin bakiyesinden düş
      DocumentReference senderBalanceRef = FirebaseFirestore.instance
          .collection('balances')
          .doc(currentUser.uid);
      batch.update(senderBalanceRef, {
        'amount': FieldValue.increment(-amount),
        'updatedAt': FieldValue.serverTimestamp()
      });

      // Alıcının bakiyesine ekle
      DocumentReference receiverBalanceRef =
          FirebaseFirestore.instance.collection('balances').doc(targetUserId);
      batch.set(
          receiverBalanceRef,
          {
            'uid': targetUserId,
            'amount': FieldValue.increment(amount),
            'updatedAt': FieldValue.serverTimestamp()
          },
          SetOptions(merge: true));

      // Transfer log'unu ekle
      DocumentReference transactionLogRef =
          FirebaseFirestore.instance.collection('transaction_logs').doc();
      batch.set(transactionLogRef, {
        'sender_uid': currentUser.uid,
        'receiver_uid': targetUserId,
        'type': 'referral_transfer',
        'amount': amount,
        'timestamp': FieldValue.serverTimestamp(),
        'ip_address': '127.0.0.1'
      });

      // Batch işlemini commit et
      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$amount TL başarıyla transfer edildi'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('İşlem sırasında hata oluştu: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Referans Kodunuz'),
        centerTitle: true,
      ),
      body: Center(
        child: _referralCode.isEmpty
            ? const SizedBox.shrink() // Boş durumda hiçbir şey gösterme
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  QrImageView(
                    data: _referralCode,
                    version: QrVersions.auto,
                    size: 250.0,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      color: Colors.black,
                      eyeShape: QrEyeShape.circle,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.circle,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _scanQRCode,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('QR Kodu Tara'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const DepositScreen()),
                        );
                      },
                      child: const Text("Para Yatırma")),
                ],
              ),
      ),
    );
  }
}
