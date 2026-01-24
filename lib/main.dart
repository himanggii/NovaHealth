import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/theme.dart';
import 'config/routes.dart';
import 'services/database_service.dart';
import 'pages/auth/landing_page.dart';
import 'pages/auth/login_page.dart';
import 'pages/auth/signup_page.dart';
import 'pages/auth/gender_page.dart';
import 'pages/auth/forgot_password_page.dart';
import 'pages/home/home_page.dart';
import 'pages/profile/edit_profile_page.dart';
import 'pages/profile/change_password_page.dart';
import 'pages/settings/settings_page.dart';
import 'pages/tracking/workout_log_page.dart';
import 'pages/tracking/hydration_page.dart';
import 'pages/tracking/symptoms_page.dart';
import 'pages/tracking/period_tracker_page.dart';
import 'pages/nutrition/nutrition_page.dart';
import 'pages/nutrition/meal_plan_page.dart';
import 'pages/wellness/mood_tracker_page.dart';
import 'pages/wellness/meditation_page.dart';
import 'pages/settings/sync_test_page.dart';
import 'providers/auth_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'services/supabase_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'config/supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  // Supabase (optional)
  if (SupabaseConfig.isConfigured) {
    try {
      await SupabaseService().init(
        supabaseUrl: SupabaseConfig.supabaseUrl,
        supabaseAnonKey: SupabaseConfig.supabaseAnonKey,
      );
    } catch (_) {}
  }

  // Local storage
  await Hive.initFlutter();
  await DatabaseService().init();

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = ref.watch(isLoggedInProvider);

    return MaterialApp(
      title: 'NovaHealth',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: isLoggedIn ? AppRoutes.home : AppRoutes.landing,
      routes: {
        AppRoutes.landing: (_) => const LandingPage(),
        AppRoutes.login: (_) => const LoginPage(),
        AppRoutes.signup: (_) => const SignupPage(),
        AppRoutes.gender: (_) => const GenderPage(),
        AppRoutes.forgotPassword: (_) => const ForgotPasswordPage(),
        AppRoutes.home: (_) => const HomePage(),
        AppRoutes.editProfile: (_) => const EditProfilePage(),
        '/change-password': (_) => const ChangePasswordPage(),
        AppRoutes.settings: (_) => const SettingsPage(),
        AppRoutes.workoutLog: (_) => const WorkoutLogPage(),
        AppRoutes.hydration: (_) => const HydrationPage(),
        AppRoutes.symptoms: (_) => const SymptomsPage(),
        AppRoutes.periodTracker: (_) => const PeriodTrackerPage(),
        AppRoutes.nutrition: (_) => const NutritionPage(),
        AppRoutes.mealPlan: (_) => const MealPlanPage(),
        AppRoutes.moodTracker: (_) => const MoodTrackerPage(),
        AppRoutes.meditation: (_) => const MeditationPage(),
        AppRoutes.syncTest: (_) => const SyncTestPage(),
      },
    );
  }
}
