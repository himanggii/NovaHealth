import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/permissions.dart';
import '../services/rbac_service.dart';
import '../providers/auth_provider.dart';

class PermissionGate extends ConsumerWidget {
  final Permission requiredPermission;
  final Widget child;
  final Widget? fallback;

  const PermissionGate({
    super.key,
    required this.requiredPermission,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    if (user == null) {
      return fallback ?? const SizedBox.shrink();
    }

    return FutureBuilder<bool>(
      future: RBACService().hasPermission(user.id, requiredPermission),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }

        if (snapshot.data == true) {
          return child;
        }

        return fallback ?? const SizedBox.shrink();
      },
    );
  }
}
