import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const _supabaseAuthRedirectUrl = String.fromEnvironment(
  'SUPABASE_AUTH_REDIRECT_URL',
  defaultValue: 'shortirfile://login-callback/',
);
const _photos = <String>{
  '3fr',
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

bool get _hasSupabaseConfig =>
    _supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_hasSupabaseConfig) {
    try {
      await Supabase.initialize(url: _supabaseUrl, publishableKey: _supabaseKey);
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

enum _AuthScreen { signIn, signUp, forgotPassword, updatePassword }

enum _AccountDialogResult { signedIn, passwordUpdated }

enum _SignedInAction { close, changePassword, signOut }

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
              widget.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
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
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
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

class _ShortirHomeState extends State<ShortirHome> {
  final _search = TextEditingController();
  final _destination = TextEditingController();
  Directory? _folder;
  List<File> _files = [];
  final Set<String> _selected = {};
  String _kind = 'photos';
  bool _busy = false;
  String? _message;

  String t(String id, String en) => widget.english ? en : id;

  @override
  void initState() {
    super.initState();
    _restoreAccountPreferences();
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
    return _files.where((file) {
      final segments = file.path.split(RegExp(r'[\/\\]'));
      final filename = segments.isNotEmpty ? segments.last : file.path;
      final parts = filename.split('.');
      final extension = parts.length > 1 ? parts.last.toLowerCase() : '';
      final matchesKind = switch (_kind) {
        'photos' => _photos.contains(extension),
        'documents' => _documents.contains(extension),
        _ => _photos.contains(extension) || _documents.contains(extension),
      };
      if (!matchesKind) return false;
      if (query.isEmpty) return true;
      return filename.toLowerCase().contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _search.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _chooseFolder() async {
    try {
      final path = await FilePicker.getDirectoryPath(
        dialogTitle: t('Pilih folder sumber', 'Choose a source folder'),
      );
      if (path == null) return;
      final folder = Directory(path);
      if (!await folder.exists()) {
        _showMessage(
          t('Folder tidak ditemukan.', 'Folder not found.'),
        );
        return;
      }
      final files = <File>[];
      await for (final entry in folder.list(followLinks: false)) {
        if (entry is File) {
          files.add(entry);
        }
      }
      files.sort((a, b) {
        final aName = a.uri.pathSegments.last.toLowerCase();
        final bName = b.uri.pathSegments.last.toLowerCase();
        return aName.compareTo(bName);
      });
      if (!mounted) return;
      setState(() {
        _folder = folder;
        _files = files;
        _selected.clear();
        _destination.clear();
        _search.clear();
        _message = t(
          '${files.length} berkas siap disortir.',
          '${files.length} files ready to sort.',
        );
      });
    } catch (error) {
      _showMessage(
        t(
          'Tidak dapat membuka folder: $error',
          'Could not open folder: $error',
        ),
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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

  Future<String> _getUniqueDestinationPath(String targetDir, String filename) async {
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == filename.length - 1) {
      var candidate = '$targetDir${Platform.pathSeparator}$filename';
      var counter = 1;
      while (await File(candidate).exists() || await Directory(candidate).exists()) {
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
    while (await File(candidate).exists() || await Directory(candidate).exists()) {
      candidate = '$targetDir${Platform.pathSeparator}$base ($counter)$ext';
      counter++;
      if (counter > 1000) break;
    }
    return candidate;
  }

  Future<void> _moveSelected() async {
    final folder = _folder;
    final rawName = _destination.text.trim();
    if (folder == null || _selected.isEmpty) return;
    final name = _sanitizeFolderName(rawName);
    if (name.isEmpty) {
      _showMessage(
        t('Masukkan nama folder yang valid.', 'Enter a valid folder name.'),
      );
      return;
    }
    final targetDir = '${folder.path}${Platform.pathSeparator}$name';
    final targetDirObj = Directory(targetDir);
    if (await targetDirObj.exists()) {
      _showMessage(
        t('Folder tujuan sudah ada.', 'Destination folder already exists.'),
      );
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Pindahkan berkas?', 'Move files?')),
        content: Text(
          t(
            'Berkas terpilih akan dipindahkan ke folder "$name".',
            'Selected files will be moved to "$name".',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('Batal', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('Pindahkan', 'Move')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await targetDirObj.create(recursive: false);
      final moved = <String>{};
      for (final file in _files.where(
        (item) => _selected.contains(item.path),
      )) {
        try {
          final filename = file.uri.pathSegments.last;
          final destPath = await _getUniqueDestinationPath(targetDir, filename);
          await file.rename(destPath);
          moved.add(file.path);
        } catch (_) {
          // Skip files that fail to move and continue with others.
        }
      }
      if (!mounted) return;
      setState(() {
        _files.removeWhere((file) => moved.contains(file.path));
        _selected.clear();
        _busy = false;
        _message = moved.isEmpty
            ? t('Tidak ada berkas yang berhasil dipindahkan.', 'No files were moved.')
            : t(
                '${moved.length} berkas berhasil dipindahkan.',
                '${moved.length} files moved successfully.',
              );
      });
      if (moved.isNotEmpty) {
        _destination.clear();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showMessage(t('Pemindahan gagal: $error', 'Move failed: $error'));
    }
  }

  void _toggleSelectAll() {
    final files = _filtered;
    if (files.isEmpty) return;
    final allSelected =
        files.every((file) => _selected.contains(file.path));
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
      final user = client.auth.currentUser;
      if (user == null) {
        _showMessage(
          t('Login dulu ya buat upgrade ke Pro.', 'Please sign in to upgrade to Pro.'),
        );
        return;
      }
      _showMessage(t('Membuat invoice...', 'Creating invoice...'));
      final res = await client.functions.invoke('create-xendit-invoice', body: {
        'amount': 99000,
        'description': 'Shortir File Pro',
      });
      String? url;
      if (res.data is Map) {
        url = (res.data as Map)['invoice_url'] as String?;
      } else if (res.data is String) {
        final m = RegExp(r'"invoice_url"\s*:\s*"([^"]+)"').firstMatch(res.data as String);
        if (m != null) url = m.group(1);
      }
      if (url == null || url.isEmpty) {
        _showMessage(t('Gagal membuat invoice.', 'Failed to create invoice.'));
        return;
      }
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        _showMessage(
          t(
            'Invoice dibuka di browser. Selesaikan pembayarannya ya.',
            'Invoice opened in browser. Complete your payment.',
          ),
        );
      } else {
        _showMessage(t('Gagal membuka invoice.', 'Failed to open invoice.'));
      }
    } catch (error) {
      _showMessage(t('Gagal upgrade: $error', 'Failed to upgrade: $error'));
    }
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
        try {
          final entitlement = await client
              .from('billing_entitlements')
              .select('status')
              .eq('user_id', signedInUser.id)
              .maybeSingle();
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
                    subtitle: Text(plan),
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
                onPressed: () => Navigator.pop(context, _SignedInAction.signOut),
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
      final hasPro = entitlement?['status'] == 'active' ||
          entitlement?['status'] == 'grace_period';
      _showMessage(
        hasPro
            ? t('Berhasil masuk. Pro aktif.', 'Signed in. Pro is active.')
            : t(
                'Berhasil masuk. Paket Gratis aktif.',
                'Signed in. Free plan is active.',
              ),
      );
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
              widget.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _folder == null ? _welcome() : _workspace(),
    );
  }

  Widget _welcome() => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(28),
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
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
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
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      onPressed: _chooseFolder,
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: Text(t('Pilih Folder', 'Choose Folder')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _workspace() {
    final files = _filtered;
    final allSelected =
        files.isNotEmpty && files.every((file) => _selected.contains(file.path));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: t('Cari berkas…', 'Search files…'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 230,
                child: TextField(
                  controller: _destination,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.create_new_folder_outlined),
                    hintText: t('Nama folder tujuan', 'New folder name'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'photos',
                    label: Text(t('Foto', 'Photos')),
                    icon: const Icon(Icons.image_outlined),
                  ),
                  ButtonSegment(
                    value: 'documents',
                    label: Text(t('Dokumen', 'Documents')),
                    icon: const Icon(Icons.description_outlined),
                  ),
                  ButtonSegment(value: 'all', label: Text(t('Semua', 'All'))),
                ],
                selected: {_kind},
                onSelectionChanged: (value) =>
                    setState(() => _kind = value.first),
              ),
              TextButton.icon(
                onPressed: files.isEmpty ? null : _toggleSelectAll,
                icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
                label: Text(
                  allSelected
                      ? t('Bersihkan pilihan', 'Clear selection')
                      : t('Pilih semua', 'Select all'),
                ),
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
            ],
          ),
        ),
        Expanded(
          child: files.isEmpty
              ? Center(
                  child: Text(
                    t('Tidak ada berkas yang cocok.', 'No matching files.'),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final file = files[index];
                    final segments = file.path.split(RegExp(r'[\/\\]'));
                    final filename =
                        segments.isNotEmpty ? segments.last : file.path;
                    final parts = filename.split('.');
                    final ext = parts.length > 1 ? parts.last.toLowerCase() : '';
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
                        secondary: Icon(
                          photo
                              ? Icons.image_outlined
                              : Icons.description_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(
                          filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          ext.isEmpty
                              ? _formatSize(size)
                              : '${ext.toUpperCase()} • ${_formatSize(size)}',
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
            child: Row(
              children: [
                Expanded(
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
                FilledButton.icon(
                  onPressed: _busy || _selected.isEmpty ? null : _moveSelected,
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: Text(
                    _busy
                        ? t('Memindahkan…', 'Moving…')
                        : t('Pindahkan Pilihan', 'Move Selected'),
                  ),
                ),
              ],
            ),
          ),
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
        _AuthScreen.forgotPassword =>
          t('Lupa kata sandi?', 'Forgot password?'),
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
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (_screen != _AuthScreen.updatePassword)
                        IconButton(
                          tooltip: t('Tutup', 'Close'),
                          onPressed: _busy ? null : () => Navigator.pop(context),
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
