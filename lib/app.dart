import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

class NoteLetterApp extends StatelessWidget {
  final GoRouter router;

  const NoteLetterApp({super.key, required this.router});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NoteLetter',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        fontFamily: AppTheme.fontSans,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ),
        textTheme: ThemeData.light().textTheme.apply(fontFamily: AppTheme.fontSans),
        scaffoldBackgroundColor: AppColors.backgroundLight,
        cardColor: AppColors.cardLight,
        dividerColor: AppColors.borderLight,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: AppTheme.fontSans,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ),
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: AppTheme.fontSans),
        scaffoldBackgroundColor: AppColors.backgroundDark,
        cardColor: AppColors.cardDark,
        dividerColor: AppColors.borderDark,
      ),
      themeMode: ThemeMode.system,
    );
  }
}
