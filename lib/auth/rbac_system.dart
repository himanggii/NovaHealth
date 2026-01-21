import '../auth/user_role.dart';
import '../auth/permissions.dart';
import '../services/database_service.dart';

class RBACService {
  static final RBACService _instance = RBACService._internal();
  factory RBACService() => _instance;
  RBACService._internal();

  final DatabaseService _db = DatabaseService();

  /// Get user role (defaults to 'user')
  Future<UserRole> getUserRole(String userId) async {
    final roleStr = await _db.getSetting(
      'user_role_$userId',
      defaultValue: 'user',
    );
    return _parseRole(roleStr);
  }

  /// Admin-only operation
  Future<bool> setUserRole(
    String userId,
    UserRole role, {
    required String adminUserId,
  }) async {
    final adminRole = await getUserRole(adminUserId);

    if (!adminRolePermissions(
      adminRole,
    ).contains(Permission.manageSystemSettings)) {
      return false;
    }

    await _db.saveSetting('user_role_$userId', role.name);
    return true;
  }

  /// Check permission
  Future<bool> hasPermission(String userId, Permission permission) async {
    final role = await getUserRole(userId);
    return adminRolePermissions(role).contains(permission);
  }

  /// Healthcare data access check
  Future<bool> canAccessData(
    String requesterId,
    String ownerId, {
    bool writeAccess = false,
  }) async {
    if (requesterId == ownerId) return true;

    final role = await getUserRole(requesterId);
    if (role != UserRole.healthcareViewer || writeAccess) return false;

    final hasAccess = await _db.getSetting(
      'healthcare_access_${ownerId}_$requesterId',
      defaultValue: false,
    );

    return hasAccess;
  }

  /// Grant access
  Future<bool> grantHealthcareAccess({
    required String dataOwnerId,
    required String healthcareViewerId,
    DateTime? expiresAt,
  }) async {
    final role = await getUserRole(healthcareViewerId);
    if (role != UserRole.healthcareViewer) return false;

    await _db.saveSetting(
      'healthcare_access_${dataOwnerId}_$healthcareViewerId',
      true,
    );

    if (expiresAt != null) {
      await _db.saveSetting(
        'healthcare_access_expiry_${dataOwnerId}_$healthcareViewerId',
        expiresAt.toIso8601String(),
      );
    }

    return true;
  }

  Future<void> revokeHealthcareAccess({
    required String dataOwnerId,
    required String healthcareViewerId,
  }) async {
    await _db.deleteSetting(
      'healthcare_access_${dataOwnerId}_$healthcareViewerId',
    );
    await _db.deleteSetting(
      'healthcare_access_expiry_${dataOwnerId}_$healthcareViewerId',
    );
  }

  // ---- Permission Map ----
  static Set<Permission> adminRolePermissions(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return {
          Permission.readOwnData,
          Permission.writeOwnData,
          Permission.deleteOwnData,
          Permission.exportOwnData,
          Permission.viewAnonymizedAnalytics,
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

  UserRole _parseRole(String roleStr) {
    switch (roleStr) {
      case 'admin':
        return UserRole.admin;
      case 'healthcareViewer':
        return UserRole.healthcareViewer;
      default:
        return UserRole.user;
    }
  }
}
