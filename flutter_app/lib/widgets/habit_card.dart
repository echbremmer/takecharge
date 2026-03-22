import 'package:flutter/material.dart';
import '../main.dart';

class HabitCard extends StatelessWidget {
  final Map<String, dynamic> habit;
  final VoidCallback onTap;

  const HabitCard({super.key, required this.habit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final type = habit['type'] as String? ?? '';

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _typeIcon(type),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      habit['name'] ?? '',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppTheme.sageDark,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _typeLabel(type),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textLight,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.sageLight),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeIcon(String type) {
    IconData icon;
    Color color;
    switch (type) {
      case 'timer':
        icon = Icons.timer_outlined;
        color = AppTheme.sageMid;
        break;
      case 'daily':
        icon = Icons.today_outlined;
        color = AppTheme.accent;
        break;
      case 'todo':
        icon = Icons.checklist_outlined;
        color = AppTheme.sageDark;
        break;
      default:
        icon = Icons.track_changes;
        color = AppTheme.sageLight;
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'timer':
        return 'Fasting timer';
      case 'daily':
        return 'Daily targets';
      case 'todo':
        return 'To-do list';
      default:
        return type;
    }
  }
}
