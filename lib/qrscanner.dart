import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class QRScannerapp extends StatefulWidget {
  final User currentUser;

  const QRScannerapp({Key? key, required this.currentUser}) : super(key: key);

  @override
  State<QRScannerapp> createState() => _QRScannerappState();
}

class _QRScannerappState extends State<QRScannerapp> {
  final MobileScannerController controller = MobileScannerController();
  bool isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR Kod ile Giriş'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: () => controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _onDetect,
            overlayBuilder: (context, constraints) {
              return Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  border: Border.all(
                    color: Colors.blue,
                    width: 10,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
              );
            },
          ),
          if (isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) async {
    if (isProcessing) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? code = barcodes.first.rawValue;
    if (code == null) return;

    setState(() {
      isProcessing = true;
    });

    try {
      final sessionId = code;
      print('QR Code tarandı: $sessionId');

      // QR session kontrolü
      final sessionDoc = await FirebaseFirestore.instance
          .collection('qr_sessions')
          .doc(sessionId)
          .get();

      if (!sessionDoc.exists) {
        throw Exception('Geçersiz QR kod');
      }

      print('Mevcut kullanıcı bilgileri: ${widget.currentUser.email}');

      // Session'ı güncelle
      final updateData = {
        'status': 'completed',
        'userId': widget.currentUser.uid,
        'userData': {
          'email': widget.currentUser.email,
          'username': widget.currentUser.displayName,
          // diğer kullanıcı bilgileri
        },
        'completedAt': FieldValue.serverTimestamp(),
      };
      
      print('Firestore\'a gönderilen veriler: $updateData');

      await FirebaseFirestore.instance
          .collection('qr_sessions')
          .doc(sessionId)
          .update(updateData);

      print('QR session güncellendi');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Web oturumu başarıyla açıldı!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      print('QR Login Hatası: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Hata: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isProcessing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
