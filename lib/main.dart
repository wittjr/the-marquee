import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/auth_controller.dart';
import 'ui/app.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthController()..bootstrap(),
      child: const MarqueeApp(),
    ),
  );
}
