// Debug-only entry point for the web target. Wires the real HomeScreen
// with stub services so we can iterate on the UI in Chrome via
// `flutter run -d chrome -t lib/main_web.dart`.
//
// Do NOT ship — auth/api/speech are faked, no real network calls.

import 'package:flutter/material.dart';
import 'screens/dictionary_screen.dart';
import 'screens/home_screen.dart';
import 'screens/scratchpad_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/snippets_screen.dart';
import 'screens/style_screen.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/speech_service.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'widgets/sidebar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageService.init();
  runApp(const FlowDebugApp());
}

// ── Stub services ──────────────────────────────────────────────────

class _StubAuth extends AuthService {
  _StubAuth() {
    // Seed the parent's private fields via its public setters where
    // available, and via injected data otherwise. Only `userName` is
    // actually read by HomeScreen.
  }
  @override
  String get userName => 'Moses';
  @override
  String get userEmail => 'moses@example.com';
}

class _StubApi extends ApiService {
  _StubApi(super.auth);

  @override
  Future<List<Map<String, dynamic>>> getDictations({
    int limit = 50,
    int offset = 0,
  }) async {
    // Give the UI enough variety to exercise the chips + empty states.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return [
      {
        'id': '1',
        'text':
            "Hey team, just pushed the new sticky header. Let me know what you think when you have a sec.",
        'language': 'en',
        'grammar_applied': true,
        'created_at':
            DateTime.now().subtract(const Duration(minutes: 4)).toIso8601String(),
        'word_count': 20,
      },
      {
        'id': '2',
        'text':
            'Нужно ещё проверить фильтры по языкам — похоже чипы работают.',
        'language': 'ru',
        'created_at':
            DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        'word_count': 10,
      },
      {
        'id': '3',
        'text': 'Reminder: schedule the standup for Thursday.',
        'language': 'en',
        'created_at': DateTime.now()
            .subtract(const Duration(hours: 6))
            .toIso8601String(),
        'word_count': 6,
      },
      {
        'id': '4',
        'text': 'Ещё одна заметка на русском языке для проверки.',
        'language': 'Russian',
        'created_at':
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String(),
        'word_count': 8,
      },
      {
        'id': '5',
        'text': 'Short test.',
        'language': 'en-US',
        'created_at':
            DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
        'word_count': 2,
      },
      // Filler so scrolling engages the sticky band for debug.
      for (var i = 6; i < 30; i++)
        {
          'id': '$i',
          'text':
              'Filler dictation #$i — scrolling under the sticky chip band to exercise frosted-glass blur.',
          'language': i.isEven ? 'en' : 'ru',
          'created_at':
              DateTime.now().subtract(Duration(days: i)).toIso8601String(),
          'word_count': 14,
        },
    ];
  }

  @override
  Future<bool> deleteDictation(String id) async => true;

  @override
  Future<bool> correctDictation({
    required String id,
    required String correctedText,
    List<String>? qualityTags,
  }) async => true;

  // ── Dictionary stubs ────────────────────────────────────────────
  final List<Map<String, dynamic>> _dictionary = [
    {'id': '1', 'word': 'postgis', 'replacement': 'PostGIS'},
    {'id': '2', 'word': 'kubernetes', 'replacement': 'Kubernetes'},
    {'id': '3', 'word': 'foo', 'replacement': null},
  ];

  @override
  Future<List<Map<String, dynamic>>> getDictionary() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return List.of(_dictionary);
  }

  @override
  Future<bool> addDictionaryEntry({
    required String word,
    String? replacement,
    bool isShared = false,
  }) async {
    _dictionary.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'word': word,
      'replacement': replacement,
    });
    return true;
  }

  @override
  Future<bool> deleteDictionaryEntry(String id) async {
    _dictionary.removeWhere((e) => e['id'] == id);
    return true;
  }

  // ── Snippet stubs ───────────────────────────────────────────────
  final List<Map<String, dynamic>> _snippets = [
    {
      'id': '1',
      'trigger_phrase': 'intro email',
      'expansion':
          'Hi team,\n\nHope you\'re doing well. Just wanted to quickly share…',
    },
    {
      'id': '2',
      'trigger_phrase': 'signoff',
      'expansion': 'Thanks,\nMoses',
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> getSnippets() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return List.of(_snippets);
  }

  @override
  Future<bool> addSnippet({
    required String triggerPhrase,
    required String expansion,
    bool isShared = false,
  }) async {
    _snippets.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'trigger_phrase': triggerPhrase,
      'expansion': expansion,
    });
    return true;
  }

  @override
  Future<bool> deleteSnippet(String id) async {
    _snippets.removeWhere((s) => s['id'] == id);
    return true;
  }
}

// ── App shell ──────────────────────────────────────────────────────

class FlowDebugApp extends StatefulWidget {
  const FlowDebugApp({super.key});

  @override
  State<FlowDebugApp> createState() => _FlowDebugAppState();
}

class _FlowDebugAppState extends State<FlowDebugApp> {
  NavItem _selected = NavItem.home;

  late final _StubAuth _auth = _StubAuth();
  late final _StubApi _api = _StubApi(_auth);
  late final SpeechService _speech = SpeechService();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flow Debug',
      debugShowCheckedModeBanner: false,
      theme: FlowTheme.build(),
      home: Scaffold(
        backgroundColor: FlowTokens.bgCanvasOpaque,
        body: Row(
          children: [
            Sidebar(
              selected: _selected,
              onSelect: (i) => setState(() => _selected = i),
              userName: 'Moses',
              plan: 'Basic',
              onAccountTap: () {},
            ),
            Expanded(
              child: switch (_selected) {
                NavItem.home => HomeScreen(
                    authService: _auth,
                    speechService: _speech,
                    apiService: _api,
                    isRecording: false,
                    isTranscribing: false,
                    onDictationCallback: (_) {},
                  ),
                NavItem.dictionary => DictionaryScreen(apiService: _api),
                NavItem.snippets => SnippetsScreen(apiService: _api),
                NavItem.style => const StyleScreen(),
                NavItem.scratchpad => const ScratchpadScreen(),
                NavItem.settings => const SettingsScreen(),
              },
            ),
          ],
        ),
      ),
    );
  }
}
