import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';
import 'services/auth_service.dart';
import 'signup_screen.dart';
import 'services/coach_max_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables from .env file
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const GymBuddyApp());
}

class GymBuddyApp extends StatelessWidget {
  const GymBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gym Buddy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final CoachMaxService _coachMaxService = CoachMaxService();
  bool _isInitializing = true;
  bool _hasCompletedOnboarding = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user != null) {
      final onboardingStatus = await _checkOnboardingStatus(user.id);
      await _coachMaxService.scheduleCoachMaxCheckIn(user.id);
      setState(() {
        _hasCompletedOnboarding = onboardingStatus;
        _isInitializing = false;
      });
    } else {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  Future<bool> _checkOnboardingStatus(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('user_profiles')
          .select('onboarding_completed')
          .eq('id', userId)
          .single();
      return response['onboarding_completed'] == true;
    } catch (e) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return const LoginScreen();
    } else if (!_hasCompletedOnboarding) {
      return const SignUpScreen();
    } else {
      return const HomeScreen();
    }
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  final CoachMaxService _coachMaxService = CoachMaxService();
  bool _isPasswordVisible = false;
  bool _isLoading = false;
  int _failedAttempts = 0;
  bool _isLockedOut = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 60),
                Icon(
                  Icons.fitness_center,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'GYM BUDDY',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Train Together, Grow Together',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 48),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  maxLength: 100,
                  buildCounter: (context,
                          {required currentLength,
                          required isFocused,
                          maxLength}) =>
                      null,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    hintText: 'Enter your email',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: !_isPasswordVisible,
                  maxLength: 128,
                  buildCounter: (context,
                          {required currentLength,
                          required isFocused,
                          maxLength}) =>
                      null,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter your password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _isPasswordVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPasswordVisible = !_isPasswordVisible;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                ),
                const SizedBox(height: 24),
                if (_isLockedOut)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red),
                    ),
                    child: const Text(
                      '🔒 Too many failed attempts. Please restart the app to try again.',
                      style: TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ElevatedButton(
                  onPressed: _isLoading || _isLockedOut
                      ? null
                      : () async {
                          if (_failedAttempts >= 5) {
                            setState(() => _isLockedOut = true);
                            return;
                          }

                          setState(() => _isLoading = true);

                          final error = await _authService.signIn(
                            email: _emailController.text.trim(),
                            password: _passwordController.text,
                          );

                          if (error == null) {
                            _failedAttempts = 0;
                            final user =
                                Supabase.instance.client.auth.currentUser;
                            if (user != null) {
                              final onboardingComplete =
                                  await _checkOnboardingStatus(user.id);
                              await _coachMaxService
                                  .scheduleCoachMaxCheckIn(user.id);
                              if (!mounted) return;
                              setState(() => _isLoading = false);
                              if (onboardingComplete) {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (context) => const HomeScreen(),
                                  ),
                                );
                              } else {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (context) => const SignUpScreen(),
                                  ),
                                );
                              }
                            }
                          } else {
                            setState(() {
                              _failedAttempts++;
                              _isLoading = false;
                              if (_failedAttempts >= 5) _isLockedOut = true;
                            });

                            if (!mounted) return;

                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _failedAttempts >= 4
                                      ? 'Login failed: 1 attempt remaining before lockout'
                                      : 'Login failed: $error',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'LOGIN',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Don't have an account? "),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const SignUpScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        'Sign Up',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _checkOnboardingStatus(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('user_profiles')
          .select('onboarding_completed')
          .eq('id', userId)
          .single();
      return response['onboarding_completed'] == true;
    } catch (e) {
      return false;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}