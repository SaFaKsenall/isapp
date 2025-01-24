import 'package:firebase_auth/firebase_auth.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io' show Platform;

final FirebaseAuth _auth = FirebaseAuth.instance;

Future<UserCredential> signIn(String email, String password) async {
  try {
    final userCredential = await _auth.signInWithEmailAndPassword(
        email: email, password: password);

    // OneSignal durumunu kontrol et ve bekle
    await Future.delayed(Duration(seconds: 2)); // Player ID oluşması için bekle

    final status = await OneSignal.User.pushSubscription;
    final playerId = status.id;

    print('========= Giriş Durumu =========');
    print('User ID: ${userCredential.user?.uid}');
    print('Player ID: $playerId');
    print('==============================');

    // Firestore'a kaydet
    if (userCredential.user != null) {
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid);

      // Mevcut kullanıcı verilerini al
      final userDoc = await userRef.get();

      // Kullanıcı verilerini güncelle
      await userRef.set({
        // Eğer mevcut veriler varsa koru
        ...?userDoc.data(),

        // Yeni verileri ekle/güncelle
        'oneSignalPlayerId': playerId,
        'lastLogin': FieldValue.serverTimestamp(),
        'email': userCredential.user!.email,
        'lastUpdated': FieldValue.serverTimestamp(),
        'deviceInfo': {
          'platform': Platform.operatingSystem,
          'version': Platform.operatingSystemVersion,
          'lastUsed': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));

      print('Kullanıcı verileri Firestore\'a kaydedildi');
      print('Player ID: $playerId');
    }

    return userCredential;
  } catch (e) {
    print('Giriş hatası: $e');
    throw e;
  }
}

// Cihaz bilgilerini al
Future<Map<String, dynamic>> _getDeviceInfo() async {
  return {
    'platform': Platform.operatingSystem,
    'version': Platform.operatingSystemVersion,
    'timestamp': FieldValue.serverTimestamp(),
  };
}

Future<void> _updateOneSignalId() async {
  try {
    final user = _auth.currentUser;
    final playerId = await OneSignal.User.pushSubscription.id;

    print('Giriş sonrası OneSignal ID güncelleniyor...');
    print('User ID: ${user?.uid}');
    print('Player ID: $playerId');

    if (user != null && playerId != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'oneSignalPlayerId': playerId,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('OneSignal ID başarıyla güncellendi');
    }
  } catch (e) {
    print('OneSignal ID güncelleme hatası: $e');
  }
}
