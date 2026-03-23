import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../main.dart';

class ShellScreen extends StatelessWidget {
  final Widget child;
  final String location;

  const ShellScreen({super.key, required this.child, required this.location});

  int get _selectedIndex {
    if (location.startsWith('/profile')) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surfaceCard,
          border: Border(
            top: BorderSide(color: Color(0x26C5C8BE), width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x10558045),
              blurRadius: 24,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (i) {
            switch (i) {
              case 0:
                context.go('/');
              case 1:
                context.go('/profile');
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
