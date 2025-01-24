// register_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:myapp/auth/login_scree.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _isLoading = false;
  String? _phoneNumber;
  String? _verificationId;

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
    return emailRegex.hasMatch(email);
  }

  String _generateUniqueHash() {
    String uniqueString = '${_emailController.text.trim()}_'
        '${DateTime.now().millisecondsSinceEpoch}';

    var bytes = utf8.encode(uniqueString);
    var digest = sha256.convert(bytes);

    return digest.toString().substring(0, 8).toUpperCase();
  }

  Future<void> _verifyPhoneNumber() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // 1. Telefon numarasının mevcut olup olmadığını kontrol et
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: _phoneNumber)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        // Telefon numarası kullanılıyor
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Bu telefon numarası başka bir hesapta kullanılıyor!')),
        );
        return;
      }

      await _auth.verifyPhoneNumber(
        phoneNumber: _phoneNumber!,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _signInWithCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Doğrulama hatası: ${e.message}')),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _isLoading = false;
            _verificationId = verificationId;
          });

          final userData = {
            'username': _usernameController.text.trim(),
            'fullName': _fullNameController.text.trim(),
            'email': _emailController.text.trim(),
            'password': _passwordController.text.trim(),
            'phoneNumber': _phoneNumber,
            'referralCode': _generateUniqueHash(),
            'role': 'user', // Yeni eklenen role alanı
          };

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => PhoneVerificationPage(
                userData: userData,
                verificationId: verificationId,
                phoneNumber: _phoneNumber!,
              ),
            ),
          );
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          setState(() {
            _verificationId = verificationId;
            _isLoading = false;
          });
        },
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bir hata oluştu: $e')),
      );
    }
  }

  Future<void> _signInWithCredential(PhoneAuthCredential credential) async {
    try {
      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      if (userCredential.user != null) {
        await _auth.signOut(); // Telefon oturumunu kapat

        UserCredential emailCredential =
            await _auth.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        await FirebaseFirestore.instance
            .collection('users')
            .doc(emailCredential.user!.uid)
            .set({
          'username': _usernameController.text.trim(),
          'fullName': _fullNameController.text.trim(),
          'email': _emailController.text.trim(),
          'phoneNumber': _phoneNumber,
          'referralCode': _generateUniqueHash(),
          'uid': emailCredential.user!.uid,
          'createdAt': FieldValue.serverTimestamp(),
          'role': 'user', // Yeni eklenen role alanı
        });

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kayıt hatası: $e')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _auth.setLanguageCode('tr');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.purple.shade50,
              Colors.purple.shade100,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Card(
                elevation: 10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Kayıt Ol',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple.shade700,
                          ),
                        )
                            .animate()
                            .fadeIn(duration: 500.ms)
                            .slideY(begin: -0.5, end: 0),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: _fullNameController,
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.person_outline,
                                color: Colors.purple.shade500),
                            labelText: 'Ad Soyad',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide(
                                  color: Colors.purple.shade500, width: 2),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Ad soyad boş bırakılamaz';
                            }
                            return null;
                          },
                        )
                            .animate()
                            .fadeIn(delay: 200.ms, duration: 500.ms)
                            .slideX(begin: -0.1, end: 0),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.alternate_email,
                                color: Colors.purple.shade500),
                            labelText: 'Kullanıcı Adı',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide(
                                  color: Colors.purple.shade500, width: 2),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Kullanıcı adı boş bırakılamaz';
                            }
                            return null;
                          },
                        )
                            .animate()
                            .fadeIn(delay: 300.ms, duration: 500.ms)
                            .slideX(begin: -0.1, end: 0),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _emailController,
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.email,
                                color: Colors.purple.shade500),
                            labelText: 'E-posta',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide(
                                  color: Colors.purple.shade500, width: 2),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'E-posta boş bırakılamaz';
                            }
                            if (!_isValidEmail(value)) {
                              return 'Geçerli bir e-posta adresi giriniz';
                            }
                            return null;
                          },
                        )
                            .animate()
                            .fadeIn(delay: 400.ms, duration: 500.ms)
                            .slideX(begin: -0.1, end: 0),
                        const SizedBox(height: 16),
                        IntlPhoneField(
                          decoration: InputDecoration(
                            labelText: 'Telefon Numarası',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide(
                                  color: Colors.purple.shade500, width: 2),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide(color: Colors.grey.shade400),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 16),
                          ),
                          initialCountryCode: 'TR',
                          dropdownIconPosition: IconPosition.trailing,
                          flagsButtonPadding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          showDropdownIcon: true,
                          dropdownIcon: Icon(Icons.arrow_drop_down,
                              color: Colors.purple.shade500),
                          invalidNumberMessage: 'Geçersiz telefon numarası',
                          onChanged: (phone) {
                            setState(() {
                              _phoneNumber = phone.completeNumber;
                            });
                          },
                          validator: (value) {
                            if (value == null || value.completeNumber.isEmpty) {
                              return 'Telefon numarası boş bırakılamaz';
                            }
                            return null;
                          },
                        )
                            .animate()
                            .fadeIn(delay: 500.ms, duration: 500.ms)
                            .slideX(begin: -0.1, end: 0),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.lock,
                                color: Colors.purple.shade500),
                            labelText: 'Şifre',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide(
                                  color: Colors.purple.shade500, width: 2),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Şifre boş bırakılamaz';
                            }
                            if (value.length < 6) {
                              return 'Şifre en az 6 karakter olmalıdır';
                            }
                            return null;
                          },
                        )
                            .animate()
                            .fadeIn(delay: 600.ms, duration: 500.ms)
                            .slideX(begin: -0.1, end: 0),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            prefixIcon: Icon(Icons.lock_outline,
                                color: Colors.purple.shade500),
                            labelText: 'Şifreyi Onayla',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                              borderSide: BorderSide(
                                  color: Colors.purple.shade500, width: 2),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Şifre onayı boş bırakılamaz';
                            }
                            if (value != _passwordController.text) {
                              return 'Şifreler eşleşmiyor';
                            }
                            return null;
                          },
                        )
                            .animate()
                            .fadeIn(delay: 700.ms, duration: 500.ms)
                            .slideX(begin: -0.1, end: 0),
                        const SizedBox(height: 24),
                        _isLoading
                            ? CircularProgressIndicator(
                                color: Colors.purple.shade500)
                            : ElevatedButton(
                                onPressed: _verifyPhoneNumber,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple.shade500,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 50),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                child: const Text('Kayıt Ol'),
                              )
                                .animate()
                                .fadeIn(delay: 800.ms, duration: 500.ms)
                                .slideY(begin: 0.1, end: 0),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const LoginPage(),
                              ),
                            );
                          },
                          child: Text(
                            'Zaten hesabın var mı? Giriş Yap',
                            style: TextStyle(color: Colors.purple.shade700),
                          ),
                        )
                            .animate()
                            .fadeIn(delay: 900.ms, duration: 500.ms),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }
}

