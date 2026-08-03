import 'package:flutter/material.dart';
import 'config/theme.dart';
import 'widgets/bottom_nav.dart';
import 'screens/input/input_home.dart';
import 'screens/output/output_home.dart';
import 'screens/profile/profile_home.dart';

class ReadFlowApp extends StatefulWidget {
  const ReadFlowApp({super.key});

  @override
  State<ReadFlowApp> createState() => _ReadFlowAppState();
}

class _ReadFlowAppState extends State<ReadFlowApp> {
  ReadFlowTab _currentTab = ReadFlowTab.input;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ReadFlow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: IndexedStack(
          index: _currentTab.index,
          children: const [
            InputHomeScreen(),
            OutputHomeScreen(),
            ProfileHomeScreen(),
          ],
        ),
        bottomNavigationBar: ReadFlowBottomNav(
          currentTab: _currentTab,
          onTabChanged: (tab) {
            setState(() => _currentTab = tab);
          },
        ),
      ),
    );
  }
}
