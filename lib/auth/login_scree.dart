import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:myapp/admin/admindashboard.dart';
import 'package:myapp/auth/register_screen.dart';
import 'package:myapp/model/user_model.dart';
import 'package:myapp/screens/bottom_menu.dart';
import 'package:myapp/wip/wip_home.dart';

// Login Page
class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

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

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Firebase Authentication
      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Fetch user details from Firestore
      User? firebaseUser = userCredential.user;
      if (firebaseUser != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(firebaseUser.uid)
            .get();

        if (userDoc.exists) {
          UserModel currentUser = UserModel.fromMap({
            'uid': firebaseUser.uid,
            'email': firebaseUser.email,
            ...userDoc.data() as Map<String, dynamic>,
          });

          // Hesap devre dışı kontrolü
          if (!currentUser.isActive) {
            // Aktivasyon kodu dialogunu göster
            final bool? isActivated = await _showActivationDialog(currentUser);
            if (isActivated != true) {
              await FirebaseAuth.instance.signOut();
              throw FirebaseAuthException(
                code: 'user-disabled',
                message: 'Bu hesap devre dışı bırakılmış.',
              );
            }
            // Hesap aktifleştirildi, normal giriş işlemine devam et
          }

          // Kullanıcının rolüne göre yönlendirme
          switch (currentUser.role) {
            case 'admin':
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const AdminDashboard()),
              );
              break;
            case 'wip':
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (context) => const WIPPage()),
              );
              break;
            case 'user':
            default:
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => AnimatedBottomTabBar(user: currentUser),
                ),
              );
              break;
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage = '';
      switch (e.code) {
        case 'user-disabled':
          errorMessage = 'Bu hesap yönetici tarafından devre dışı bırakılmış.';
          break;
        case 'user-not-found':
          errorMessage = 'Bu e-posta ile kayıtlı kullanıcı bulunamadı';
          break;
        case 'wrong-password':
          errorMessage =
              'E-posta veya şifreniz hatalı. Lütfen tekrar kontrol ediniz.';
          break;
        case 'invalid-email':
          errorMessage = 'Geçersiz e-posta formatı';
          break;
        case 'too-many-requests':
          errorMessage =
              'Çok fazla deneme yaptınız. Lütfen daha sonra tekrar deneyin.';
          break;
        default:
          errorMessage =
              'Giriş sırasında bir hata oluştu. Lütfen bilgilerinizi kontrol edin.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          duration: Duration(seconds: 5),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      // Genel hata durumu için daha açıklayıcı bir mesaj
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Giriş işlemi sırasında beklenmedik bir hata oluştu'),
          duration: Duration(seconds: 5),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<bool?> _showActivationDialog(UserModel user) {
    final TextEditingController codeController = TextEditingController();

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Hesap Aktivasyonu Gerekli'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'Hesabınız devre dışı bırakılmış. Aktivasyon kodunu girerek hesabınızı aktifleştirebilirsiniz.'),
            SizedBox(height: 16),
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
              style: TextStyle(
                fontSize: 24,
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal'),
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
            child: Text('Aktifleştir'),
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
                                builder: (context) => const RegisterPage(),
                              ),
                            );
                          },
                          child: Text(
                            'Hesabın yok mu? Kayıt Ol',
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
