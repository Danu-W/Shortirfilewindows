import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shortir_file/app_update.dart';
import 'package:shortir_file/search_names.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const _supabaseAuthRedirectUrl = String.fromEnvironment(
  'SUPABASE_AUTH_REDIRECT_URL',
  defaultValue: 'shortirfile://login-callback/',
);
const _appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
const _photos = <String>{  '3fr',
  'ari',
  'arw',
  'avif',
  'bmp',
  'cr2',
  'cr3',
  'dng',
  'gif',
  'heic',
  'heif',
  'jpeg',
  'jpg',
  'nef',
  'orf',
  'png',
  'raf',
  'raw',
  'rw2',
  'tif',
  'tiff',
  'webp',
};
const _videos = <String>{
  '3gp',
  'avi',
  'mkv',
  'mov',
  'mp4',
  'm4v',
  'webm',
  'wmv',
};
const _documents = <String>{
  'csv',
  'doc',
  'docx',
  'epub',
  'key',
  'md',
  'numbers',
  'odt',
  'odp',
  'ods',
  'pages',
  'pdf',
  'ppt',
  'pptx',
  'rtf',
  'tsv',
  'txt',
  'xls',
  'xlsx',
};

const _freeFileLimitPerSort = 100;
const _freeSortsPerMonth = 3;
const _androidBannerAdUnitId = 'ca-app-pub-4753144649572694/4872282130';
const _androidTestBannerAdUnitId = 'ca-app-pub-3940256099942544/9214589741';
bool _adsReady = false;

bool get _hasSupabaseConfig =>
    _supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    try {
      await MobileAds.instance.initialize();
      _adsReady = true;
    } catch (_) {
      // Keep the app usable if an ad provider is unavailable or misconfigured.
    }
  }
  if (_hasSupabaseConfig) {
    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        publishableKey: _supabaseKey,
      );
    } catch (error) {
      // Continue without auth if Supabase fails to initialize.
    }
  }
  runApp(const ShortirApp());
}

class ShortirApp extends StatefulWidget {
  const ShortirApp({super.key});

  @override
  State<ShortirApp> createState() => _ShortirAppState();
}

class _ShortirAppState extends State<ShortirApp> {
  bool _english = false;
  bool _dark = false;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF286448);
    return MaterialApp(
      title: 'Shortir File',
      debugShowCheckedModeBanner: false,
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: green,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F3),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: green,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      home: ShortirAuthGate(
        english: _english,
        dark: _dark,
        onLanguage: _setLanguage,
        onTheme: () => setState(() => _dark = !_dark),
      ),
    );
  }

  void _setLanguage(bool value) {
    setState(() => _english = value);
    if (!_hasSupabaseConfig) return;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      Supabase.instance.client
          .from('user_preferences')
          .upsert({
            'user_id': user.id,
            'language': value ? 'en' : 'id',
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .then((_) {})
          .catchError((_) {});
    } catch (_) {}
  }
}

class ShortirHome extends StatefulWidget {
  const ShortirHome({
    required this.english,
    required this.dark,
    required this.onLanguage,
    required this.onTheme,
    super.key,
  });
  final bool english;
  final bool dark;
  final ValueChanged<bool> onLanguage;
  final VoidCallback onTheme;

  @override
  State<ShortirHome> createState() => _ShortirHomeState();
}

enum _ViewMode { list, grid }

List<String> mergeSearchNames(
  List<String> current,
  String input,
  Set<String> extensions,
) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return current;
  final names = detectFileNames(trimmed, extensions: extensions);
  return {...current, ...(names.isEmpty ? [trimmed] : names)}.toList();
}

enum _AuthScreen { signIn, signUp, forgotPassword, updatePassword }

enum _AccountDialogResult { signedIn, passwordUpdated }

enum _SignedInAction { close, changePassword, signOut }

class _FileOperationEntry {
  const _FileOperationEntry({
    required this.sourcePath,
    required this.destinationPath,
    required this.operation,
    required this.createdAt,
    this.createdFolder,
  });

  final String sourcePath;
  final String destinationPath;
  final String operation;
  final DateTime createdAt;
  final String? createdFolder;

  Map<String, dynamic> toJson() => {
    'sourcePath': sourcePath,
    'destinationPath': destinationPath,
    'operation': operation,
    'createdAt': createdAt.toIso8601String(),
    if (createdFolder != null) 'createdFolder': createdFolder,
  };

  factory _FileOperationEntry.fromJson(Map<String, dynamic> json) {
    return _FileOperationEntry(
      sourcePath: json['sourcePath'] as String? ?? '',
      destinationPath: json['destinationPath'] as String? ?? '',
      operation: json['operation'] as String? ?? 'move',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      createdFolder: json['createdFolder'] as String?,
    );
  }
}

class _SortRule {
  const _SortRule({
    required this.type,
    required this.value,
    required this.destination,
  });

  final String type;
  final String value;
  final String destination;

  Map<String, dynamic> toJson() => {
    'type': type,
    'value': value,
    'destination': destination,
  };

  factory _SortRule.fromJson(Map<String, dynamic> json) => _SortRule(
    type: json['type'] as String? ?? 'extension',
    value: json['value'] as String? ?? '',
    destination: json['destination'] as String? ?? '',
  );
}

class ShortirAuthGate extends StatefulWidget {
  const ShortirAuthGate({
    required this.english,
    required this.dark,
    required this.onLanguage,
    required this.onTheme,
    super.key,
  });

  final bool english;
  final bool dark;
  final ValueChanged<bool> onLanguage;
  final VoidCallback onTheme;

  @override
  State<ShortirAuthGate> createState() => _ShortirAuthGateState();
}

class _ShortirAuthGateState extends State<ShortirAuthGate> {
  StreamSubscription<AuthState>? _authSubscription;
  late bool _signedIn;
  bool _recoveryDialogOpen = false;

  String t(String id, String en) => widget.english ? en : id;

  @override
  void initState() {
    super.initState();
    _signedIn = _hasSupabaseConfig
        ? Supabase.instance.client.auth.currentSession != null
        : false;
    if (_hasSupabaseConfig) {
      try {
        _authSubscription = Supabase.instance.client.auth.onAuthStateChange
            .listen((state) {
              if (!mounted) return;
              setState(() {
                _signedIn =
                    Supabase.instance.client.auth.currentSession != null;
              });
              if (state.event == AuthChangeEvent.passwordRecovery) {
                _showPasswordRecoveryDialog();
              }
            });
      } catch (_) {}
    }
  }

