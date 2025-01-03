import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:myapp/auth/login_scree.dart';
import 'package:myapp/auth/register_screen.dart';
import 'package:myapp/screens/qr_payment/iyzico.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'İş Bulma Uygulaması',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    checkAppPassword();
  }

  Future<void> checkAppPassword() async {
    await Future.delayed(const Duration(seconds: 3));
    final password = await DatabaseHelper.instance.getPassword();
    if (password != null) {
      // Şifre varsa, şifre giriş ekranına yönlendir
      Navigator.pushReplacement(
        context as BuildContext,
        MaterialPageRoute(builder: (context) => const PasswordScreen()),
      );
    } else {
      // Şifre yoksa, şifre oluşturma ekranına yönlendir
      Navigator.pushReplacement(
        context as BuildContext,
        MaterialPageRoute(builder: (context) => const CreatePasswordScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}

class CreatePasswordScreen extends StatefulWidget {
  const CreatePasswordScreen({super.key});

  @override
  _CreatePasswordScreenState createState() => _CreatePasswordScreenState();
}

class _CreatePasswordScreenState extends State<CreatePasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  String errorText = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '6 Haneli Şifre Oluşturun',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Şifre',
                labelStyle: TextStyle(color: Colors.white),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
                counterStyle: TextStyle(color: Colors.white),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmPasswordController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Şifreyi Tekrar Girin',
                labelStyle: TextStyle(color: Colors.white),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
                counterStyle: TextStyle(color: Colors.white),
              ),
            ),
            if (errorText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  errorText,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                if (_passwordController.text.length != 6) {
                  setState(() {
                    errorText = 'Şifre 6 haneli olmalıdır';
                  });
                  return;
                }
                if (_passwordController.text !=
                    _confirmPasswordController.text) {
                  setState(() {
                    errorText = 'Şifreler eşleşmiyor';
                  });
                  return;
                }
                await DatabaseHelper.instance
                    .setPassword(_passwordController.text);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const splashhh()),
                );
              },
              child: const Text('Şifreyi Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}

class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});

  @override
  _PasswordScreenState createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _passwordController = TextEditingController();
  String errorText = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Şifre Girin',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _passwordController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Şifre',
                labelStyle: TextStyle(color: Colors.white),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white),
                ),
                counterStyle: TextStyle(color: Colors.white),
              ),
            ),
            if (errorText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  errorText,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final savedPassword =
                    await DatabaseHelper.instance.getPassword();
                if (_passwordController.text == savedPassword) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const splashhh()),
                  );
                } else {
                  setState(() {
                    errorText = 'Yanlış şifre!';
                  });
                }
              },
              child: const Text('Giriş'),
            ),
          ],
        ),
      ),
    );
  }
}

class splashhh extends StatelessWidget {
  const splashhh({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (context) =>  iyzicopayment()));
            },
            icon: const Icon(Icons.payment)),
        title: const Text('İş Bulma Uygulaması'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock),
            onPressed: () => _showPasswordDialog(context),
          ),
        ],
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Lottie.asset(
              'lottie/1735243972997.json',
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginPage()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text('Giriş Yap'),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const RegisterPage()));
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text('Kayıt Ol'),
                ),
              ],
            ),
          ),
        ],
      ),
      backgroundColor: Colors.white,
    );
  }

  void _showPasswordDialog(BuildContext context) {
    final newPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uygulama Şifresini Değiştir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newPasswordController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Yeni Şifre (6 Haneli)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              if (newPasswordController.text.length == 6) {
                await DatabaseHelper.instance
                    .setPassword(newPasswordController.text);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Şifre başarıyla güncellendi')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Şifre 6 haneli olmalıdır')),
                );
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('app_password.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE app_password(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        password TEXT NOT NULL
      )
    ''');
  }

  Future<String?> getPassword() async {
    final db = await instance.database;
    final result = await db.query('app_password');
    if (result.isNotEmpty) {
      return result.first['password'] as String;
    }
    return null;
  }

  Future<int> setPassword(String password) async {
    final db = await instance.database;
    await db.delete('app_password'); // Eski şifreyi sil
    return await db.insert('app_password', {'password': password});
  }
}
