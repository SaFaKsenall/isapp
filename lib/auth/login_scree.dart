import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:myapp/admin/admindashboard.dart';
import 'package:myapp/auth/forgot_password_page.dart';
import 'package:myapp/auth/register_screen.dart';
import 'package:myapp/model/user_model.dart';
import 'package:myapp/screens/bottom_menu.dart';
import 'package:myapp/wip/wip_home.dart';
import 'package:myapp/auth/auth_service.dart' as auth_service;

// Login Page

class LoginPage extends StatefulWidget {
  final UserModel? initialUser;

  const LoginPage({Key? key, this.initialUser}) : super(key: key);

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();

  final _passwordController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');

    return emailRegex.hasMatch(email);
  }

  @override
  void initState() {
    super.initState();

    // Eğer devre dışı bir hesapla gelindiyse aktivasyon dialogunu göster
    if (widget.initialUser != null && widget.initialUser!.isActive == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showActivationDialog(widget.initialUser!);
      });
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final userCredential = await auth_service.signIn(
        _emailController.text.trim(),
        _passwordController.text.trim(),
      );

      User? firebaseUser = userCredential.user;

      if (firebaseUser != null) {
        // Firestore'dan kullanıcı bilgilerini al
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(firebaseUser.uid)
            .get();

        if (userDoc.exists) {
          Map<String, dynamic> userData =
              userDoc.data() as Map<String, dynamic>;

          // isActive kontrolü
          if (userData['isActive'] == false) {
            setState(() {
              _isLoading = false;
            });

            // Aktivasyon dialogunu göster
            final isActivated = await _showActivationDialog(UserModel.fromMap({
              'uid': firebaseUser.uid,
              'email': firebaseUser.email,
              ...userData,
            }));

            if (isActivated == null || !isActivated) {
              // Aktivasyon iptal edildi veya başarısız oldu
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Aktivasyon işlemi iptal edildi'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
              return;
            }
          }

          // Kullanıcı aktif veya aktivasyon başarılı
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => AnimatedBottomTabBar(
                  user: UserModel.fromMap({
                    'uid': firebaseUser.uid,
                    'email': firebaseUser.email,
                    ...userData,
                  }),
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Giriş yapılırken bir hata oluştu. Lütfen tekrar deneyin.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool?> _showActivationDialog(UserModel user) {
    final TextEditingController codeController = TextEditingController();

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Hesap Aktivasyonu Gerekli'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Hesabınız devre dışı bırakılmış. Aktivasyon kodunu girerek hesabınızı aktifleştirebilirsiniz.'),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              decoration: InputDecoration(
                hintText: '6 haneli kod',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, false); // İptal edildiğinde false dön
            },
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = codeController.text.trim();

              if (code.length == 6) {
                try {
                  // Aktivasyon kodunu kontrol et

                  final activationDoc = await FirebaseFirestore.instance
                      .collection('activation_codes')
                      .doc(user.uid)
                      .get();

                  if (!activationDoc.exists) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Aktivasyon kodu bulunamadı')),
                    );

                    return;
                  }

                  final activationData =
                      activationDoc.data() as Map<String, dynamic>;

                  // Kodun geçerliliğini kontrol et

                  if (activationData['isUsed'] == true) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content:
                              Text('Bu aktivasyon kodu daha önce kullanılmış')),
                    );

                    return;
                  }

                  final expiresAt = activationData['expiresAt'] as Timestamp;

                  if (expiresAt.toDate().isBefore(DateTime.now())) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Aktivasyon kodunun süresi dolmuş')),
                    );

                    return;
                  }

                  if (code == activationData['code']) {
                    // Hesabı aktifleştir

                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .update({'isActive': true});

                    // Aktivasyon kodunu kullanıldı olarak işaretle

                    await FirebaseFirestore.instance
                        .collection('activation_codes')
                        .doc(user.uid)
                        .update({
                      'isUsed': true,
                      'usedAt': FieldValue.serverTimestamp(),
                    });

                    Navigator.pop(context, true);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Geçersiz aktivasyon kodu')),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Aktivasyon sırasında hata oluştu: $e')),
                  );
                }
              }
            },
            child: const Text('Aktifleştir'),
          ),
        ],
      ),
    );
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
              Colors.blue.shade50,
              Colors.blue.shade100,
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
                          'Giriş Yap',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        )
                            .animate()
                            .fadeIn(duration: 500.ms)
                            .slideY(begin: -0.5, end: 0),

                        const SizedBox(height: 32),

                        TextFormField(
                          controller: _emailController,
                          decoration: InputDecoration(
                            prefixIcon:
                                Icon(Icons.email, color: Colors.blue.shade500),
                            labelText: 'E-posta',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
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
                            .fadeIn(delay: 300.ms, duration: 500.ms)
                            .slideX(begin: -0.1, end: 0),

                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            prefixIcon:
                                Icon(Icons.lock, color: Colors.blue.shade500),
                            labelText: 'Şifre',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
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
                            .fadeIn(delay: 500.ms, duration: 500.ms)
                            .slideX(begin: -0.1, end: 0),

                        const SizedBox(height: 24),

                        _isLoading
                            ? CircularProgressIndicator(
                                color: Colors.blue.shade500)
                            : ElevatedButton(
                                onPressed: _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade500,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(double.infinity, 50),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                child: const Text('Giriş Yap'),
                              )
                                .animate()
                                .fadeIn(delay: 700.ms, duration: 500.ms),

                        const SizedBox(height: 16),

                        // Login Navigation

                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) =>
                                    const ForgotPasswordPage(),
                              ),
                            );
                          },
                          child: Text(
                            'Hesabın yok mu? Kayıt Ol',
                            style: TextStyle(color: Colors.blue.shade700),
                          ),
                        ).animate().fadeIn(delay: 1100.ms, duration: 500.ms),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const RegisterPage(),
                              ),
                            );
                          },
                          child: Text(
                            'Şifremi Unuttum',
                            style: TextStyle(color: Colors.blue.shade700),
                          ),
                        ).animate().fadeIn(delay: 900.ms, duration: 500.ms),
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
    _emailController.dispose();

    _passwordController.dispose();

    super.dispose();
  }
}
