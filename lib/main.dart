import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'models/saved_account.dart';
import 'screens/account_picker_screen.dart';
import 'screens/app_shell.dart';
import 'screens/login_screen.dart';
import 'screens/permissions_screen.dart';
import 'services/activation_policy_service.dart';
import 'services/auth_service.dart';
import 'services/speech_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'widgets/flow_menu_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init persistent storage
  await StorageService.init();

  // window_manager is a macOS/desktop plugin — its MethodChannel has
  // no implementation on web and throws MissingPluginException. Skip
  // the native window setup entirely when running in a browser.
  if (!kIsWeb) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(800, 600),
      minimumSize: Size(700, 500),
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'Flow',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    // LSUIElement=true boots us as a tray-only agent (no Dock icon, no
    // menu bar). Promote to .regular now that the window is on screen
    // so the native PlatformMenuBar strip actually renders. Subsequent
    // show/hide toggles are driven from the Swift side (windowShouldClose
    // and StatusBarHelper).
    await ActivationPolicyService.regular();
  }

  runApp(const FlowApp());
}

class FlowApp extends StatefulWidget {
  const FlowApp({super.key});

  @override
  State<FlowApp> createState() => _FlowAppState();
}

enum AppScreen { loading, accountPicker, login, permissions, main }

class _FlowAppState extends State<FlowApp> {
  final AuthService _authService = AuthService();
  final SpeechService _speechService = SpeechService();
  // Shared with the native macOS menu bar so "About Flow" can resolve
  // a BuildContext for showAboutDialog without a per-screen hook.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  AppScreen _screen = AppScreen.loading;
  String? _prefilledEmail;

  @override
  void initState() {
    super.initState();
    _speechService.setAuthService(_authService);
    _setupNative();
    _bootstrap();
  }

  Future<void> _setupNative() async {
    await _speechService.setupStatusBar();
  }

  /// Decide where to land on launch:
  /// 1. Active session still valid → Home.
  /// 2. Saved-account list non-empty → picker (the user can silent-
  ///    auth into one of them, or fall through to the login form).
  /// 3. Nothing saved → login form.
  Future<void> _bootstrap() async {
    final storage = StorageService.instance;

    // (1) Fast path — last active session is still good.
    if (storage.hasAuth) {
      final ok = await _authService.tryAutoLogin();
      if (!mounted) return;
      if (ok) {
        await _checkPermissionsAndNavigate();
        return;
      }
    }

    // (2) Have saved accounts? Show the picker.
    if (storage.savedAccounts.isNotEmpty) {
      setState(() {
        _screen = AppScreen.accountPicker;
        _prefilledEmail = null;
      });
      return;
    }

    // (3) Fresh install — bare login form.
    setState(() => _screen = AppScreen.login);
  }

  Future<void> _onAccountPicked(SavedAccount account) async {
    // Try to activate the stashed tokens silently. If they're still
    // good, straight to Home; if the refresh also fails we fall
    // through to the login form with the email pre-filled so the
    // user only has to type the password.
    setState(() => _screen = AppScreen.loading);
    final ok = await _authService.trySilentAuthWith(account.email);
    if (!mounted) return;
    if (ok) {
      await _checkPermissionsAndNavigate();
    } else {
      setState(() {
        _prefilledEmail = account.email;
        _screen = AppScreen.login;
      });
    }
  }

  void _onSignInWithOther() {
    setState(() {
      _prefilledEmail = null;
      _screen = AppScreen.login;
    });
  }

  void _onLoggedIn() async {
    await _checkPermissionsAndNavigate();
  }

  void _onLoginBack() {
    // Tapping "back" from the full-login screen when there are saved
    // accounts takes the user back to the picker. Used by the login
    // screen's top-left caret when prefilledEmail was set.
    if (StorageService.instance.savedAccounts.isNotEmpty) {
      setState(() {
        _prefilledEmail = null;
        _screen = AppScreen.accountPicker;
      });
    }
  }

  Future<void> _checkPermissionsAndNavigate() async {
    final state = await _speechService.checkPermissions();
    final goToMain = state.allGranted;
    setState(() {
      _screen = goToMain ? AppScreen.main : AppScreen.permissions;
    });
  }

  void _onPermissionsGranted() {
    setState(() => _screen = AppScreen.main);
  }

  void _onLogout() async {
    // Keep the account in the saved list so the picker still shows
    // it. The user can always explicitly forget it from the picker
    // via the hover "×".
    await _authService.logout();
    if (!mounted) return;
    if (StorageService.instance.savedAccounts.isNotEmpty) {
      setState(() {
        _prefilledEmail = null;
        _screen = AppScreen.accountPicker;
      });
    } else {
      setState(() => _screen = AppScreen.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild the whole MaterialApp whenever the theme controller fires
    // (system brightness shift or user-selected mode change). This swaps
    // the ThemeData and the entire widget tree picks up the new palette.
    //
    // FlowMenuBar wraps MaterialApp so the native macOS menu bar is
    // always present, independent of which AppScreen is on screen. On
    // non-macOS platforms PlatformMenuBar is a no-op pass-through.
    return ListenableBuilder(
      listenable: FlowThemeController.instance,
      builder: (context, _) => FlowMenuBar(
        navigatorKey: _navigatorKey,
        child: MaterialApp(
          title: 'Flow',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,
          theme: FlowTheme.build(brightness: Brightness.light),
          darkTheme: FlowTheme.build(brightness: Brightness.dark),
          themeMode: switch (FlowThemeController.instance.mode) {
            FlowThemeMode.light => ThemeMode.light,
            FlowThemeMode.dark => ThemeMode.dark,
            FlowThemeMode.system => ThemeMode.system,
          },
          home: _routeForScreen(),
        ),
      ),
    );
  }

  Widget _routeForScreen() {
    return switch (_screen) {
      AppScreen.loading => const Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: CircularProgressIndicator(color: FlowTokens.accent),
          ),
        ),
      AppScreen.accountPicker => AccountPickerScreen(
          authService: _authService,
          onAccountPicked: _onAccountPicked,
          onSignInWithOther: _onSignInWithOther,
        ),
      AppScreen.login => LoginScreen(
          authService: _authService,
          onLoggedIn: _onLoggedIn,
          initialEmail: _prefilledEmail,
          onBack: _prefilledEmail != null ||
                  StorageService.instance.savedAccounts.isNotEmpty
              ? _onLoginBack
              : null,
        ),
      AppScreen.permissions => PermissionsScreen(
          onAllGranted: _onPermissionsGranted,
        ),
      AppScreen.main => AppShell(
          authService: _authService,
          speechService: _speechService,
          onLogout: _onLogout,
        ),
    };
  }
}
