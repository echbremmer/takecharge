import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../providers/habits_provider.dart';

class ShellScreen extends ConsumerStatefulWidget {
  final Widget child;
  final String location;

  const ShellScreen({super.key, required this.child, required this.location});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset('assets/logo.svg', height: 32),
            const SizedBox(width: 8),
            SvgPicture.asset('assets/logo-text.svg', height: 20),
          ],
        ),
        titleSpacing: 16,
        actions: [
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.person_outline,
                color: Color(0xFF2C2C2C)),
            onPressed: () => context.go('/profile'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0x26C5C8BE)),
        ),
      ),
      body: widget.child,
      bottomNavigationBar: _BottomNav(
        onTap: () => context.go('/'),
      ),
    );
  }
}

// ── Hamburger dropdown panel ───────────────────────────────────────────────

class _HamburgerMenu extends ConsumerWidget {
  final String location;
  final VoidCallback onSelect;

  const _HamburgerMenu({required this.location, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitsProvider);

    return Material(
      elevation: 0,
      color: AppTheme.surfaceCard,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppTheme.surfaceCard,
          boxShadow: [
            BoxShadow(
              color: Color(0x1A55624D),
              blurRadius: 32,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _MenuItem(
              label: 'Summary',
              isActive: location == '/',
              onTap: () {
                onSelect();
                context.go('/');
              },
            ),
            habitsAsync.when(
              loading: () => const SizedBox(
                height: 48,
                child: Center(child: LinearProgressIndicator()),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (habits) => Column(
                mainAxisSize: MainAxisSize.min,
                children: habits.map<Widget>((h) {
                  final id = h['id'] as int;
                  final isActive = location == '/habit/$id';
                  return _MenuItem(
                    label: h['name'] as String,
                    isActive: isActive,
                    onTap: () {
                      onSelect();
                      context.go('/habit/$id');
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _MenuItem({required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        color: isActive ? AppTheme.primaryFixed.withOpacity(0.5) : Colors.transparent,
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? AppTheme.primary : AppTheme.onSurfaceVar,
          ),
        ),
      ),
    );
  }
}

// ── Bottom navigation bar ─────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final VoidCallback onTap;
  const _BottomNav({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xCCF8FAF3),
        border: Border(top: BorderSide(color: Color(0x26C5C8BE), width: 1)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            _NavItem(
              icon: Icons.dashboard_outlined,
              selectedIcon: Icons.dashboard,
              label: 'Dashboard',
              selected: true,
              onTap: onTap,
            ),
            _NavItem(
              icon: Icons.bar_chart_outlined,
              selectedIcon: Icons.bar_chart,
              label: 'Insights',
              selected: false,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}


class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.primary : AppTheme.onSurfaceMuted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? selectedIcon : icon, color: color, size: 24),
              const SizedBox(height: 3),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
