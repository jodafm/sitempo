import 'package:flutter/material.dart';

import 'screens/timer_screen.dart';

void main() {
  runApp(const SitempoApp());
}

class SitempoApp extends StatelessWidget {
  const SitempoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sitempo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const TimerScreen(),
    );
  }
}
