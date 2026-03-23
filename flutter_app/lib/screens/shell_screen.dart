import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class _ShellScreenState extends ConsumerState<ShellScreen>
    with SingleTickerProviderStateMixin {
  bool _menuOpen = false;
  late final AnimationController _menuCtrl;
  late final Animation<Offset> _menuSlide;

  @override
  void initState() {
    super.initState();
    _menuCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _menuSlide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _menuCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _menuCtrl.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    setState(() => _menuOpen = !_menuOpen);
    _menuOpen ? _menuCtrl.forward() : _menuCtrl.reverse();
  }

  void _closeMenu() {
    setState(() => _menuOpen = false);
    _menuCtrl.reverse();
  }

  int get _navIndex => widget.location.startsWith('/profile') ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('TAKECHARGE'),
        leading: IconButton(
          tooltip: 'Menu',
          icon: AnimatedIcon(
            icon: AnimatedIcons.menu_close,
            progress: _menuCtrl,
            color: AppTheme.onSurfaceVar,
          ),
          onPressed: _toggleMenu,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0x26C5C8BE)),
        ),
      ),
      body: Stack(
        children: [
          // Page content
          widget.child,

          // Scrim — closes menu on tap outside
          AnimatedBuilder(
            animation: _menuCtrl,
            builder: (context, _) => _menuCtrl.value > 0
                ? GestureDetector(
                    onTap: _closeMenu,
                    child: Container(
                      color: Colors.black.withOpacity(_menuCtrl.value * 0.18),
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // Slide-down menu panel
          SlideTransition(
            position: _menuSlide,
            child: Align(
              alignment: Alignment.topCenter,
              child: _HamburgerMenu(
                location: widget.location,
                onSelect: _closeMenu,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        selectedIndex: _navIndex,
        onTap: (i) {
          _closeMenu();
          if (i == 0) context.go('/');
          if (i == 1) context.go('/profile');
        },
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
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const _BottomNav({required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfaceCard,
        border: Border(top: BorderSide(color: Color(0x26C5C8BE), width: 1)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0C55624D),
            blurRadius: 24,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onTap,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'HOME',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'PROFILE',
          ),
        ],
      ),
    );
  }
}
