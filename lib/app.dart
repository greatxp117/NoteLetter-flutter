import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'state/theme_notifier.dart';
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
      // The themes are built from the semantic tokens in `theme/app_theme.dart`.
      // They used to be declared inline here with
      // `ColorScheme.fromSeed(seedColor: brick-500)`, which derived a whole
      // tonal palette from one token by algorithm: most widgets drew colours
      // that appear nowhere in design-tokens.md, and only scaffold/card/divider
      // were actually token-set. A generated palette is always self-consistent,
      // so nothing ever looked broken — it was simply a different design.
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: context.watch<ThemeNotifier>().themeMode,
    );
  }
}