// PhoneVerificationPage
class PhoneVerificationPage extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String verificationId;
  final String phoneNumber;

  const PhoneVerificationPage({
    super.key,
    required this.userData,
    required this.verificationId,
    required this.phoneNumber,
  });

  @override
  _PhoneVerificationPageState createState() => _PhoneVerificationPageState();
}

class _PhoneVerificationPageState extends State<PhoneVerificationPage> {
  final TextEditingController _codeController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isLoading = false;
  int _resendTimer = 60;
  bool _canResend = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  void _startResendTimer() {
    setState(() {
      _resendTimer = 60;
      _canResend = false;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_resendTimer > 0) {
          _resendTimer--;
        } else {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  String _getEnteredCode() {
      return _codeController.text;
  }

  Future<void> _verifyCode() async {
    final enteredCode = _getEnteredCode();

    if (enteredCode.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen 6 haneli kodu tam olarak giriniz')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // SMS kodunu doğrula
      final credential = PhoneAuthProvider.credential(
        verificationId: widget.verificationId,
        smsCode: enteredCode,
      );

      // Önce telefon doğrulamasını yap
      await _auth.signInWithCredential(credential);

      // Telefon doğrulaması başarılı olduğunda kullanıcı hesabını oluştur
      await _createUserAccount();
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'invalid-verification-code':
          message = 'Geçersiz doğrulama kodu. Lütfen tekrar deneyin.';
          break;
        case 'invalid-verification-id':
          message =
              'Doğrulama oturumu zaman aşımına uğradı. Tekrar kod gönderin.';
          break;
        default:
          message = 'Bir hata oluştu: ${e.message}';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bir hata oluştu: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _createUserAccount() async {
    try {
      // Mevcut telefon auth oturumunu kapat
      await _auth.signOut();

      // Email/password hesabı oluştur
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: widget.userData['email'],
        password: widget.userData['password'],
      );

      // Firestore'a kullanıcı bilgilerini kaydet
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set({
        ...widget.userData,
        'uid': userCredential.user!.uid,
        'phoneVerified': true,
        'createdAt': FieldValue.serverTimestamp(),
        'role': 'user', // Yeni eklenen role alanı
      });

      // Başarılı kayıt sonrası giriş sayfasına yönlendir
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
          (route) => false,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kayıt başarıyla tamamlandı!')),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'email-already-in-use':
          message = 'Bu e-posta adresi zaten kullanımda';
          break;
        case 'weak-password':
          message = 'Şifre çok zayıf';
          break;
        default:
          message = 'Kayıt hatası: ${e.message}';
      }
       throw FirebaseAuthException(code: e.code, message: message);
    }
  }

  Future<void> _resendCode() async {
    if (!_canResend) return;

    setState(() => _isLoading = true);

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: widget.phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _auth.signInWithCredential(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Doğrulama hatası: ${e.message}')),
          );
        },
        codeSent: (String verificationId, int? resendToken) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Yeni kod gönderildi')),
          );
          _startResendTimer();
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
        timeout: const Duration(seconds: 60),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kod gönderme hatası: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.purple.shade50,
              Colors.purple.shade100,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Card(
                elevation: 10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Telefon Doğrulama',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade700,
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 500.ms)
                          .slideY(begin: -0.5, end: 0),
                      const SizedBox(height: 16),
                      Text(
                        '${widget.phoneNumber} numaralı telefona\ngönderilen 6 haneli kodu giriniz',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 16,
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 200.ms, duration: 500.ms),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: 250,
                        child: TextFormField(
                            controller: _codeController,
                              keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 6,
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: 'Doğrulama Kodunu Giriniz',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: Colors.purple.shade500,
                                    width: 2,
                                  ),
                                ),
                            ),
                            )
                        .animate()
                            .fadeIn(
                                  delay:  300.ms,
                                  duration: 500.ms)
                            .slideY(begin: 0.1, end: 0),
                      ),
                      const SizedBox(height: 32),
                      _isLoading
                          ? CircularProgressIndicator(
                              color: Colors.purple.shade500)
                          : ElevatedButton(
                              onPressed: _verifyCode,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple.shade500,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(double.infinity, 50),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                ),
                              ),
                              child: const Text('Doğrula'),
                            )
                                .animate()
                                .fadeIn(delay: 900.ms, duration: 500.ms)
                                .slideY(begin: 0.1, end: 0),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _canResend ? _resendCode : null,
                        child: Text(
                          _canResend
                              ? 'Kodu Tekrar Gönder'
                              : 'Yeni kod için $_resendTimer saniye bekleyin',
                          style: TextStyle(
                            color: _canResend
                                ? Colors.purple.shade700
                                : Colors.grey.shade600,
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 1000.ms, duration: 500.ms),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
       _codeController.dispose();
    super.dispose();
  }
}