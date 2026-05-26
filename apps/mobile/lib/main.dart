import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:screen_protector/screen_protector.dart';

import 'firebase_options.dart';
import 'core/config/emulator.dart';
import 'core/services/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/banned_page.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/auth/presentation/main_shell.dart';
import 'features/auth/presentation/terms_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await connectToEmulators();
  await NotificationService.init();
  if (!kIsWeb) await ScreenProtector.preventScreenshotOn();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Desafio Pago',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const _SplashScreen(),
    );
  }
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 2800), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const AuthGate(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset(
          'assets/images/logo_anim_sq_light.gif',
          width: 260,
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }
        if (!snapshot.hasData) return const LoginPage();
        return _TermsGate(userId: snapshot.data!.uid);
      },
    );
  }
}

class _TermsGate extends StatefulWidget {
  final String userId;
  const _TermsGate({required this.userId});

  @override
  State<_TermsGate> createState() => _TermsGateState();
}

class _TermsGateState extends State<_TermsGate> {
  late Future<bool> _termsFuture;

  @override
  void initState() {
    super.initState();
    _termsFuture = _checkTerms();
  }

  Future<bool> _checkTerms() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();
    return doc.data()?['termsAccepted'] == true;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _termsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const _LoadingScreen();
        if (!snapshot.data!) {
          return TermsPage(
            onAccepted: () =>
                setState(() => _termsFuture = Future.value(true)),
          );
        }
        return _BanGate(userId: widget.userId);
      },
    );
  }
}

class _BanGate extends StatefulWidget {
  final String userId;

  const _BanGate({required this.userId});

  @override
  State<_BanGate> createState() => _BanGateState();
}

class _BanGateState extends State<_BanGate> {
  @override
  void initState() {
    super.initState();
    NotificationService.requestAndSaveToken(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const _LoadingScreen();
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        if (data?['isBanned'] == true) {
          return BannedPage(reason: data?['banReason'] as String?);
        }
        return const MainShell();
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
