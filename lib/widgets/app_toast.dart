import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum ToastType { success, error, info }

class AppToast {
  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color borderColor;
    Color iconColor;
    IconData iconData;

    switch (type) {
      case ToastType.success:
        borderColor = Colors.green.shade400;
        iconColor = Colors.green.shade400;
        iconData = Icons.check_circle_outline;
        break;
      case ToastType.error:
        borderColor = Colors.red.shade400;
        iconColor = Colors.red.shade400;
        iconData = Icons.error_outline;
        break;
      case ToastType.info:
        borderColor =
            isDark ? AppColors.primaryDark : AppColors.primary;
        iconColor = isDark ? AppColors.primaryDark : AppColors.primary;
        iconData = Icons.info_outline;
        break;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          padding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          elevation: 0,
          content: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.cardDark : Colors.white,
              border: Border.all(color: borderColor, width: 1.5),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(iconData, color: iconColor, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      color: isDark
                          ? AppColors.foregroundDark
                          : AppColors.foregroundLight,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }
}
