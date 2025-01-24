import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String username;
  final String? profileImageUrl;
  String? uniqueHash;
  final bool? transferAllowed;
  String? email;
  String? role; // Yeni eklenen role değişkeni
  bool isActive;

  UserModel({
    required this.uid,
    required this.username,
    this.profileImageUrl,
    this.uniqueHash,
    this.email,
    this.transferAllowed,
    this.role, // Role parametresi eklendi
    this.isActive = true,
  });

  // Firestore verisinden gelen veriyi model olarak döndüren metot
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'],
      username: map['username'],
      email: map['email'],
      uniqueHash: map['uniqueHash'],
      profileImageUrl: map['profileImageUrl'],
      transferAllowed: map['transferAllowed'] ?? false,
      role: map['role'], // 'role' alanı da okunuyor.
      isActive: map['isActive'] ?? true,
    );
  }

  // Modeli Firestore'a kaydedilecek formata dönüştüren metot
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'username': username,
      'email': email,
      'uniqueHash': uniqueHash,
      'profileImageUrl': profileImageUrl,
      'transferAllowed': transferAllowed,
      'role': role, // 'role' alanı da kaydediliyor
      'isActive': isActive,
    };
  }

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      username: data['username'] ?? '',
      profileImageUrl: data['profileImageUrl'],
    );
  }
}
