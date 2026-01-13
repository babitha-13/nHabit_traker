import 'package:flutter/material.dart';
import 'package:habit_tracker/main.dart';

class ScoreBonusToastService {
  static void showBonusNotification({
    required String message,
    required double points,
    required String type,
  }) {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    
    final color = type == 'bonus' ? Colors.green : Colors.red;
    final icon = type == 'bonus' ? Icons.add_circle : Icons.remove_circle;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
  
  static void showMultipleNotifications(
    List<Map<String, dynamic>> notifications,
  ) {
    // Show notifications with delay between them
    for (int i = 0; i < notifications.length; i++) {
      Future.delayed(
        Duration(milliseconds: i * 500),
        () {
          showBonusNotification(
            message: notifications[i]['message'] as String,
            points: notifications[i]['points'] as double,
            type: notifications[i]['type'] as String,
          );
        },
      );
    }
  }
}

