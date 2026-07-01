import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_controller.dart';
import 'login_page.dart';
import 'main_shell.dart';
import 'theme.dart';

class MarqueeApp extends StatelessWidget {
  const MarqueeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Marquee',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Consumer<AuthController>(
        builder: (context, auth, _) {
          switch (auth.status) {
            case AuthStatus.unknown:
              return const _SplashScreen();
            case AuthStatus.signedOut:
              return const LoginPage();
            case AuthStatus.signedIn:
              return const MainShell();
          }
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
