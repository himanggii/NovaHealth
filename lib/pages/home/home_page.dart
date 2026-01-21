import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dashboard/dashboard_page.dart';
import '../profile/profile_page.dart';
import '../settings/language_page.dart';
import '../tracking/input_page.dart';

import '../../auth/permissions.dart';
import '../../services/rbac_service.dart';
import '../../shared/app_state.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    // Safety: user must be logged in
    if (currentUserId == null) {
      return const Scaffold(body: Center(child: Text('User not logged in')));
    }

    return FutureBuilder<bool>(
      future: RBACService().hasPermission(
        currentUserId!,
        Permission.readOwnData,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.data == false) {
          return const Scaffold(body: Center(child: Text('Access Denied')));
        }

        return Scaffold(
          body: _buildBody(),
          bottomNavigationBar: _buildBottomNav(),
        );
      },
    );
  }

  /// -------- BODY (TABS) --------
  Widget _buildBody() {
    return FutureBuilder<bool>(
      future: RBACService().hasPermission(
        currentUserId!,
        Permission.writeOwnData,
      ),
      builder: (context, snapshot) {
        final canEdit = snapshot.data == true;

        final pages = <Widget>[
          const DashboardPage(),
          if (canEdit) const InputPage(),
          const ProfilePage(),
          const LanguagePage(),
        ];

        // Clamp index in case permissions changed
        final safeIndex = _selectedIndex.clamp(0, pages.length - 1);

        return pages[safeIndex];
      },
    );
  }

  /// -------- BOTTOM NAV --------
  Widget _buildBottomNav() {
    return FutureBuilder<bool>(
      future: RBACService().hasPermission(
        currentUserId!,
        Permission.writeOwnData,
      ),
      builder: (context, snapshot) {
        final canEdit = snapshot.data == true;

        final items = <BottomNavigationBarItem>[
          const BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          if (canEdit)
            const BottomNavigationBarItem(
              icon: Icon(Icons.input),
              label: 'Input',
            ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.language),
            label: 'Language',
          ),
        ];

        return BottomNavigationBar(
          items: items,
          currentIndex: _selectedIndex.clamp(0, items.length - 1),
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
        );
      },
    );
  }
}
