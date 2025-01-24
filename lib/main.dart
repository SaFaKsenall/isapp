import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:myapp/chat/chatpage.dart';
import 'package:myapp/firebase_options.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:myapp/auth/login_scree.dart';
import 'package:myapp/model/user_model.dart';
import 'package:myapp/screens/bottom_menu.dart';
import 'package:myapp/admin/admindashboard.dart';
import 'package:myapp/wip/wip_home.dart';

// Firebase başlatma durumunu global olarak tutalım
bool _initialized = false;
late final Future<FirebaseApp> _initialization;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase başlatmayı bir kere yapalım ve saklayalım
  _initialization = Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // OneSignal ve diğer başlatma işlemlerini parallel çalıştıralım
  await Future.wait([
    _initialization,
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]),
    _initializeOneSignal(),
  ]);

  runApp(const JobPlatformApp());
}

// OneSignal başlatma işlemini güncelliyoruz
Future<void> _initializeOneSignal() async {
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  OneSignal.initialize('10eef095-d1ee-4c36-a53d-454b1f5d6746');
  // Otomatik izin istemeyi kaldırıyoruz
  // await OneSignal.Notifications.requestPermission(true);
  // await OneSignal.User.pushSubscription.optIn();
}

class JobPlatformApp extends StatefulWidget {
  const JobPlatformApp({Key? key}) : super(key: key);

  @override
  State<JobPlatformApp> createState() => _JobPlatformAppState();
}

class _JobPlatformAppState extends State<JobPlatformApp> {
  @override
  void initState() {
    super.initState();
    // Uygulama başladıktan sonra bildirim izni isteyelim
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestNotificationPermission(context);
    });
  }

  Future<void> _requestNotificationPermission(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Bildirim İzni',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'Uygulamamız size önemli güncellemeler ve bildirimler göndermek istiyor. İzin vermek ister misiniz?',
          style: GoogleFonts.inter(),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text(
              'Hayır',
              style: GoogleFonts.inter(
                color: Colors.grey,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              await OneSignal.Notifications.requestPermission(true);
              await OneSignal.User.pushSubscription.optIn();
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(
              'İzin Ver',
              style: GoogleFonts.inter(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // OneSignal bildirim işleyicisini güncelle
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      // Bildirimi göster ve varsayılan sesi çal
      event.notification.display();
    });

    OneSignal.Notifications.addClickListener((event) {
      debugPrint("Bildirim açıldı: ${event.notification.body}");
    });

    return MaterialApp(
      title: 'İş Platform',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
        textTheme: GoogleFonts.interTextTheme(
          Theme.of(context).textTheme,
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          primary: Colors.blue.shade600,
          secondary: Colors.purple.shade600,
          background: Colors.black87,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade600,
            foregroundColor: Colors.black87,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 30),
            textStyle: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.blue.shade600, width: 2),
          ),
          labelStyle: GoogleFonts.inter(
            color: Colors.grey.shade600,
          ),
        ),
        appBarTheme: AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.blue.shade600,
          foregroundColor: Colors.black87,
          centerTitle: true,
          titleTextStyle: GoogleFonts.inter(
            color: Colors.black87,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        cardTheme: CardTheme(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      builder: (context, child) {
        return Container(
          color: Colors.white,
          child: child ?? const SizedBox(),
        );
      },
      home: FutureBuilder(
        // Önceden başlatılmış Firebase instance'ını kullanalım
        future: _initialization,
        builder: (context, firebaseSnapshot) {
          if (firebaseSnapshot.connectionState == ConnectionState.waiting) {
            return _buildSplashScreen(); // Yeni splash screen
          }

          return StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildSplashScreen();
              }

              if (snapshot.hasData && snapshot.data != null) {
                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(snapshot.data!.uid)
                      .get(),
                  builder: (context, userSnapshot) {
                    if (userSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return Scaffold(
                        backgroundColor: Colors.white,
                        body: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                color: Colors.blue.shade600,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Bilgileriniz yükleniyor...',
                                style: GoogleFonts.inter(
                                  color: Colors.grey[600],
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    if (userSnapshot.hasData && userSnapshot.data != null) {
                      final userData =
                          userSnapshot.data!.data() as Map<String, dynamic>;

                      final currentUser = UserModel.fromMap({
                        'uid': snapshot.data!.uid,
                        'email': snapshot.data!.email,
                        ...userData,
                      });

                      // isActive kontrolü ekleyelim
                      if (userData['isActive'] == false) {
                        // Devre dışı hesap için login sayfasına yönlendir
                        return LoginPage(initialUser: currentUser);
                      }

                      // Aktif hesaplar için rol kontrolü
                      switch (currentUser.role) {
                        case 'admin':
                          return const AdminDashboard();
                        case 'wip':
                          return const WIPPage();
                        case 'user':
                        default:
                          return AnimatedBottomTabBar(user: currentUser);
                      }
                    }

                    // Hata durumunda login sayfasına yönlendir
                    return const LoginPage();
                  },
                );
              }

              // Kullanıcı oturum açmamışsa giriş sayfasına yönlendir
              return const LoginPage();
            },
          );
        },
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  // Yeni splash screen widget'ı
  Widget _buildSplashScreen() {
    return Container(
      color: Colors.white,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo veya marka görselinizi buraya ekleyebilirsiniz
            Image.asset(
              'assets/logo.png', // Logo dosyanızın yolu
              width: 120,
              height: 120,
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          ],
        ),
      ),
    );
  }
}

class ConnectionWrapper extends StatefulWidget {
  final Widget child;
  const ConnectionWrapper({Key? key, required this.child}) : super(key: key);

  @override
  State<ConnectionWrapper> createState() => _ConnectionWrapperState();
}

class _ConnectionWrapperState extends State<ConnectionWrapper>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  bool _isConnected = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    ));

    checkConnectivity();
  }

  Future<void> checkConnectivity() async {
    final connectivity = Connectivity();
    final ConnectivityResult connectivityResult =
        await connectivity.checkConnectivity();
    updateConnectionStatus(connectivityResult);

    connectivity.onConnectivityChanged.listen((ConnectivityResult result) {
      updateConnectionStatus(result);
    });
  }

  void updateConnectionStatus(ConnectivityResult result) {
    if (!mounted) return;

    setState(() {
      _isConnected = result != ConnectivityResult.none;
      if (!_isConnected) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Stack(
        children: [
          widget.child,
          if (!_isConnected)
            FadeTransition(
              opacity: _fadeAnimation,
              child: Scaffold(
                backgroundColor: const Color(0xFFF5F5F5),
                body: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white,
                        Colors.grey.shade50,
                      ],
                    ),
                  ),
                  width: double.infinity,
                  height: double.infinity,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.1),
                                spreadRadius: 8,
                                blurRadius: 12,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.wifi_off_rounded,
                            size: 80,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'İnternet bağlantınızı kontrol edin',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
