import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:myapp/chat/chatpage.dart';
import 'package:myapp/firebase_options.dart';
import 'package:myapp/screens/splash_screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

bool _initialized = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // OneSignal Başlatma ve Ayarlar
  OneSignal.initialize("10eef095-d1ee-4c36-a53d-454b1f5d6746");
  OneSignal.Notifications.requestPermission(true);
  OneSignal.consentGiven(true);

  // OneSignal Player ID'yi Firestore'a kaydet
  OneSignal.User.pushSubscription.addObserver((state) async {
    String? playerId = state.current.id;
    String? userId = FirebaseAuth.instance.currentUser?.uid;

    if (playerId != null && userId != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({'oneSignalPlayerId': playerId});
    }
  });

  // Bildirime tıklandığında sohbet sayfasına yönlendirme
  OneSignal.Notifications.addClickListener((event) {
    if (event.notification.additionalData != null) {
      final data = event.notification.additionalData!;
      if (data['type'] == 'chat') {
        Navigator.push(
          GlobalKey<NavigatorState>().currentContext!,
          MaterialPageRoute(
            builder: (context) => ChatPage(
              otherUserId: data['senderId'],
              otherUserName: data['senderName'],
              otherUserProfileImageUrl: data['senderProfileImage'],
            ),
          ),
        );
      }
    }
  });

  // Sistem UI yapılandırması
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  // Yönlendirme ayarları
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Firebase başlatma kontrolü
  if (!_initialized) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _initialized = true;
    } catch (e) {
      debugPrint('Firebase initialization error: $e');
    }
  }

  runApp(const JobPlatformApp());
}

class JobPlatformApp extends StatelessWidget {
  const JobPlatformApp({Key? key}) : super(key: key);

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
        textTheme: GoogleFonts.interTextTheme(
          Theme.of(context).textTheme,
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          primary: Colors.blue.shade600,
          secondary: Colors.purple.shade600,
          background: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade600,
            foregroundColor: Colors.white,
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
          backgroundColor: Colors.white,
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
      home: splashhh(),
    ).animate().fadeIn(duration: 500.ms);
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
