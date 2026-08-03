import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'config/constants.dart';
import 'providers/vocab_provider.dart';
import 'providers/article_provider.dart';
import 'providers/stats_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 Hive（本地 KV 存储，用于 API Key 等配置）
  await Hive.initFlutter();
  await Hive.openBox(AppConstants.hiveBoxSettings);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VocabProvider()),
        ChangeNotifierProvider(create: (_) => ArticleProvider()),
        ChangeNotifierProvider(create: (_) => StatsProvider()),
      ],
      child: const ReadFlowApp(),
    ),
  );
}