  Future<void> _showPasswordRecoveryDialog() async {
    if (_recoveryDialogOpen || !mounted) return;
    _recoveryDialogOpen = true;
    final result = await showDialog<_AccountDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AccountAuthDialog(
        client: Supabase.instance.client,
        english: widget.english,
        initialScreen: _AuthScreen.updatePassword,
      ),
    );
    _recoveryDialogOpen = false;
    if (result == _AccountDialogResult.passwordUpdated && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('Kata sandi berhasil diperbarui.', 'Password updated.'),
          ),
        ),
      );
    }
  }

  Future<void> _openAuth(_AuthScreen screen) async {
    if (!_hasSupabaseConfig) return;
    try {
      await showDialog<_AccountDialogResult>(
        context: context,
        builder: (context) => _AccountAuthDialog(
          client: Supabase.instance.client,
          english: widget.english,
          initialScreen: screen,
        ),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_signedIn) {
      return ShortirHome(
        english: widget.english,
        dark: widget.dark,
        onLanguage: widget.onLanguage,
        onTheme: widget.onTheme,
      );
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/shortir_file_icon.png',
                width: 38,
                height: 38,
              ),
            ),
            const SizedBox(width: 11),
            const Text(
              'Shortir File',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => widget.onLanguage(!widget.english),
            child: Text(widget.english ? 'EN' : 'ID'),
          ),
          IconButton(
            onPressed: widget.onTheme,
            tooltip: t('Ganti tema', 'Toggle theme'),
            icon: Icon(
              widget.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(25),
                      child: Image.asset(
                        'assets/shortir_file_icon.png',
                        width: 72,
                        height: 72,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      t(
                        'Atur semua berkas dengan mudah.',
                        'Organize all your files with ease.',
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      t(
                        'Masuk atau buat akun untuk melanjutkan ke aplikasi.',
                        'Sign in or create an account to continue.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _openAuth(_AuthScreen.signIn),
                        icon: const Icon(Icons.login),
                        label: Text(t('Masuk', 'Sign in')),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _openAuth(_AuthScreen.signUp),
                        icon: const Icon(Icons.person_add_alt_1),
                        label: Text(t('Buat akun baru', 'Create an account')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShortirHomeState extends State<ShortirHome> with WidgetsBindingObserver {
  static const _safChannel = MethodChannel('storyties/saf');
  static const _updateNotifyChannel = MethodChannel('storyties/updates');
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  String? _destFolder;
  String? _newDestFolderCreated;
  Directory? _folder;
  List<File> _files = [];
  final Set<String> _selected = {};
  String _kind = 'photos';
  String _extensionFilter = 'all';
  String _fileOperation = 'move';
  bool _clearingPastedSearch = false;
  bool _busy = false;
  bool _isPro = false;
  bool _planLoaded = false;
  int _sortsUsed = 0;
  String? _message;
  String? _lastPaymentOrderId;
  List<String> _searchNames = [];
  BannerAd? _bannerAd;
  final List<_FileOperationEntry> _operationHistory = [];
  final List<_FileOperationEntry> _redoHistory = [];
  final List<_SortRule> _sortRules = [];
  final Set<String> _excludedPaths = {};
  bool _cancelRequested = false;
  int _processedCount = 0;
  int _totalCount = 0;
  AppUpdateInfo? _pendingUpdate;
  bool _checkingUpdate = false;
  bool _downloadingUpdate = false;
  bool _updatePromptShown = false;
  final _updateProgressNotifier = ValueNotifier<double>(0);
  String _sortMode = 'name';
  _ViewMode _viewMode = _ViewMode.list;
  static const _gridCell = 120.0;
  final Map<String, Future<Uint8List?>> _thumbFutures = {};
  final Map<String, int> _fileSizes = {};

  Future<Uint8List?> _thumbFuture(File file) {
    final key = file.path;
    return _thumbFutures.putIfAbsent(key, () async {
      if (key.startsWith('content://')) {
        try {
          return await _safChannel.invokeMethod<Uint8List>(
            'readThumbnail',
            {'uri': key, 'maxDim': 384},
          );
        } catch (_) {
          return null;
        }
      }
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty || bytes.length > 25 * 1024 * 1024) return null;
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: 384,
        );
        final frame = await codec.getNextFrame();
        final byteData = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        return byteData?.buffer.asUint8List();
      } catch (_) {
        return null;
      }
    });
  }

  String t(String id, String en) => widget.english ? en : id;

  String get _quotaOwner =>
      (_hasSupabaseConfig
          ? Supabase.instance.client.auth.currentUser?.id
          : null) ??
      'local';

  String get _currentMonth {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  int get _sortsLeft =>
      (_sortsUsed >= _freeSortsPerMonth ? 0 : _freeSortsPerMonth - _sortsUsed);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreAccountPreferences();
    _loadOperationHistory();
    _loadExcludedPaths();
    _loadSortRules();
    _loadPlan();
    _checkForUpdates();
    Timer.periodic(const Duration(hours: 6), (_) => _checkForUpdates());
    SharedPreferences.getInstance().then((prefs) {
      final mode = prefs.getString('file_view_mode');
      if (!mounted) return;
      setState(() {
        _viewMode = mode == 'grid' ? _ViewMode.grid : _ViewMode.list;
      });
    });
  }

  String get _bannerAdUnitId =>
      kReleaseMode ? _androidBannerAdUnitId : _androidTestBannerAdUnitId;

  void _loadBannerAd() {
    if (!Platform.isAndroid || !_adsReady || _bannerAd != null || _isPro) {
      return;
    }
    final banner = BannerAd(
      adUnitId: _bannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _bannerAd = null);
        },
        onAdLoaded: (ad) {
          if (mounted) setState(() => _bannerAd = ad as BannerAd);
        },
      ),
    );
    banner.load();
  }

  void _disposeBannerAd() {
    _bannerAd?.dispose();
    _bannerAd = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPlan();
    }
  }

  Future<void> _loadPlan() async {
    var isPro = false;
    if (_hasSupabaseConfig) {
      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          final entitlement = await Supabase.instance.client
              .from('billing_entitlements')
              .select('status, expires_at')
              .eq('user_id', user.id)
              .maybeSingle();
          final status = entitlement?['status'];
          isPro = status == 'active' || status == 'grace_period';
          final expiresAt = entitlement?['expires_at'];
          if (isPro && expiresAt != null) {
            final expiry = DateTime.tryParse(expiresAt.toString());
            if (expiry != null && expiry.isBefore(DateTime.now())) {
              isPro = false;
            }
          }
        }
      } catch (_) {}
    }
    final sortsUsed = await _readUsage();
    if (!mounted) return;
    setState(() {
      _isPro = isPro;
      _planLoaded = true;
      _sortsUsed = sortsUsed;
    });
    if (isPro) {
      _disposeBannerAd();
    } else {
      _loadBannerAd();
    }
  }

  Future<int> _readUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('sort_usage_$_quotaOwner');
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final month = data['month'] as String? ?? '';
        final count = (data['count'] as num?)?.toInt() ?? 0;
        if (month == _currentMonth) {
          return count;
        }
      } catch (_) {}
    }
    return 0;
  }

  Future<void> _recordSort() async {
    final prefs = await SharedPreferences.getInstance();
    final next = await _readUsage() + 1;
    await prefs.setString(
      'sort_usage_$_quotaOwner',
      jsonEncode({'month': _currentMonth, 'count': next}),
    );
    if (!mounted) return;
    setState(() {
      _sortsUsed = next;
    });
  }

  String get _historyKey => 'file_operation_history_$_quotaOwner';
  String get _excludedPathsKey => 'excluded_paths_$_quotaOwner';
  String get _sortRulesKey => 'sort_rules_$_quotaOwner';

  Future<void> _loadSortRules() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sortRulesKey);
    if (raw == null) return;
    try {
      final rules = (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(_SortRule.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _sortRules
          ..clear()
          ..addAll(rules);
      });
    } catch (_) {}
  }

  Future<void> _saveSortRules() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _sortRulesKey,
      jsonEncode(_sortRules.map((rule) => rule.toJson()).toList()),
    );
  }

  Future<void> _loadExcludedPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final paths = prefs.getStringList(_excludedPathsKey) ?? <String>[];
    if (!mounted) return;
    setState(() {
      _excludedPaths
        ..clear()
        ..addAll(paths);
    });
  }

  Future<void> _loadOperationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final entries = decoded
          .whereType<Map<String, dynamic>>()
          .map(_FileOperationEntry.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _operationHistory
          ..clear()
          ..addAll(entries);
      });
    } catch (_) {}
  }

  Future<void> _saveOperationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(
        _operationHistory.take(100).map((entry) => entry.toJson()).toList(),
      ),
    );
  }

  Future<void> _cleanupCreatedFolder(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return;
      if (await dir.list().isEmpty) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<(bool, String?)> _restoreEntry(_FileOperationEntry entry) async {
    try {
      final destination = File(entry.destinationPath);
      final source = File(entry.sourcePath);
      if (entry.operation == 'copy') {
        if (await destination.exists()) await destination.delete();
      } else if (await destination.exists() && !await source.exists()) {
        try {
          await destination.rename(source.path);
        } on FileSystemException {
          await destination.copy(source.path);
          await destination.delete();
        }
        if (await source.exists() &&
            !_files.any((file) => file.path == source.path)) {
          setState(() => _files.add(source));
        }
      }
      await _cleanupCreatedFolder(entry.createdFolder);
      return (true, null);
    } catch (error) {
      return (false, error.toString());
    }
  }

  Future<(bool, String?)> _reapplyEntry(_FileOperationEntry entry) async {
    try {
      final source = File(entry.sourcePath);
      final destination = File(entry.destinationPath);
      final createdFolder = entry.createdFolder;
      if (createdFolder != null && createdFolder.isNotEmpty) {
        await Directory(createdFolder).create(recursive: true);
      }
      if (entry.operation == 'copy') {
        if (await source.exists() && !await destination.exists()) {
          await source.copy(destination.path);
        }
      } else if (await source.exists() && !await destination.exists()) {
        try {
          await source.rename(destination.path);
        } on FileSystemException {
          await source.copy(destination.path);
          await source.delete();
        }
        if (!_files.any((file) => file.path == destination.path)) {
          setState(() => _files.add(destination));
        }
      }
      return (true, null);
    } catch (error) {
      return (false, error.toString());
    }
  }

  Future<void> _undoLastOperation() async {
    if (!await _requirePro()) return;
    if (!mounted) return;
    if (_operationHistory.isEmpty || _busy) return;
    final entry = _operationHistory.last;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Batalkan tindakan terakhir?', 'Undo last action?')),
        content: Text(
          t(
            'File akan dikembalikan ke lokasi sebelumnya.',
            'Files will be restored to their previous location.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Batal', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('Undo', 'Undo')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final result = await _restoreEntry(entry);
      if (!result.$1) {
        if (!mounted) return;
        setState(() => _busy = false);
        _showMessage(
          t('Undo gagal: ${result.$2}', 'Undo failed: ${result.$2}'),
        );
        return;
      }
      setState(() {
        _operationHistory.removeLast();
        _redoHistory.add(entry);
      });
      await _saveOperationHistory();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = t('Tindakan terakhir dibatalkan.', 'Last action undone.');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(t('Undo gagal: $error', 'Undo failed: $error'));
    }
  }

  Future<void> _undoAllOperations() async {
    if (!await _requirePro()) return;
    if (!mounted) return;
    if (_operationHistory.isEmpty || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Batalkan semua tindakan?', 'Undo all actions?')),
        content: Text(
          t(
            'Semua file akan dikembalikan ke lokasi sebelumnya.',
            'All files will be restored to their previous locations.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Batal', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('Undo Semua', 'Undo All')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final entries = List<_FileOperationEntry>.of(_operationHistory);
      final undone = <_FileOperationEntry>[];
      for (final entry in entries.reversed) {
        if (_cancelRequested) break;
        if ((await _restoreEntry(entry)).$1) undone.add(entry);
      }
      final failed = entries.length - undone.length;
      setState(() {
        _operationHistory
          ..clear()
          ..addAll(entries.where((entry) => !undone.contains(entry)));
        _redoHistory.addAll(undone.reversed);
      });
      await _saveOperationHistory();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = failed == 0
            ? t('Semua tindakan dibatalkan.', 'All actions undone.')
            : t(
                '${undone.length} tindakan dibatalkan, $failed gagal.',
                '${undone.length} actions undone, $failed failed.',
              );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(t('Undo gagal: $error', 'Undo failed: $error'));
    }
  }

  Future<void> _redoLastOperation() async {
    if (!await _requirePro()) return;
    if (!mounted) return;
    if (_redoHistory.isEmpty || _busy) return;
    final entry = _redoHistory.last;
    setState(() => _busy = true);
    try {
      final result = await _reapplyEntry(entry);
      if (!result.$1) {
        if (!mounted) return;
        setState(() => _busy = false);
        _showMessage(
          t('Redo gagal: ${result.$2}', 'Redo failed: ${result.$2}'),
        );
        return;
      }
      setState(() {
        _redoHistory.removeLast();
        _operationHistory.add(entry);
      });
      await _saveOperationHistory();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = t('Tindakan diulang kembali.', 'Action redone.');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(t('Redo gagal: $error', 'Redo failed: $error'));
    }
  }

  Future<void> _redoAllOperations() async {
    if (!await _requirePro()) return;
    if (!mounted) return;
    if (_redoHistory.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final entries = List<_FileOperationEntry>.of(_redoHistory);
      final redone = <_FileOperationEntry>[];
      for (final entry in entries.reversed) {
        if (_cancelRequested) break;
        if ((await _reapplyEntry(entry)).$1) redone.add(entry);
      }
      final failed = entries.length - redone.length;
      setState(() {
        _redoHistory
          ..clear()
          ..addAll(entries.where((entry) => !redone.contains(entry)));
        _operationHistory.addAll(redone.reversed);
      });
      await _saveOperationHistory();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = failed == 0
            ? t('Semua tindakan diulang kembali.', 'All actions redone.')
            : t(
                '${redone.length} tindakan diulang, $failed gagal.',
                '${redone.length} actions redone, $failed failed.',
              );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(t('Redo gagal: $error', 'Redo failed: $error'));
    }
  }

  Future<void> _showOperationHistory() async {
    if (!await _requirePro()) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Riwayat aktivitas', 'Activity history')),
        content: SizedBox(
          width: math.min(520, MediaQuery.sizeOf(context).width - 48),
          height: 360,
          child: _operationHistory.isEmpty
              ? Center(
                  child: Text(t('Belum ada aktivitas.', 'No activity yet.')),
                )
              : ListView.builder(
                  itemCount: _operationHistory.length,
                  itemBuilder: (context, index) {
                    final entry =
                        _operationHistory[_operationHistory.length - 1 - index];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        entry.operation == 'copy'
                            ? Icons.copy_outlined
                            : Icons.drive_file_move_outlined,
                      ),
                      title: Text(_fileName(File(entry.destinationPath))),
                      subtitle: Text(
                        '${entry.operation == 'copy' ? t('Disalin', 'Copied') : t('Dipindahkan', 'Moved')} • ${entry.createdAt.toLocal()}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _exportOperationLog,
            icon: const Icon(Icons.save_alt_outlined),
            label: Text(t('Simpan log', 'Save log')),
          ),
          TextButton.icon(
            onPressed: _exportMetadataBackup,
            icon: const Icon(Icons.backup_outlined),
            label: Text(t('Backup metadata', 'Metadata backup')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Tutup', 'Close')),
          ),
        ],
      ),
    );
  }

  Future<void> _exportOperationLog() async {
    if (!await _requirePro()) return;
    final folder = _folder;
    if (folder == null) {
      _showMessage(t('Pilih folder dulu.', 'Choose a folder first.'));
      return;
    }
    try {
      final logFile = File(
        '${folder.path}${Platform.pathSeparator}.shortir-operation-log.json',
      );
      await logFile.writeAsString(
        const JsonEncoder.withIndent(
          '  ',
        ).convert(_operationHistory.map((entry) => entry.toJson()).toList()),
      );
      if (mounted) {
        _showMessage(
          t('Log lokal berhasil disimpan.', 'Local log saved successfully.'),
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          t('Gagal menyimpan log: $error', 'Could not save log: $error'),
        );
      }
    }
  }

  Future<void> _exportMetadataBackup() async {
    if (!await _requirePro()) return;
    final folder = _folder;
    if (folder == null) {
      _showMessage(t('Pilih folder dulu.', 'Choose a folder first.'));
      return;
    }
    try {
      final backup = {
        'app': 'Shortir File',
        'version': '1.0.0+3',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'sourceFolder': folder.path,
        'operation': _fileOperation,
        'rules': _sortRules.map((rule) => rule.toJson()).toList(),
        'excludedPaths': _excludedPaths.toList(),
        'operations': _operationHistory.map((entry) => entry.toJson()).toList(),
      };
      await File(
        '${folder.path}${Platform.pathSeparator}.shortir-metadata-backup.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(backup));
      if (mounted) {
        _showMessage(
          t('Backup metadata berhasil disimpan.', 'Metadata backup saved.'),
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(t('Backup gagal: $error', 'Backup failed: $error'));
      }
    }
  }

  Future<void> _restoreAccountPreferences() async {
    if (!_hasSupabaseConfig) return;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final preference = await Supabase.instance.client
          .from('user_preferences')
          .select('language')
          .eq('user_id', user.id)
          .maybeSingle();
      if (preference != null && mounted) {
        widget.onLanguage(preference['language'] == 'en');
      }
    } catch (_) {}
  }

  List<File> get _filtered {
    final query = _search.text.trim().toLowerCase();
    final names = _searchNames.map(normalizeSearchName).toSet();
    final files = _files.where((file) {
      final filename = _fileName(file);
      if (_excludedPaths.contains(file.path)) return false;
      if (!_matchesFileType(file)) return false;
      if (names.isNotEmpty) {
        final fileNameKey = normalizeSearchName(filename);
        return names.any(
          (name) => fileNameKey == name || fileNameKey.contains(name),
        );
      }
      if (query.isEmpty) return true;
      return filename.toLowerCase().contains(query);
    }).toList();
    files.sort((a, b) {
      switch (_sortMode) {
        case 'size':
          return _safeLength(a).compareTo(_safeLength(b));
        case 'date':
          return _safeModified(a).compareTo(_safeModified(b));
        case 'type':
          return _fileExtension(a).compareTo(_fileExtension(b));
        default:
          return _fileName(
            a,
          ).toLowerCase().compareTo(_fileName(b).toLowerCase());
      }
    });
    return files;
  }

  String _fileName(File file) {
    final path = file.path;
    if (path.startsWith('content://')) {
      final decoded = Uri.decodeComponent(path.split('/').last);
      final segments = decoded.split('/');
      return segments.isNotEmpty ? segments.last : decoded;
    }
    final segments = path.split(RegExp(r'[\/\\]'));
    return segments.isNotEmpty ? segments.last : path;
  }

  int _safeLength(File file) {
    try {
      return file.lengthSync();
    } catch (_) {
      return 0;
    }
  }

  DateTime _safeModified(File file) {
    try {
      return file.statSync().modified;
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  String _fileExtension(File file) {
    final filename = _fileName(file);
    final dotIndex = filename.lastIndexOf('.');
    return dotIndex > 0 && dotIndex < filename.length - 1
        ? filename.substring(dotIndex + 1).toLowerCase()
        : '';
  }

  String _mimeForExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
        return 'text/plain';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.ms-excel';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'mp3':
        return 'audio/mpeg';
      default:
        return 'application/octet-stream';
    }
  }

  bool _matchesFileType(File file) {
    final extension = _fileExtension(file);
    if (!_matchesFileKind(file)) return false;
    return _extensionFilter == 'all' || extension == _extensionFilter;
  }

  bool _matchesFileKind(File file) {
    final extension = _fileExtension(file);
    final matchesKind = switch (_kind) {
      'photos' => _photos.contains(extension),
      'documents' => _documents.contains(extension),
      _ => _photos.contains(extension) || _documents.contains(extension),
    };
    return matchesKind;
  }

  bool _nameHasMatch(String name) {
    final key = normalizeSearchName(name);
    return key.isNotEmpty &&
        _files.any((file) {
          // Report a name as found even when its format is hidden by the
          // currently selected format filter.
          if (!_matchesFileKind(file)) return false;
          final fileKey = normalizeSearchName(_fileName(file));
          return fileKey == key || fileKey.contains(key);
        });
  }

  List<String> get _missingSearchNames =>
      _searchNames.where((name) => !_nameHasMatch(name)).toList();

  Set<String> get _searchExtensions => switch (_kind) {
    'photos' => _photos,
    'documents' => _documents,
    _ => {..._photos, ..._documents},
  };

  List<String> get _availableExtensions => switch (_kind) {
    'photos' => _photos.toList()..sort(),
    'documents' => _documents.toList()..sort(),
    _ => {..._photos, ..._documents}.toList()..sort(),
  };

  void _updateSearch(String value) {
    if (_clearingPastedSearch) return;
    final hasListSeparators = RegExp(r'[ \r\n,;\t]').hasMatch(value);
    if (hasListSeparators) {
      final names = detectFileNames(value, extensions: _searchExtensions);
      if (names.isNotEmpty) {
        _clearingPastedSearch = true;
        setState(() {
          _searchNames = mergeSearchNames(
            _searchNames,
            value,
            _searchExtensions,
          );
        });
        _search.clear();
        _clearingPastedSearch = false;
      }
    }
  }

  void _removeSearchName(String name) {
    setState(() {
      _searchNames = _searchNames.where((item) => item != name).toList();
    });
  }

  void _commitSearch(String value) {
    if (value.trim().isEmpty) return;
    final merged = mergeSearchNames(_searchNames, value, _searchExtensions);
    final addedCount = merged.length - _searchNames.length;
    setState(() => _searchNames = merged);
    _search.clear();
    _searchFocus.requestFocus();
    if (addedCount == 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('Nama sudah ada di daftar.', 'Name already in list.'),
          ),
        ),
      );
    }
  }

  Future<void> _previewFile(File file) async {
    if (!await _requirePro()) return;
    if (!mounted) return;
    final extension = _fileExtension(file);
    if (_photos.contains(extension)) {
      Widget image;
      if (file.path.startsWith('content://')) {
        Uint8List? bytes;
        try {
          bytes = await _safChannel.invokeMethod<Uint8List>(
            'readBytes',
            {'uri': file.path, 'maxBytes': 15 * 1024 * 1024},
          );
        } catch (_) {
          bytes = null;
        }
        if (bytes == null) {
          _showMessage(
            t('Tidak dapat membaca gambar.', 'Could not read image.'),
          );
          return;
        }
        image = Image.memory(bytes, fit: BoxFit.contain);
      } else {
        image = Image.file(file, fit: BoxFit.contain);
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: InteractiveViewer(child: image),
        ),
      );
      return;
    } else {
      final opened = await launchUrl(
        file.path.startsWith('content://')
            ? Uri.parse(file.path)
            : Uri.file(file.path),
      );
      if (!opened && mounted) {
        _showMessage(t('Tidak bisa membuka berkas.', 'Could not open file.'));
      }
      return;
    }
  }

  Future<void> _findDuplicates() async {
    if (!await _requirePro()) return;
    if (!mounted) return;
    final criterion = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(t('Cari duplikat berdasarkan', 'Find duplicates by')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'name'),
            child: Text(t('Nama file', 'File name')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'size'),
            child: Text(t('Ukuran file', 'File size')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'content'),
            child: Text(t('Isi file (hash)', 'File content (hash)')),
          ),
        ],
      ),
    );
    if (criterion == null) return;
    final groups = <String, List<File>>{};
    for (final file in _files.where(
      (file) => !_excludedPaths.contains(file.path),
    )) {
      String key;
      if (criterion == 'name') {
        key = _fileName(file).toLowerCase();
      } else if (criterion == 'size') {
        key = '${_safeLength(file)}';
      } else {
        key = sha256.convert(await file.readAsBytes()).toString();
      }
      groups.putIfAbsent(key, () => <File>[]).add(file);
    }
    final duplicates = groups.values
        .where((group) => group.length > 1)
        .toList();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('File duplikat', 'Duplicate files')),
        content: SizedBox(
          width: math.min(560, MediaQuery.sizeOf(context).width - 48),
          height: 360,
          child: duplicates.isEmpty
              ? Center(
                  child: Text(t('Tidak ada duplikat.', 'No duplicates found.')),
                )
              : ListView(
                  children: [
                    for (final group in duplicates)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${group.length} file'),
                              for (final file in group)
                                Text(
                                  _fileName(file),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Tutup', 'Close')),
          ),
        ],
      ),
    );
  }

  String _ruleLabel(_SortRule rule) {
    final condition = switch (rule.type) {
      'extension' => '${t('Tipe', 'Type')}: ${rule.value.toUpperCase()}',
      'size' => '${t('Ukuran minimal', 'Minimum size')}: ${rule.value} MB',
      'date' => '${t('Bulan', 'Month')}: ${rule.value}',
      _ => '${t('Nama mengandung', 'Name contains')}: ${rule.value}',
    };
    return '$condition → ${rule.destination}';
  }

  Future<void> _addSortRule() async {
    if (!await _requirePro()) return;
    if (!mounted) return;
    final rule = await showDialog<_SortRule>(
      context: context,
      builder: (context) => const _SortRuleDialog(),
    );
    if (rule == null) return;
    setState(() => _sortRules.add(rule));
    await _saveSortRules();
  }

  bool _matchesRule(File file, _SortRule rule) {
    switch (rule.type) {
      case 'extension':
        return _fileExtension(file) ==
            rule.value.toLowerCase().replaceFirst('.', '');
      case 'size':
        final minimumMb = double.tryParse(rule.value) ?? 0;
        return _safeLength(file) >= minimumMb * 1024 * 1024;
      case 'date':
        final modified = _safeModified(file);
        return '${modified.year}-${modified.month.toString().padLeft(2, '0')}' ==
            rule.value;
      default:
        return _fileName(file).toLowerCase().contains(rule.value.toLowerCase());
    }
  }

  Future<void> _applySortRules() async {
    if (!await _requirePro()) return;
    final folder = _folder;
    if (folder == null || _sortRules.isEmpty || _busy) return;
    final candidates = _files
        .where((file) => !_excludedPaths.contains(file.path))
        .toList();
    if (candidates.isEmpty) {
      _showMessage(
        t('Tidak ada file yang bisa diproses.', 'No files to process.'),
      );
      return;
    }
    setState(() {
      _busy = true;
      _cancelRequested = false;
      _processedCount = 0;
      _totalCount = candidates.length;
    });
    final processedPaths = <String>{};
    final entries = <_FileOperationEntry>[];
    try {
      for (final file in candidates) {
        if (_cancelRequested) break;
        final rule = _sortRules.cast<_SortRule?>().firstWhere(
          (item) => item != null && _matchesRule(file, item),
          orElse: () => null,
        );
        if (rule != null) {
          final destinationDir = Directory(
            '${folder.path}${Platform.pathSeparator}${_sanitizeFolderName(rule.destination)}',
          );
          final folderExisted = await destinationDir.exists();
          await destinationDir.create(recursive: true);
          final destinationPath = await _getUniqueDestinationPath(
            destinationDir.path,
            _fileName(file),
          );
          if (_fileOperation == 'copy') {
            await file.copy(destinationPath);
          } else {
            await file.rename(destinationPath);
          }
          processedPaths.add(file.path);
          entries.add(
            _FileOperationEntry(
              sourcePath: file.path,
              destinationPath: destinationPath,
              operation: _fileOperation,
              createdAt: DateTime.now(),
              createdFolder: folderExisted ? null : destinationDir.path,
            ),
          );
        }
        if (mounted) setState(() => _processedCount++);
      }
      _operationHistory.addAll(entries);
      await _saveOperationHistory();
      if (!mounted) return;
      setState(() {
        if (_fileOperation == 'move') {
          _files.removeWhere((file) => processedPaths.contains(file.path));
        }
        _busy = false;
        _cancelRequested = false;
        _message = t(
          '${entries.length} file berhasil diproses oleh aturan.',
          '${entries.length} files processed by rules.',
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _cancelRequested = false;
      });
      _showMessage(
        t('Aturan gagal dijalankan: $error', 'Rules failed: $error'),
      );
    }
  }

  Future<void> _showSortRules() async {
    if (!await _requirePro()) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Aturan sortir otomatis', 'Automatic sort rules')),
        content: SizedBox(
          width: math.min(560, MediaQuery.sizeOf(context).width - 48),
          height: 360,
          child: _sortRules.isEmpty
              ? Center(child: Text(t('Belum ada aturan.', 'No rules yet.')))
              : ListView.builder(
                  itemCount: _sortRules.length,
                  itemBuilder: (context, index) => ListTile(
                    dense: true,
                    title: Text(_ruleLabel(_sortRules[index])),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        setState(() => _sortRules.removeAt(index));
                        await _saveSortRules();
                        if (context.mounted) Navigator.pop(context);
                        if (mounted) _showSortRules();
                      },
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _addSortRule,
            icon: const Icon(Icons.add),
            label: Text(t('Tambah aturan', 'Add rule')),
          ),
          FilledButton.icon(
            onPressed: _sortRules.isEmpty ? null : _applySortRules,
            icon: const Icon(Icons.play_arrow),
            label: Text(t('Jalankan', 'Run')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Tutup', 'Close')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    _searchFocus.dispose();
    _destFolder = null;
      _newDestFolderCreated = null;
    _disposeBannerAd();
    super.dispose();
  }

  Future<void> _pickFilesIndividually() async {
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: t('Pilih berkas', 'Choose files'),
      );
      if (picked.isEmpty) return;
      final files = <File>[];
      for (final platformFile in picked) {
        final path = platformFile.path;
        if (path != null) files.add(File(path));
      }
      if (!mounted) return;
      setState(() {
        _folder = Directory('/storage/emulated/0');
        _files = files;
        _selected.clear();
        _destFolder = null;
      _newDestFolderCreated = null;
        _search.clear();
        _searchNames.clear();
        _message = t(
          '${files.length} berkas siap disortir.',
          '${files.length} files ready to sort.',
        );
      });
    } catch (_) {
      if (mounted) {
        _showMessage(
          t('Gagal membuka pemilih berkas.', 'Could not open file picker.'),
        );
      }
    }
  }

  Future<void> _resetWorkspace() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Reset tampilan?', 'Reset workspace?')),
        content: Text(
          t(
            'Kembali ke layar awal dan pilih folder lagi. Pilihan, pencarian, aturan, dan folder tujuan akan dibersihkan.',
            'Return to the start screen and pick a folder again. Selection, search, rules, and destination folder will be cleared.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Batal', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('Reset', 'Reset')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _files = [];
      _selected.clear();
      _destFolder = null;
      _newDestFolderCreated = null;
      _search.clear();
      _searchNames.clear();
      _excludedPaths.clear();
      _sortRules.clear();
      _message = null;
      _kind = 'photos';
      _extensionFilter = 'all';
      _fileOperation = 'move';
      _viewMode = _ViewMode.list;
    });
  }

  Future<void> _chooseFolder() async {
    try {
      if (Platform.isAndroid) {
        try {
          await _safChannel.invokeMethod<bool>('requestMediaPermissions');
        } catch (_) {
        }
        final treeUri = await _safChannel.invokeMethod<String>('pickFolder');
        if (treeUri == null || !mounted) return;
        final info = await _safChannel.invokeMethod<Map<dynamic, dynamic>>(
          'treeInfo',
          {'uri': treeUri},
        );
        final docId = info?['docId'] as String? ?? '';
        if (docId.isEmpty || docId.endsWith(':')) {
          if (!mounted) return;
          final useFilePicker = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                t('Folder tidak dikenali', 'Folder not recognized'),
              ),
              content: Text(
                t(
                  'Sistem mengembalikan penyimpanan utama (/storage/emulated/0), bukan folder yang kamu pilih. Ini biasa terjadi di Xiaomi untuk folder tertentu. Pilih file satu per satu, atau coba folder lain.',
                  'The system returned the main storage (/storage/emulated/0) instead of the folder you picked. This is common on Xiaomi for certain folders. Pick files individually, or try another folder.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(t('Batal', 'Cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    t('Pilih file satu per satu', 'Pick files individually'),
                  ),
                ),
              ],
            ),
          );
          if (!mounted) return;
          if (useFilePicker == true) {
            await _pickFilesIndividually();
          }
          return;
        }
        List<dynamic>? items;
        try {
          items = await _safChannel.invokeMethod<List<dynamic>>(
            'listFolder',
            {'uri': treeUri},
          );
        } on PlatformException catch (error) {
          if (error.code == 'denied' || error.code == 'bad_args') {
            items = null;
          } else {
            rethrow;
          }
        }
        final files = <File>[];
        _fileSizes.clear();
        for (final item in items ?? const []) {
          final map = Map<String, dynamic>.from(item as Map);
          if (map['isDirectory'] != true) {
            final uri = map['uri'] as String?;
            if (uri != null) {
              files.add(File(uri));
              _fileSizes[uri] = (map['size'] as num?)?.toInt() ?? 0;
            }
          }
        }
        if (items == null || files.isEmpty) {
          if (!mounted) return;
          final useFilePicker = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                t('Folder tidak dapat dibaca', 'Folder could not be read'),
              ),
              content: Text(
                t(
                  'Folder ini dilindungi privasi oleh sistem (misalnya folder Download). Pilih file satu per satu dari folder ini, atau pilih folder lain.',
                  'This folder is protected by the system privacy policy (e.g. the Downloads folder). Pick files individually from this folder, or choose another folder.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(t('Batal', 'Cancel')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(
                    t('Pilih file satu per satu', 'Pick files individually'),
                  ),
                ),
              ],
            ),
          );
          if (!mounted) return;
          if (useFilePicker == true) {
            await _pickFilesIndividually();
          }
          return;
        }
        if (!mounted) return;
        debugPrint('[ShortirDart] items=${items.length} files=${files.length}');        debugPrint(
          '[ShortirDart] firstNames=${files.take(5).map((f) => _fileName(f)).toList()}',
        );
        setState(() {
          _folder = Directory('/storage/emulated/0');
          _files = files;
          _selected.clear();
          _destFolder = null;
      _newDestFolderCreated = null;
          _search.clear();
          _searchNames.clear();
          _message = t(
            '${files.length} berkas siap disortir.',
            '${files.length} files ready to sort.',
          );
        });
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final lastFolderPath = prefs.getString('last_source_folder');
      String? initialDirectory;
      if (lastFolderPath != null && await Directory(lastFolderPath).exists()) {
        initialDirectory = lastFolderPath;
      } else if (Platform.isMacOS && await Directory('/Volumes').exists()) {
        initialDirectory = '/Volumes';
      }
      final path = await FilePicker.getDirectoryPath(
        dialogTitle: t('Pilih folder sumber', 'Choose a source folder'),
        initialDirectory: initialDirectory,
      );
      if (path == null) return;
      await prefs.setString('last_source_folder', path);
      await _loadFolder(Directory(path));
    } catch (error) {
      _showMessage(
        t(
          'Tidak dapat membuka folder: $error',
          'Could not open folder: $error',
        ),
      );
    }
  }

  Future<void> _loadFolder(Directory folder) async {
    if (!await folder.exists()) {
      _showMessage(t('Folder tidak ditemukan.', 'Folder not found.'));
      return;
    }
    final files = <File>[];
    await for (final entry in folder.list(followLinks: false)) {
      if (entry is File) {
        final filename = _fileName(entry);
        if (filename.startsWith('._') || filename == '.DS_Store') continue;
        files.add(entry);
      }
    }
    files.sort(
      (a, b) =>
          _fileName(a).toLowerCase().compareTo(_fileName(b).toLowerCase()),
    );
    if (!mounted) return;
    setState(() {
      _folder = folder;
      _files = files;
      _selected.clear();
      _destFolder = null;
      _newDestFolderCreated = null;
      _search.clear();
      _searchNames.clear();
      _message = t(
        '${files.length} berkas siap disortir.',
        '${files.length} files ready to sort.',
      );
    });
  }

  Future<void> _handleDroppedFiles(DropDoneDetails details) async {
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) return;
    final dropped = details.files;
    if (dropped.isEmpty) return;
    final candidate = Directory(dropped.first.path);
    if (await candidate.exists()) {
      await _loadFolder(candidate);
    } else {
      _showMessage(
        t(
          'Lepaskan folder sumber, bukan file.',
          'Drop a source folder, not a file.',
        ),
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _toolsButton(String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tune, size: 18, color: scheme.onPrimary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: scheme.onPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _requirePro() async {
    if (_isPro) return true;
    final upgrade = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Fitur Pro', 'Pro feature')),
        content: Text(
          t(
            'Fitur ini tersedia untuk paket Pro. Upgrade untuk membukanya.',
            'This feature is available on the Pro plan. Upgrade to unlock it.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Nanti', 'Later')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('Upgrade', 'Upgrade')),
          ),
        ],
      ),
    );
    if (upgrade == true) await _upgradeToPro();
    return false;
  }

  String _sanitizeFolderName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    var cleaned = trimmed.replaceAll(RegExp(r'[\/\\\:\*\?\"\<\>\|]'), '_');
    cleaned = cleaned.replaceAll(RegExp(r'^\.+$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return '';
    if (cleaned.length > 64) {
      cleaned = cleaned.substring(0, 64).trim();
    }
    return cleaned;
  }

  Future<String> _getUniqueDestinationPath(
    String targetDir,
    String filename,
  ) async {
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == filename.length - 1) {
      var candidate = '$targetDir${Platform.pathSeparator}$filename';
      var counter = 1;
      while (await File(candidate).exists() ||
          await Directory(candidate).exists()) {
        candidate = '$targetDir${Platform.pathSeparator}$filename ($counter)';
        counter++;
        if (counter > 1000) break;
      }
      return candidate;
    }
    final base = filename.substring(0, dotIndex);
    final ext = filename.substring(dotIndex);
    var candidate = '$targetDir${Platform.pathSeparator}$filename';
    var counter = 1;
    while (await File(candidate).exists() ||
        await Directory(candidate).exists()) {
      candidate = '$targetDir${Platform.pathSeparator}$base ($counter)$ext';
      counter++;
      if (counter > 1000) break;
    }
    return candidate;
  }

  Future<void> _processSelected() async {
    if (_folder == null || _selected.isEmpty) return;
    final selectedFiles = _files
        .where((file) => _selected.contains(file.path))
        .toList();
    await _runOperation(selectedFiles);
  }



  String? get _displayDestFolder {
    final folder = _destFolder;
    if (folder == null || folder.isEmpty) return null;
    final segments = folder
        .split(RegExp(r'[\\/]'))
        .where((segment) => segment.isNotEmpty)
        .toList();
    return segments.isNotEmpty ? segments.last : folder;
  }

  Future<void> _pickDestinationFolder() async {
    try {
      String? picked;
      if (Platform.isAndroid) {
        picked = await _safChannel.invokeMethod<String>(
          'pickDestinationFolder',
        );
      } else {
        picked = await FilePicker.getDirectoryPath(
          dialogTitle: t('Pilih folder tujuan', 'Choose a destination folder'),
        );
      }
      if (picked == null || !mounted) return;

      final controller = TextEditingController();
      final makeNew = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('Buat folder baru?', 'Create a new folder?')),
          content: TextField(
            controller: controller,
            autofocus: true,
            onSubmitted: (value) => Navigator.pop(context, true),
            decoration: InputDecoration(
              labelText: t('Nama folder baru (opsional)', 'New folder name (optional)'),
              hintText: t('Kosongkan untuk memakai folder ini', 'Leave empty to use this folder'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('Gunakan folder ini', 'Use this folder')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('Buat & Gunakan', 'Create & Use')),
            ),
          ],
        ),
      );
      if (!mounted) return;

      var target = picked;
      if (makeNew == true) {
        final name = _sanitizeFolderName(controller.text);
        if (name.isEmpty) {
          _showMessage(t('Nama folder kosong.', 'Folder name is empty.'));
          return;
        }
        if (Platform.isAndroid) {
          final uri = await _safChannel.invokeMethod<String>(
            'createSubfolder',
            {'treeUri': picked, 'name': name},
          );
          if (uri != null) {
            target = uri;
          } else {
            _showMessage(t('Gagal membuat folder.', 'Could not create folder.'));
            return;
          }
        } else {
          try {
            final dir = Directory('$picked${Platform.pathSeparator}$name');
            await dir.create(recursive: true);
            target = dir.path;
          } catch (_) {
            _showMessage(t('Gagal membuat folder.', 'Could not create folder.'));
            return;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _destFolder = target;
        _newDestFolderCreated = makeNew == true ? target : null;
      });
    } catch (_) {
      if (mounted) {
        _showMessage(
          t('Gagal memilih folder tujuan.', 'Could not choose destination folder.'),
        );
      }
    }
  }

  Future<void> _sendUpdateNotification(AppUpdateInfo info) async {
    try {
      await _updateNotifyChannel.invokeMethod(
        'notifyUpdateAvailable',
        {
          'title': t('Update Shortir File tersedia', 'Shortir File update available'),
          'body': t(
            'Versi $info tersedia. Buka aplikasi untuk mengunduh dan memasang.',
            'Version $info is available. Open the app to download and install.',
          ),
        },
      );
    } catch (_) {}
  }

  Future<void> _checkForUpdates() async {
    if (!Platform.isMacOS || _checkingUpdate) return;
    _checkingUpdate = true;
    try {
      final info = await AppUpdateChecker.checkLatest();
      if (info == null || !mounted) return;
      if (AppUpdateChecker.compareVersions(info.version, _appVersion) <= 0) return;
      setState(() => _pendingUpdate = info);
      _sendUpdateNotification(info);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_updatePromptShown) _promptUpdate();
      });
    } finally {
      _checkingUpdate = false;
    }
  }

  Future<void> _manualUpdateCheck() async {
    if (_checkingUpdate || _downloadingUpdate) return;
    _checkingUpdate = true;
    try {
      final info = await AppUpdateChecker.checkLatest();
      if (!mounted) return;
      if (info == null) {
        _showMessage(
          t('Gagal memeriksa update.', 'Could not check for updates.'),
        );
        return;
      }
      if (AppUpdateChecker.compareVersions(info.version, _appVersion) <= 0) {
        _showMessage(
          t(
            'Aplikasi sudah versi terbaru ($_appVersion).',
            'You are up to date ($_appVersion).',
          ),
        );
        return;
      }
      setState(() => _pendingUpdate = info);
      _updatePromptShown = false;
      _promptUpdate();
    } finally {
      _checkingUpdate = false;
    }
  }

  void _promptUpdate() {
    final info = _pendingUpdate;
    if (info == null) return;
    _updatePromptShown = true;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          t('Versi baru $info tersedia', 'New version $info is available'),
        ),
        content: Text(
          t(
            'Versi $_appVersion terpasang. Unduh dan pasang versi $info sekarang?',
            'Version $_appVersion is installed. Download and install version $info now?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Nanti', 'Later')),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _downloadAndInstall();
            },
            icon: const Icon(Icons.system_update_alt),
            label: Text(t('Unduh & Pasang', 'Download & Install')),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAndInstall() async {
    final info = _pendingUpdate;
    if (info == null || _downloadingUpdate) return;
    setState(() => _downloadingUpdate = true);
    _updateProgressNotifier.value = 0;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(t('Mengunduh update…', 'Downloading update…')),
        content: ValueListenableBuilder<double>(
          valueListenable: _updateProgressNotifier,
          builder: (context, progress, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 12),
              Text('${(progress * 100).toStringAsFixed(0)}%'),
            ],
          ),
        ),
      ),
    );
    String? error;
    try {
      final isAndroid = Platform.isAndroid;
      final fileUrl = isAndroid ? info.apkUrl : info.downloadUrl;
      if (fileUrl == null) {
        throw Exception('Tidak ada paket update untuk platform ini');
      }
      final tempDir = await Directory.systemTemp.createTemp('shortir_update');
      final fileName = isAndroid
          ? 'shortir-file-android.apk'
          : 'shortir-file-macos.zip';
      final filePath = '${tempDir.path}/$fileName';
      await AppUpdateChecker.downloadToFile(
        fileUrl,
        filePath,
        onProgress: (received, total) {
          if (!mounted) return;
          _updateProgressNotifier.value = total > 0 ? received / total : 0.0;
        },
      );
      final shaUrl = info.sha256Url;
      if (shaUrl != null) {
        final shaPath = '${tempDir.path}/$fileName.sha256';
        await AppUpdateChecker.downloadToFile(shaUrl, shaPath);
        final expected = (await File(shaPath).readAsString())
            .trim()
            .split(RegExp(r'\s+'))
            .first
            .toLowerCase();
        final actual = await AppUpdateChecker.sha256OfFile(filePath);
        if (expected != actual) {
          throw Exception('SHA-256 tidak cocok');
        }
      }
      if (isAndroid) {
        final installed = await _safChannel.invokeMethod<bool>(
          'installApk',
          {'path': filePath},
        );
        if (installed != true) {
          error = t(
            'Gagal memulai pemasangan APK.',
            'Could not start APK installation.',
          );
        } else {
          _showMessage(
            t(
              'APK terunduh. Ikuti langkah pemasangan di layar ponsel.',
              'APK downloaded. Follow the installation steps on your phone.',
            ),
          );
        }
      } else {
        final appPath = File(Platform.resolvedExecutable).parent.parent.path;
        if (!await AppUpdateChecker.parentWritable(appPath)) {
          error = t(
            'Tidak punya izin menulis ke folder aplikasi ("$appPath"). Pindahkan aplikasi ke folder yang bisa ditulis (mis. ~/Applications) lalu coba lagi.',
            'No write permission to the app folder ("$appPath"). Move the app to a writable folder (e.g. ~/Applications) and try again.',
          );
        } else {
          final installError = await AppUpdateChecker.installUpdate(
            currentPid: pid,
            appPath: appPath,
            zipPath: filePath,
            tempDirPath: tempDir.path,
          );
          if (installError == null) {
            exit(0);
          } else {
            error = installError;
          }
        }
      }
    } catch (_) {
      error = t(
        'Update gagal diunduh atau diverifikasi. Coba lagi nanti.',
        'Update failed to download or verify. Try again later.',
      );
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    setState(() => _downloadingUpdate = false);
    _updateProgressNotifier.value = 0;
    if (error != null) _showMessage(error);
  }

  Future<void> _runOperation(List<File> selectedFiles) async {
    final isCopy = _fileOperation == 'copy';
    final folder = _folder;
    if (folder == null || selectedFiles.isEmpty) return;
    if (_destFolder == null) {
      await _pickDestinationFolder();
      if (!mounted || _destFolder == null) return;
    }
    final destLabel = _displayDestFolder ?? '';
    if (!_isPro) {
      if (selectedFiles.length > _freeFileLimitPerSort) {
        _showMessage(
          t(
            'Paket Gratis maksimal $_freeFileLimitPerSort berkas per sortir. Upgrade ke Pro untuk tanpa batas.',
            'Free plan allows up to $_freeFileLimitPerSort files per sort. Upgrade to Pro for unlimited sorting.',
          ),
        );
        return;
      }
      final sortsUsed = await _readUsage();
      if (!mounted) return;
      setState(() {
        _sortsUsed = sortsUsed;
      });
      if (sortsUsed >= _freeSortsPerMonth) {
        _showMessage(
          t(
            'Kuota Gratis $_freeSortsPerMonth sortir bulan ini sudah habis. Upgrade ke Pro untuk melanjutkan.',
            'Free quota of $_freeSortsPerMonth sorts this month is used up. Upgrade to Pro to continue.',
          ),
        );
        return;
      }
    }
    String? androidTargetUri;
    final String targetDir;
    if (Platform.isAndroid) {
      androidTargetUri = _destFolder;
      targetDir = _destFolder!;
    } else {
      targetDir = _destFolder!;
      final targetDirObj = Directory(targetDir);
      if (!await targetDirObj.exists()) {
        _showMessage(
          t('Folder tujuan tidak ditemukan.', 'Destination folder not found.'),
        );
        return;
      }
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isCopy
              ? t('Salin berkas?', 'Copy files?')
              : t('Pindahkan berkas?', 'Move files?'),
        ),
        content: Text(
          t(
            isCopy
                ? 'Berkas terpilih akan disalin ke folder "$destLabel".'
                : 'Berkas terpilih akan dipindahkan ke folder "$destLabel".',
            isCopy
                ? 'Selected files will be copied to "$destLabel".'
                : 'Selected files will be moved to "$destLabel".',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Batal', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(isCopy ? t('Salin', 'Copy') : t('Pindahkan', 'Move')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _cancelRequested = false;
      _processedCount = 0;
      _totalCount = selectedFiles.length;
    });
    try {
      final processed = <String>{};
      final operationEntries = <_FileOperationEntry>[];
      for (final file in selectedFiles) {
        if (_cancelRequested) break;
        try {
          final filename = file.uri.pathSegments.last;
          final String destPath;
          if (androidTargetUri != null) {
            final mime = _mimeForExtension(_fileExtension(file));
            final destUri = await _safChannel.invokeMethod<String>(
              'transfer',
              {
                'srcUri': file.uri.toString(),
                'destTreeUri': androidTargetUri,
                'fileName': filename,
                'mime': mime,
                'keepSource': isCopy,
              },
            );
            if (destUri == null) throw Exception('transfer failed');
            destPath = destUri;
          } else {
            destPath = await _getUniqueDestinationPath(targetDir, filename);
          }
          if (androidTargetUri == null) {
            if (isCopy) {
              await file.copy(destPath);
            } else {
              await file.rename(destPath);
            }
          }
          processed.add(file.path);
          operationEntries.add(
            _FileOperationEntry(
              sourcePath: file.path,
              destinationPath: destPath,
              operation: isCopy ? 'copy' : 'move',
              createdAt: DateTime.now(),
              createdFolder: _newDestFolderCreated != null &&
                      destPath.startsWith(_newDestFolderCreated!)
                  ? _newDestFolderCreated
                  : null,
            ),
          );
        } catch (_) {
          // Skip files that fail to move and continue with others.
        }
        if (mounted) setState(() => _processedCount++);
      }
      _operationHistory.addAll(operationEntries);
      _redoHistory.clear();
      await _saveOperationHistory();
      if (!mounted) return;
      setState(() {
        if (!isCopy) {
          _files.removeWhere((file) => processed.contains(file.path));
        }
        _selected.clear();
        _busy = false;
        _message = _cancelRequested
            ? t(
                '${processed.length} berkas diproses sebelum dibatalkan.',
                '${processed.length} files processed before cancellation.',
              )
            : processed.isEmpty
            ? (isCopy
                  ? t(
                      'Tidak ada berkas yang berhasil disalin.',
                      'No files were copied.',
                    )
                  : t(
                      'Tidak ada berkas yang berhasil dipindahkan.',
                      'No files were moved.',
                    ))
            : t(
                isCopy
                    ? '${processed.length} berkas berhasil disalin.'
                    : '${processed.length} berkas berhasil dipindahkan.',
                isCopy
                    ? '${processed.length} files copied successfully.'
                    : '${processed.length} files moved successfully.',
              );
        _cancelRequested = false;
      });
      if (processed.isNotEmpty) {
        _destFolder = null;
      _newDestFolderCreated = null;
        if (!_isPro) {
          await _recordSort();
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(
        isCopy
            ? t('Penyalinan gagal: $error', 'Copy failed: $error')
            : t('Pemindahan gagal: $error', 'Move failed: $error'),
      );
    }
  }

  void _toggleSelectAll() {
    final files = _filtered;
    if (files.isEmpty) return;
    final allSelected = files.every((file) => _selected.contains(file.path));
    setState(() {
      if (allSelected) {
        for (final file in files) {
          _selected.remove(file.path);
        }
      } else {
        for (final file in files) {
          _selected.add(file.path);
        }
      }
    });
  }

  Future<void> _upgradeToPro() async {
    final plan = await showDialog<Map<String, Object>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Pilih paket Pro', 'Choose a Pro plan')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(t('Bulanan', 'Monthly')),
              subtitle: const Text('Rp15.000'),
              onTap: () =>
                  Navigator.pop(context, {'amount': 15000, 'name': 'Bulanan'}),
            ),
            ListTile(
              title: Text(t('Tahunan', 'Yearly')),
              subtitle: const Text('Rp150.000'),
              onTap: () =>
                  Navigator.pop(context, {'amount': 150000, 'name': 'Tahunan'}),
            ),
          ],
        ),
      ),
    );
    if (plan == null) return;
    if (!_hasSupabaseConfig) {
      _showMessage(
        t(
          'Login dulu ya buat upgrade ke Pro.',
          'Please sign in to upgrade to Pro.',
        ),
      );
      return;
    }
    try {
      final client = Supabase.instance.client;
      var user = client.auth.currentUser;
      if (user == null) {
        _showMessage(
          t(
            'Login dulu ya buat upgrade ke Pro.',
            'Please sign in to upgrade to Pro.',
          ),
        );
        return;
      }
      try {
        final refreshed = await client.auth.refreshSession();
        user = refreshed.user ?? client.auth.currentUser;
      } catch (_) {
        await client.auth.signOut();
        _showMessage(
          t(
            'Sesi login sudah kedaluwarsa. Silakan login kembali.',
            'Your login session expired. Please sign in again.',
          ),
        );
        return;
      }
      if (user == null) {
        _showMessage(
          t(
            'Login dulu ya buat upgrade ke Pro.',
            'Please sign in to upgrade to Pro.',
          ),
        );
        return;
      }
      final session = client.auth.currentSession;
      if (session == null || session.accessToken.isEmpty) {
        _showMessage(
          t(
            'Sesi login tidak tersedia. Silakan login kembali.',
            'No login session is available. Please sign in again.',
          ),
        );
        return;
      }
      _showMessage(t('Membuat QRIS...', 'Creating QRIS payment...'));
      final res = await client.functions.invoke(
        'create-midtrans-qris',
        body: {
          'amount': plan['amount'],
          'plan': plan['name'] == 'Tahunan' ? 'yearly' : 'monthly',
          'description': 'Shortir File Pro ${plan['name']}',
        },
      );
      String? url;
      String? qrBase64;
      if (res.data is Map) {
        final data = res.data as Map;
        url = data['qr_url'] as String?;
        qrBase64 = data['qr_base64'] as String?;
      } else if (res.data is String) {
        final data = jsonDecode(res.data as String) as Map;
        url = data['qr_url'] as String?;
        qrBase64 = data['qr_base64'] as String?;
      }
      if ((qrBase64 == null || qrBase64.isEmpty) &&
          (url == null || url.isEmpty)) {
        final details = res.data is Map ? (res.data as Map)['error'] : null;
        _showMessage(
          t(
            'Gagal membuat QRIS: ${details ?? res.data}',
            'Failed to create QR payment: ${details ?? res.data}',
          ),
        );
        return;
      }
      _lastPaymentOrderId = res.data is Map
          ? (res.data as Map)['order_id'] as String?
          : null;
      final qrBytes = qrBase64 == null ? null : base64Decode(qrBase64);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('Bayar ${plan['name']}', 'Pay ${plan['name']}')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 280,
                height: 280,
                child: qrBytes != null
                    ? Image.memory(qrBytes, fit: BoxFit.contain)
                    : Image.network(url!, fit: BoxFit.contain),
              ),
              const SizedBox(height: 12),
              Text(
                t(
                  'Pindai QRIS untuk menyelesaikan pembayaran.',
                  'Scan the QRIS code to complete payment.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('Tutup', 'Close')),
            ),
            TextButton(
              onPressed: () => launchUrl(
                Uri.parse(url!),
                mode: LaunchMode.externalApplication,
              ),
              child: Text(t('Buka browser', 'Open browser')),
            ),
          ],
        ),
      );
    } catch (error) {
      _showMessage(t('Gagal upgrade: $error', 'Failed to upgrade: $error'));
    }
  }

  Future<void> _checkPaymentStatus() async {
    if (!_hasSupabaseConfig) return;
    _showMessage(
      t('Memeriksa status pembayaran...', 'Checking payment status...'),
    );
    if (_lastPaymentOrderId != null) {
      try {
        await Supabase.instance.client.functions.invoke(
          'check-midtrans-status',
          body: {'order_id': _lastPaymentOrderId},
        );
      } catch (_) {}
    }
    await _loadPlan();
    if (!mounted) return;
    _showMessage(
      _isPro
          ? t(
              'Pembayaran terverifikasi. Pro aktif.',
              'Payment verified. Pro is active.',
            )
          : t(
              'Pembayaran belum terverifikasi.',
              'Payment has not been verified yet.',
            ),
    );
  }

  Future<void> _account() async {
    if (!_hasSupabaseConfig) {
      _showMessage(
        t(
          'Login belum dikonfigurasi. Hubungi pengelola aplikasi.',
          'Sign-in is not configured. Contact the app administrator.',
        ),
      );
      return;
    }
    try {
      final client = Supabase.instance.client;
      final signedInUser = client.auth.currentUser;
      if (signedInUser != null) {
        var plan = t('Gratis', 'Free');
        var isPro = false;
        String? expiresAt;
        String? provider;
        try {
          final entitlement = await client
              .from('billing_entitlements')
              .select('status, expires_at, provider, product_id')
              .eq('user_id', signedInUser.id)
              .maybeSingle();
          expiresAt = entitlement?['expires_at']?.toString();
          provider = entitlement?['provider']?.toString();
          if (entitlement?['status'] == 'active' ||
              entitlement?['status'] == 'grace_period') {
            plan = 'Pro';
            isPro = true;
          }
        } catch (_) {
          plan = t('Belum tersedia', 'Unavailable');
        }
        if (!mounted) return;
        final action = await showDialog<_SignedInAction>(
          context: context,
          builder: (context) => AlertDialog(
            scrollable: true,
            title: Text(t('Pengaturan akun', 'Account settings')),
            content: SizedBox(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.email_outlined),
                    title: Text(t('Email', 'Email')),
                    subtitle: Text(signedInUser.email ?? '-'),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.workspace_premium_outlined),
                    title: Text(t('Paket', 'Plan')),
                    subtitle: Text(
                      isPro && expiresAt != null
                          ? '$plan • ${t('aktif sampai', 'active until')} ${DateTime.tryParse(expiresAt)?.toLocal() ?? expiresAt}${provider == null ? '' : ' • $provider'}'
                          : plan,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.info_outline),
                    title: Text(t('Versi aplikasi', 'App version')),
                    subtitle: Text(_appVersion),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context, _SignedInAction.close);
                      _checkPaymentStatus();
                    },
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      t('Cek status pembayaran', 'Check payment status'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context, _SignedInAction.close);
                      _manualUpdateCheck();
                    },
                    icon: const Icon(Icons.system_update_alt),
                    label: Text(t('Cek update', 'Check for updates')),
                  ),
                  if (!isPro) ...[
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context, _SignedInAction.close);
                        _upgradeToPro();
                      },
                      icon: const Icon(Icons.upgrade_outlined),
                      label: Text(t('Upgrade ke Pro', 'Upgrade to Pro')),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, _SignedInAction.changePassword),
                child: Text(t('Ubah kata sandi', 'Change password')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, _SignedInAction.close),
                child: Text(t('Tutup', 'Close')),
              ),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.pop(context, _SignedInAction.signOut),
                icon: const Icon(Icons.logout),
                label: Text(t('Keluar', 'Sign out')),
              ),
            ],
          ),
        );
        if (action == _SignedInAction.signOut) {
          await client.auth.signOut();
          _showMessage(t('Kamu sudah keluar.', 'You are signed out.'));
        } else if (action == _SignedInAction.changePassword) {
          try {
            await client.auth.resetPasswordForEmail(
              signedInUser.email!,
              redirectTo: _supabaseAuthRedirectUrl,
            );
            _showMessage(
              t(
                'Tautan ubah kata sandi dikirim ke email kamu.',
                'A password reset link was sent to your email.',
              ),
            );
          } on AuthException catch (error) {
            _showMessage(error.message);
          }
        }
        return;
      }
      final result = await showDialog<_AccountDialogResult>(
        context: context,
        builder: (context) =>
            _AccountAuthDialog(client: client, english: widget.english),
      );
      if (result != _AccountDialogResult.signedIn || !mounted) return;

      final userId = client.auth.currentUser!.id;
      Map<String, dynamic>? preference;
      Map<String, dynamic>? entitlement;
      try {
        preference = await client
            .from('user_preferences')
            .select('language')
            .eq('user_id', userId)
            .maybeSingle();
      } catch (_) {}
      if (preference != null && mounted) {
        widget.onLanguage(preference['language'] == 'en');
      }
      try {
        entitlement = await client
            .from('billing_entitlements')
            .select('status, expires_at')
            .eq('user_id', userId)
            .maybeSingle();
      } catch (_) {}
      final hasPro =
          entitlement?['status'] == 'active' ||
          entitlement?['status'] == 'grace_period';
      _showMessage(
        hasPro
            ? t('Berhasil masuk. Pro aktif.', 'Signed in. Pro is active.')
            : t(
                'Berhasil masuk. Paket Gratis aktif.',
                'Signed in. Free plan is active.',
              ),
      );
      await _loadPlan();
    } catch (error) {
      _showMessage(t('Gagal mengakses akun: $error', 'Account error: $error'));
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/shortir_file_icon.png',
                width: 38,
                height: 38,
              ),
            ),
            const SizedBox(width: 11),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Shortir File',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                Text(
                  t('Atur file dengan mudah', 'Organize files with ease'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _account,
            tooltip: t('Akun', 'Account'),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          TextButton(
            onPressed: () => widget.onLanguage(!widget.english),
            child: Text(widget.english ? 'EN' : 'ID'),
          ),
          IconButton(
            onPressed: widget.onTheme,
            tooltip: t('Ganti tema', 'Toggle theme'),
            icon: Icon(
              widget.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _folder == null
          ? (Platform.isMacOS || Platform.isWindows || Platform.isLinux
                ? DropTarget(onDragDone: _handleDroppedFiles, child: _welcome())
                : _welcome())
          : _workspace(),
      bottomNavigationBar: _bannerAd == null
          ? null
          : SafeArea(
              child: SizedBox(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
            ),
    );
  }

  Widget _pickFolderButton() => FilledButton.icon(
    onPressed: _chooseFolder,
    icon: const Icon(Icons.create_new_folder_outlined),
    label: Text(t('Pilih Folder', 'Choose Folder')),
  );

  Widget _welcome() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: Image.asset(
                    'assets/shortir_file_icon.png',
                    width: 72,
                    height: 72,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  t(
                    'Semua berkas, lebih tertata.',
                    'All files, beautifully organized.',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t(
                    'Pilih folder untuk mulai merapikan foto dan dokumen.',
                    'Choose a folder to organize photos and documents.',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (_planLoaded && !_isPro) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.local_fire_department_outlined,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            t(
                              'Trial gratis: $_sortsLeft/$_freeSortsPerMonth sortir tersisa · maksimal $_freeFileLimitPerSort file per sortir',
                              'Free trial: $_sortsLeft/$_freeSortsPerMonth sorts left · maximum $_freeFileLimitPerSort files per sort',
                            ),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                _pickFolderButton(),
                if (!_isPro) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _upgradeToPro,
                    icon: const Icon(Icons.workspace_premium_outlined),
                    label: Text(t('Upgrade ke Pro', 'Upgrade to Pro')),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _gridTile(File file) {
    final filename = _fileName(file);
    final parts = filename.split('.');
    final ext = parts.length > 1 ? parts.last.toLowerCase() : '';
    final photo = _photos.contains(ext);
    final selected = _selected.contains(file.path);
    return GestureDetector(
      onTap: () => setState(() {
        selected ? _selected.remove(file.path) : _selected.add(file.path);
      }),
      onDoubleTap: () => _previewFile(file),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: photo
                          ? FutureBuilder<Uint8List?>(
                              future: _thumbFuture(file),
                              builder: (context, snapshot) {
                                final bytes = snapshot.data;
                                if (bytes == null || bytes.isEmpty) {
                                  return Center(
                                    child: Icon(
                                      Icons.image_outlined,
                                      size: _gridCell * 0.45,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  );
                                }
                                return Image.memory(
                                  bytes,
                                  fit: BoxFit.cover,
                                  gaplessPlayback: true,
                                  errorBuilder: (context, error, stack) =>
                                      Center(
                                    child: Icon(
                                      Icons.image_outlined,
                                      size: _gridCell * 0.45,
                                    ),
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Icon(
                                _videos.contains(ext)
                                    ? Icons.movie_outlined
                                    : Icons.description_outlined,
                                size: _gridCell * 0.45,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                  child: Text(
                    filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 6,
              right: 6,
              child: Checkbox(
                value: selected,
                onChanged: (value) => setState(() {
                  value == true
                      ? _selected.add(file.path)
                      : _selected.remove(file.path);
                }),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _workspace() {
    final files = _filtered;
    final allSelected =
        files.isNotEmpty &&
        files.every((file) => _selected.contains(file.path));
    return Column(
      children: [
        if (_isPro)
          Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _busy || _operationHistory.isEmpty
                    ? null
                    : _undoLastOperation,
                icon: const Icon(Icons.undo, size: 18),
                label: Text(t('Undo', 'Undo')),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _busy || _operationHistory.isEmpty
                    ? null
                    : _undoAllOperations,
                icon: const Icon(Icons.undo, size: 18),
                label: Text(t('Undo Semua', 'Undo All')),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _busy || _redoHistory.isEmpty
                    ? null
                    : _redoLastOperation,
                icon: const Icon(Icons.redo, size: 18),
                label: Text(t('Redo', 'Redo')),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _busy || _redoHistory.isEmpty
                    ? null
                    : _redoAllOperations,
                icon: const Icon(Icons.redo, size: 18),
                label: Text(t('Redo Semua', 'Redo All')),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_searchNames.isNotEmpty)
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 74),
                              child: SingleChildScrollView(
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 2,
                                  children: [
                                    for (final name in _searchNames)
                                      InputChip(
                                        label: Text(
                                          name,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: _nameHasMatch(name)
                                                ? null
                                                : Theme.of(context)
                                                      .colorScheme
                                                      .onErrorContainer,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        backgroundColor: _nameHasMatch(name)
                                            ? null
                                            : Theme.of(
                                                context,
                                              ).colorScheme.errorContainer,
                                        deleteIconColor: _nameHasMatch(name)
                                            ? null
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onErrorContainer,
                                        visualDensity: VisualDensity.compact,
                                        onDeleted: () =>
                                            _removeSearchName(name),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          Row(
                            children: [
                              const Icon(Icons.search, size: 21),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _search,
                                  focusNode: _searchFocus,
                                  minLines: 1,
                                  maxLines: 2,
                                  textInputAction: TextInputAction.done,
                                  onChanged: _updateSearch,
                                  onSubmitted: _commitSearch,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: InputDecoration.collapsed(
                                    hintText: t(
                                      'Cari atau paste daftar nama file…',
                                      'Search or paste a list of file names…',
                                    ),
                                    hintStyle: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: t('Tambah nama', 'Add name'),
                                onPressed: () =>
                                    _commitSearch(_search.text),
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  size: 22,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_searchNames.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_filtered.length} ${t('file ditemukan', 'files found')} · ${_missingSearchNames.length} ${t('nama file tidak ditemukan', 'file names not found')}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      if (_missingSearchNames.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${t('Nama tidak ditemukan:', 'Names not found:')} ${_missingSearchNames.join(', ')}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                                fontSize: 11,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<String>(
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        ),
                        textStyle: WidgetStatePropertyAll(
                          TextStyle(fontSize: 11),
                        ),
                      ),
                      segments: [
                        ButtonSegment(
                          value: 'photos',
                          label: Text(t('Foto', 'Photos')),
                          icon: const Icon(Icons.image_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: 'documents',
                          label: Text(t('Dokumen', 'Documents')),
                          icon: const Icon(Icons.description_outlined, size: 16),
                        ),
                        ButtonSegment(
                          value: 'all',
                          label: Text(t('Semua', 'All')),
                          icon: const Icon(Icons.grid_view_outlined, size: 16),
                        ),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (value) => setState(() {
                        _kind = value.first;
                        _extensionFilter = 'all';
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: allSelected
                        ? t('Bersihkan pilihan', 'Clear selection')
                        : t('Pilih semua', 'Select all'),
                    onPressed: files.isEmpty ? null : _toggleSelectAll,
                    icon: Icon(
                      allSelected ? Icons.deselect : Icons.select_all,
                      size: 20,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  ],
                ),
              ],
            ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _folder!.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              Text(
                '${files.length} ${t('berkas', 'files')} · ${_selected.length} ${t('dipilih', 'selected')}',
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _chooseFolder,
                child: Text(t('Ganti', 'Change')),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: _resetWorkspace,
                tooltip: t('Reset', 'Reset'),
                icon: const Icon(Icons.restart_alt, size: 20),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              DropdownButton<String>(
                value: _availableExtensions.contains(_extensionFilter)
                    ? _extensionFilter
                    : 'all',
                isDense: true,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(14),
                icon: const Icon(Icons.filter_alt_outlined, size: 16),
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontSize: 12),
                items: [
                  DropdownMenuItem(
                    value: 'all',
                    child: Text(t('Semua format', 'All formats')),
                  ),
                  for (final extension in _availableExtensions)
                    DropdownMenuItem(
                      value: extension,
                      child: Text(extension.toUpperCase()),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _extensionFilter = value);
                },
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _sortMode,
                isDense: true,
                underline: const SizedBox.shrink(),
                borderRadius: BorderRadius.circular(14),
                icon: const Icon(Icons.sort_by_alpha, size: 16),
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(fontSize: 12),
                items: [
                  DropdownMenuItem(
                    value: 'name',
                    child: Text(t('Nama', 'Name')),
                  ),
                  DropdownMenuItem(
                    value: 'type',
                    child: Text(t('Tipe', 'Type')),
                  ),
                  DropdownMenuItem(
                    value: 'size',
                    child: Text(t('Ukuran', 'Size')),
                  ),
                  DropdownMenuItem(
                    value: 'date',
                    child: Text(t('Tanggal', 'Date')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _sortMode = value);
                },
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: t('Tampilan daftar', 'List view'),
                isSelected: _viewMode == _ViewMode.list,
                onPressed: () => setState(() {
                  _viewMode = _ViewMode.list;
                  SharedPreferences.getInstance().then(
                    (prefs) => prefs.setString('file_view_mode', 'list'),
                  );
                }),
                icon: const Icon(Icons.view_list_outlined, size: 20),
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                tooltip: t('Tampilan ikon', 'Grid view'),
                isSelected: _viewMode == _ViewMode.grid,
                onPressed: () => setState(() {
                  _viewMode = _ViewMode.grid;
                  SharedPreferences.getInstance().then(
                    (prefs) => prefs.setString('file_view_mode', 'grid'),
                  );
                }),
                icon: const Icon(Icons.grid_view_outlined, size: 20),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 10),
              if (_isPro)
                PopupMenuButton<String>(
                  tooltip: t('Buka tools', 'Open tools'),
                  onSelected: (value) {
                    switch (value) {
                      case 'rules':
                        _showSortRules();
                      case 'duplicates':
                        _findDuplicates();
                      case 'history':
                        _showOperationHistory();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'rules',
                      child: ListTile(
                        leading: const Icon(Icons.auto_awesome_motion_outlined),
                        title: Text(t('Aturan otomatis', 'Auto rules')),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'duplicates',
                      child: ListTile(
                        leading: const Icon(Icons.copy_all_outlined),
                        title: Text(t('Cari duplikat', 'Find duplicates')),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'history',
                      child: ListTile(
                        leading: const Icon(Icons.history),
                        title: Text(t('Riwayat aktivitas', 'Activity history')),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                  child: _toolsButton(t('Buka tools', 'Open tools')),
                )
              else
                GestureDetector(
                  onTap: () => _requirePro(),
                  child: _toolsButton(t('Buka tools', 'Open tools')),
                ),
            ],
          ),
        ),
        Expanded(
          child: files.isEmpty
              ? (_files.isEmpty
                    ? Center(
                        child: _pickFolderButton(),
                      )
                    : Center(
                        child: Text(
                          t('Tidak ada berkas yang cocok.', 'No matching files.'),
                        ),
                      ))
              : _viewMode == _ViewMode.grid
                  ? GridView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: _gridCell * 1.35,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: files.length,
                      itemBuilder: (context, index) =>
                          _gridTile(files[index]),
                    )
                  : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    final filename = _fileName(file);
                    final parts = filename.split('.');
                    final ext = parts.length > 1
                        ? parts.last.toLowerCase()
                        : '';
                    final photo = _photos.contains(ext);
                    int size = 0;
                    try {
                      size = file.lengthSync();
                    } catch (_) {}
                    return Card(
                      child: CheckboxListTile(
                        value: _selected.contains(file.path),
                        onChanged: (value) => setState(
                          () => value == true
                              ? _selected.add(file.path)
                              : _selected.remove(file.path),
                        ),
                        title: Row(
                          children: [
                            SizedBox(
                              width: 52,
                              height: 52,
                              child: GestureDetector(
                                onTap: () => _previewFile(file),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: photo
                                      ? FutureBuilder<Uint8List?>(
                                          future: _thumbFuture(file),
                                          builder: (context, snapshot) {
                                            final bytes = snapshot.data;
                                            if (bytes == null || bytes.isEmpty) {
                                              return Center(
                                                child: Icon(
                                                  Icons.image_outlined,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              );
                                            }
                                            return Image.memory(
                                              bytes,
                                              fit: BoxFit.cover,
                                              gaplessPlayback: true,
                                              errorBuilder:
                                                  (context, error, stack) =>
                                                      Center(
                                                child: Icon(
                                                  Icons.image_outlined,
                                                ),
                                              ),
                                            );
                                          },
                                        )
                                      : Center(
                                          child: Icon(
                                            _videos.contains(ext)
                                                ? Icons.movie_outlined
                                                : Icons.description_outlined,
                                            size: 26,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    filename,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    (() {
                                      final displaySize =
                                          _fileSizes[file.path] ?? size;
                                      if (ext.isEmpty) {
                                        return displaySize > 0
                                            ? _formatSize(displaySize)
                                            : '';
                                      }
                                      return '${ext.toUpperCase()}${displaySize > 0 ? ' • ${_formatSize(displaySize)}' : ''}';
                                    })(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        controlAffinity: ListTileControlAffinity.trailing,
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
            child: Column(
              children: [
                if (_busy) ...[
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: _totalCount == 0
                              ? null
                              : _processedCount / _totalCount,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text('$_processedCount/$_totalCount'),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () =>
                            setState(() => _cancelRequested = true),
                        child: Text(t('Batal', 'Cancel')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    _message ??
                        t(
                          '${_files.length} berkas ditemukan',
                          '${_files.length} files found',
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<String>(
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: WidgetStatePropertyAll(
                            EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          ),
                          textStyle: WidgetStatePropertyAll(
                            TextStyle(fontSize: 11),
                          ),
                        ),
                        segments: [
                          ButtonSegment(
                            value: 'move',
                            label: Text(t('Pindahkan', 'Move')),
                            icon: const Icon(
                              Icons.drive_file_move_outlined,
                              size: 16,
                            ),
                          ),
                          ButtonSegment(
                            value: 'copy',
                            label: Text(t('Salin', 'Copy')),
                            icon: const Icon(Icons.copy_outlined, size: 16),
                          ),
                        ],
                        selected: {_fileOperation},
                        onSelectionChanged: _busy
                            ? null
                            : (value) =>
                                  setState(() => _fileOperation = value.first),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        textStyle: WidgetStatePropertyAll(
                          TextStyle(fontSize: 12),
                        ),
                      ),
                      onPressed: _busy || _selected.isEmpty
                          ? null
                          : _processSelected,
                      icon: Icon(
                        _fileOperation == 'copy'
                            ? Icons.copy_outlined
                            : Icons.drive_file_move_outline,
                        size: 18,
                      ),
                      label: Text(
                        _busy
                            ? (_fileOperation == 'copy'
                                  ? t('Menyalin…', 'Copying…')
                                  : t('Memindahkan…', 'Moving…'))
                            : (_fileOperation == 'copy'
                                  ? t('Salin Pilihan', 'Copy Selected')
                                  : t('Pindahkan Pilihan', 'Move Selected')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SortRuleDialog extends StatefulWidget {
  const _SortRuleDialog();

  @override
  State<_SortRuleDialog> createState() => _SortRuleDialogState();
}

class _SortRuleDialogState extends State<_SortRuleDialog> {
  final _value = TextEditingController();
  final _destination = TextEditingController();
  String _type = 'extension';

  @override
  void dispose() {
    _value.dispose();
    _destination.dispose();
    super.dispose();
  }

  String get _hint => switch (_type) {
    'extension' => 'jpg',
    'size' => '100',
    'date' => '2026-11',
    _ => 'invoice',
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tambah aturan sortir'),
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Kondisi'),
              items: const [
                DropdownMenuItem(value: 'extension', child: Text('Tipe file')),
                DropdownMenuItem(
                  value: 'size',
                  child: Text('Ukuran minimal (MB)'),
                ),
                DropdownMenuItem(
                  value: 'date',
                  child: Text('Tanggal (YYYY-MM)'),
                ),
                DropdownMenuItem(value: 'name', child: Text('Nama mengandung')),
              ],
              onChanged: (value) =>
                  setState(() => _type = value ?? 'extension'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _value,
              decoration: InputDecoration(labelText: 'Nilai', hintText: _hint),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _destination,
              decoration: const InputDecoration(
                labelText: 'Folder tujuan',
                hintText: 'Foto',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            final value = _value.text.trim();
            final destination = _destination.text.trim();
            if (value.isEmpty || destination.isEmpty) return;
            Navigator.pop(
              context,
              _SortRule(type: _type, value: value, destination: destination),
            );
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

class _AccountAuthDialog extends StatefulWidget {
  const _AccountAuthDialog({
    required this.client,
    required this.english,
    this.initialScreen = _AuthScreen.signIn,
  });

  final SupabaseClient client;
  final bool english;
  final _AuthScreen initialScreen;

  @override
  State<_AccountAuthDialog> createState() => _AccountAuthDialogState();
}

class _AccountAuthDialogState extends State<_AccountAuthDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  late _AuthScreen _screen = widget.initialScreen;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  String? _error;
  String? _notice;

  String t(String id, String en) => widget.english ? en : id;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String get _title => switch (_screen) {
    _AuthScreen.signIn => t('Selamat datang kembali', 'Welcome back'),
    _AuthScreen.signUp => t('Buat akun Shortir File', 'Create your account'),
    _AuthScreen.forgotPassword => t('Lupa kata sandi?', 'Forgot password?'),
    _AuthScreen.updatePassword => t(
      'Buat kata sandi baru',
      'Set a new password',
    ),
  };

  String get _subtitle => switch (_screen) {
    _AuthScreen.signIn => t(
      'Masuk untuk menyinkronkan pengaturan akun.',
      'Sign in to sync your account settings.',
    ),
    _AuthScreen.signUp => t(
      'Buat akun untuk menyimpan pengaturanmu.',
      'Create an account to save your settings.',
    ),
    _AuthScreen.forgotPassword => t(
      'Kami akan mengirim tautan pemulihan ke emailmu.',
      'We will email you a password reset link.',
    ),
    _AuthScreen.updatePassword => t(
      'Pilih kata sandi baru untuk akunmu.',
      'Choose a new password for your account.',
    ),
  };

  String get _submitLabel => switch (_screen) {
    _AuthScreen.signIn => t('Masuk', 'Sign in'),
    _AuthScreen.signUp => t('Buat akun', 'Create account'),
    _AuthScreen.forgotPassword => t('Kirim tautan', 'Send reset link'),
    _AuthScreen.updatePassword => t('Simpan kata sandi', 'Save password'),
  };

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      switch (_screen) {
        case _AuthScreen.signIn:
          await widget.client.auth.signInWithPassword(
            email: _email.text.trim(),
            password: _password.text,
          );
          if (mounted) {
            Navigator.pop(context, _AccountDialogResult.signedIn);
          }
        case _AuthScreen.signUp:
          final response = await widget.client.auth.signUp(
            email: _email.text.trim(),
            password: _password.text,
            emailRedirectTo: _supabaseAuthRedirectUrl,
          );
          if (response.session != null && mounted) {
            Navigator.pop(context, _AccountDialogResult.signedIn);
          } else if (mounted) {
            setState(() {
              _screen = _AuthScreen.signIn;
              _password.clear();
              _confirmPassword.clear();
              _notice = t(
                'Akun dibuat. Periksa email untuk konfirmasi, lalu masuk.',
                'Account created. Check your email to confirm, then sign in.',
              );
            });
          }
        case _AuthScreen.forgotPassword:
          await widget.client.auth.resetPasswordForEmail(
            _email.text.trim(),
            redirectTo: _supabaseAuthRedirectUrl,
          );
          if (mounted) {
            setState(() {
              _screen = _AuthScreen.signIn;
              _notice = t(
                'Jika email terdaftar, tautan pemulihan akan segera dikirim.',
                'If the email is registered, a reset link will be sent shortly.',
              );
            });
          }
        case _AuthScreen.updatePassword:
          await widget.client.auth.updateUser(
            UserAttributes(password: _password.text),
          );
          if (mounted) {
            Navigator.pop(context, _AccountDialogResult.passwordUpdated);
          }
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = t(
            'Terjadi kendala. Periksa koneksi lalu coba lagi.',
            'Something went wrong. Check your connection and try again.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendConfirmation() async {
    if (!_validEmail(_email.text.trim())) {
      setState(() {
        _error = t(
          'Masukkan email yang valid dahulu.',
          'Enter a valid email first.',
        );
        _notice = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.client.auth.resend(
        type: OtpType.signup,
        email: _email.text.trim(),
        emailRedirectTo: _supabaseAuthRedirectUrl,
      );
      if (mounted) {
        setState(() {
          _notice = t(
            'Jika akun belum dikonfirmasi, email baru akan dikirim.',
            'If the account is unconfirmed, a new email will be sent.',
          );
        });
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = t(
            'Email belum dapat dikirim. Coba lagi nanti.',
            'Email could not be sent. Please try again later.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _validEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);

  void _switchScreen(_AuthScreen screen) {
    setState(() {
      _screen = screen;
      _error = null;
      _notice = null;
      _password.clear();
      _confirmPassword.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final needsEmail = _screen != _AuthScreen.updatePassword;
    final needsPassword =
        _screen == _AuthScreen.signIn ||
        _screen == _AuthScreen.signUp ||
        _screen == _AuthScreen.updatePassword;
    final needsConfirmation =
        _screen == _AuthScreen.signUp || _screen == _AuthScreen.updatePassword;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (_screen != _AuthScreen.updatePassword)
                        IconButton(
                          tooltip: t('Tutup', 'Close'),
                          onPressed: _busy
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(_subtitle),
                  const SizedBox(height: 22),
                  if (needsEmail) ...[
                    TextFormField(
                      controller: _email,
                      autofocus: true,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: t('Alamat email', 'Email address'),
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) => _validEmail(value?.trim() ?? '')
                          ? null
                          : t(
                              'Masukkan email yang valid.',
                              'Enter a valid email.',
                            ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (needsPassword) ...[
                    TextFormField(
                      controller: _password,
                      obscureText: _obscurePassword,
                      autofillHints: _screen == _AuthScreen.signIn
                          ? const [AutofillHints.password]
                          : const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: t('Kata sandi', 'Password'),
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? t('Tampilkan kata sandi', 'Show password')
                              : t('Sembunyikan kata sandi', 'Hide password'),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        final password = value ?? '';
                        if (_screen == _AuthScreen.signIn) {
                          return password.isEmpty
                              ? t(
                                  'Masukkan kata sandi.',
                                  'Enter your password.',
                                )
                              : null;
                        }
                        return password.length >= 8
                            ? null
                            : t(
                                'Gunakan minimal 8 karakter.',
                                'Use at least 8 characters.',
                              );
                      },
                      onFieldSubmitted: (_) =>
                          _screen == _AuthScreen.signIn ? _submit() : null,
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (needsConfirmation) ...[
                    TextFormField(
                      controller: _confirmPassword,
                      obscureText: _obscureConfirmation,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: t('Ulangi kata sandi', 'Confirm password'),
                        prefixIcon: const Icon(Icons.lock_reset_outlined),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: t('Tampilkan kata sandi', 'Show password'),
                          onPressed: () => setState(
                            () => _obscureConfirmation = !_obscureConfirmation,
                          ),
                          icon: Icon(
                            _obscureConfirmation
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) => value == _password.text
                          ? null
                          : t(
                              'Kata sandi tidak sama.',
                              'Passwords do not match.',
                            ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_error != null) _feedback(_error!, isError: true),
                  if (_notice != null) _feedback(_notice!),
                  if (_error != null || _notice != null)
                    const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_submitLabel),
                  ),
                  if (_screen == _AuthScreen.signIn) ...[
                    Align(
                      alignment: Alignment.center,
                      child: TextButton(
                        onPressed: _busy
                            ? null
                            : () => _switchScreen(_AuthScreen.forgotPassword),
                        child: Text(t('Lupa kata sandi?', 'Forgot password?')),
                      ),
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(t('Belum punya akun?', 'New to Shortir File?')),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _switchScreen(_AuthScreen.signUp),
                          child: Text(t('Daftar', 'Create account')),
                        ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _resendConfirmation,
                      icon: const Icon(Icons.mark_email_unread_outlined),
                      label: Text(
                        t(
                          'Kirim ulang email konfirmasi',
                          'Resend confirmation email',
                        ),
                      ),
                    ),
                  ] else if (_screen != _AuthScreen.updatePassword) ...[
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _switchScreen(_AuthScreen.signIn),
                      child: Text(t('Kembali ke masuk', 'Back to sign in')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _feedback(String message, {bool isError = false}) {
    final colors = Theme.of(context).colorScheme;
    final color = isError ? colors.error : colors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: TextStyle(color: color)),
    );
  }
}
