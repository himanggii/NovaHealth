import '../auth/user_role.dart';
import '../auth/permissions.dart';
import 'database_service.dart';

class RBACService {
  static final RBACService _instance = RBACService._internal();
  factory RBACService() => _instance;
  RBACService._internal();

  final DatabaseService _db = DatabaseService();

  /// TEMP: returns user role from storage
  Future<UserRole> getUserRole(String userId) async {
    final roleStr = await _db.getSetting(
      'user_role_$userId',
      defaultValue: 'user',
    );

    switch (roleStr) {
      case 'admin':
        return UserRole.admin;
      case 'healthcareViewer':
        return UserRole.healthcareViewer;
      default:
        return UserRole.user;
    }
  }

  /// Check permission for user
  Future<bool> hasPermission(String userId, Permission permission) async {
    final role = await getUserRole(userId);
    return _permissionsForRole(role).contains(permission);
  }

  /// Permission mapping
  Set<Permission> _permissionsForRole(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return {
          Permission.readOwnData,
          Permission.writeOwnData,
          Permission.deleteOwnData,
          Permission.exportOwnData,
          Permission.manageSystemSettings,
        };
      case UserRole.healthcareViewer:
        return {Permission.readSharedData};
      case UserRole.user:
      default:
        return {
          Permission.readOwnData,
          Permission.writeOwnData,
          Permission.deleteOwnData,
          Permission.exportOwnData,
          Permission.shareWithHealthcare,
        };
    }
  }
}
