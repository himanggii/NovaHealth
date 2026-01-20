import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_model.dart';
import '../utils/constants.dart';
import 'database_service.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseService _db = DatabaseService();

  // ---------------- SIGN UP (FirebaseAuth + local DB only) ----------------

  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String username,
    String? fullName,
    String? gender,
    DateTime? dateOfBirth,
  }) async {
    print("AuthService.signUp started (MINIMAL, NO FIRESTORE)");

    try {
      // 1) Create account in Firebase Auth
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim().toLowerCase(),
        password: password,
      );
      print("FirebaseAuth createUserWithEmailAndPassword returned");

      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        print("FirebaseAuth user is null");
        return AuthResult(
          success: false,
          message: 'Failed to create account',
        );
      }

      // 2) Create UserModel
      final now = DateTime.now();
      final user = UserModel(
        id: firebaseUser.uid,
        email: email.trim().toLowerCase(),
        username: username.trim(),
        fullName: fullName?.trim(),
        gender: gender,
        dateOfBirth: dateOfBirth,
        createdAt: now,
        updatedAt: now,
        notificationPreferences: {
          'hydration': true,
          'workout': true,
          'meal': true,
          'period': true,
        },
      );

      // 3) Save locally (Hive) – this is how the rest of your app reads user data
      try {
        print("Saving user to local DatabaseService...");
        await _db.saveUser(user);
        print("Local user saved");
      } catch (e) {
        print("Local saveUser error: $e");
      }

      try {
        print("Saving auth flags to local settings...");
        await _db.saveSetting(AppConstants.keyIsLoggedIn, true);
        await _db.saveSetting(AppConstants.keyUserId, user.id);
        print("Local auth flags saved");
      } catch (e) {
        print("Local saveSetting error: $e");
      }

      print("AuthService.signUp returning success");
      return AuthResult(
        success: true,
        message: 'Account created successfully',
        user: user,
      );
    } on FirebaseAuthException catch (e) {
      print("FirebaseAuthException in signUp: ${e.code} - ${e.message}");
      String msg = 'Failed to create account';

      if (e.code == 'email-already-in-use') {
        msg = 'An account with this email already exists';
      } else if (e.code == 'weak-password') {
        msg = 'Password is too weak';
      }

      return AuthResult(success: false, message: msg);
    } catch (e) {
      print("Generic exception in AuthService.signUp: $e");
      return AuthResult(
        success: false,
        message: 'Failed to create account: ${e.toString()}',
      );
    }
  }

    // ---------------- LOGIN (email OR username, preserves username case) ----------------

  Future<AuthResult> login({
    required String email, // this is actually an identifier: email OR username
    required String password,
  }) async {
    print("AuthService.login started");

    final identifier = email.trim();
    String loginEmail;
    UserModel? matchedUser;

    // Get all known users from local DB (Hive)
    List<UserModel> allUsers = [];
    try {
      allUsers = _db.getAllUsers();
    } catch (e) {
      print("Error getting all users from DB: $e");
    }

    // Helper to find a user safely
    UserModel? _findUser(bool Function(UserModel u) test) {
      for (final u in allUsers) {
        if (test(u)) return u;
      }
      return null;
    }

    if (identifier.contains('@')) {
      // Treat as email
      final normalizedEmail = identifier.toLowerCase();
      matchedUser = _findUser(
        (u) => u.email.toLowerCase() == normalizedEmail,
      );
      loginEmail = normalizedEmail;
      print("Logging in with email: $loginEmail");
    } else {
      // Treat as username
      final usernameLower = identifier.toLowerCase();
      matchedUser = _findUser(
        (u) => u.username.toLowerCase() == usernameLower,
      );
      if (matchedUser == null) {
        print("No local user found for username '$identifier'");
        return AuthResult(
          success: false,
          message: 'Invalid email/username or password',
        );
      }
      loginEmail = matchedUser.email;
      print("Resolved username '$identifier' to email '$loginEmail'");
    }

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: loginEmail.trim().toLowerCase(),
        password: password,
      );
      print("FirebaseAuth signInWithEmailAndPassword returned");

      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        return AuthResult(
          success: false,
          message: 'Invalid email/username or password',
        );
      }

      // Prefer the local user we already know (keeps original username casing)
      UserModel? user = matchedUser;

      // If we somehow don't have a local user, create a basic one
      if (user == null) {
        print("No local user matched, creating fallback user");
        final now = DateTime.now();
        user = UserModel(
          id: firebaseUser.uid,
          email: firebaseUser.email ?? loginEmail.trim().toLowerCase(),
          username: loginEmail.contains('@')
              ? loginEmail.split('@').first
              : loginEmail,
          fullName: null,
          gender: null,
          dateOfBirth: null,
          createdAt: now,
          updatedAt: now,
          notificationPreferences: {
            'hydration': true,
            'workout': true,
            'meal': true,
            'period': true,
          },
        );
      }

      // Save user back to local DB (but this will keep username as-is if we had matchedUser)
      try {
        await _db.saveUser(user);
      } catch (e) {
        print("Local saveUser in login error: $e");
      }

      // Restore user data from Supabase
      try {
        await _db.restoreUserData(user.id);
      } catch (e) {
        print("Data restore error: $e");
      }

      try {
        await _db.saveSetting(AppConstants.keyIsLoggedIn, true);
        await _db.saveSetting(AppConstants.keyUserId, user.id);
      } catch (e) {
        print("Local saveSetting in login error: $e");
      }

      return AuthResult(
        success: true,
        message: 'Login successful',
        user: user,
      );
    } on FirebaseAuthMultiFactorException catch (e) {
      // User has enrolled MFA — don't swallow this, let caller handle the flow
      print("FirebaseAuthMultiFactorException in login: ${e.message}");
      rethrow;
    } on FirebaseAuthException catch (e) {
      print("FirebaseAuthException in login: ${e.code} - ${e.message}");
      return AuthResult(
        success: false,
        message: 'Invalid email/username or password',
      );
    } catch (e) {
      print("Generic exception in login: $e");
      return AuthResult(
        success: false,
        message: 'Invalid email/username or password',
      );
    }
  }


  // ---------------- LOGOUT ----------------

  Future<void> logout() async {
    try {
      await _auth.signOut();
    } catch (e) {
      print("Error in FirebaseAuth.signOut: $e");
    }

    try {
      await _db.saveSetting(AppConstants.keyIsLoggedIn, false);
      await _db.deleteSetting(AppConstants.keyUserId);
    } catch (e) {
      print("Error clearing local auth settings: $e");
    }
  }

  // ---------------- HELPERS ----------------

  bool isLoggedIn() {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser != null) return true;

    final local = _db.getSetting(AppConstants.keyIsLoggedIn, defaultValue: false);
    return (local is bool) ? local : false;
  }

  UserModel? getCurrentUser() {
    try {
      final userId = _db.getSetting(AppConstants.keyUserId);
      if (userId == null) return null;
      return _db.getUser(userId);
    } catch (e) {
      print("getCurrentUser error: $e");
      return null;
    }
  }

  String? getCurrentUserId() {
    try {
      return _db.getSetting(AppConstants.keyUserId);
    } catch (e) {
      print("getCurrentUserId error: $e");
      return null;
    }
  }

  // ---------------- PASSWORD & ACCOUNT MGMT ----------------

  Future<AuthResult> updatePassword({
    required String userId,
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.uid != userId) {
        return AuthResult(
          success: false,
          message: 'Not authenticated',
        );
      }

      // NOTE: Proper re-auth requires EmailAuthProvider.credential; skipping for now.
      await user.updatePassword(newPassword);

      return AuthResult(
        success: true,
        message: 'Password updated successfully',
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult(
        success: false,
        message: 'Failed to update password: ${e.message}',
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'Failed to update password: ${e.toString()}',
      );
    }
  }

  Future<AuthResult> deleteAccount(String userId, String password) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.uid != userId) {
        return AuthResult(
          success: false,
          message: 'Not authenticated',
        );
      }

      try {
        await _db.deleteUser(user.uid);
        await _db.deleteSetting(AppConstants.keyUserId);
      } catch (e) {
        print("Local delete user error: $e");
      }

      await user.delete();
      await logout();

      return AuthResult(
        success: true,
        message: 'Account deleted successfully',
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult(
        success: false,
        message: 'Failed to delete account: ${e.message}',
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message: 'Failed to delete account: ${e.toString()}',
      );
    }
  }

  Future<AuthResult> resetPassword({
    required String email,
  }) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim().toLowerCase());
      return AuthResult(
        success: true,
        message: 'Password reset email sent if an account exists for this address',
      );
    } on FirebaseAuthException catch (_) {
      return AuthResult(
        success: true,
        message: 'Password reset email sent if an account exists for this address',
      );
    } catch (_) {
      return AuthResult(
        success: true,
        message: 'Password reset email sent if an account exists for this address',
      );
    }
  }
}

// ---------------- RESULT CLASS ----------------

class AuthResult {
  final bool success;
  final String message;
  final UserModel? user;

  AuthResult({
    required this.success,
    required this.message,
    this.user,
  });
}
