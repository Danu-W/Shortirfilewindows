import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.tagName,
    required this.downloadUrl,
    this.sha256Url,
    this.apkUrl,
  });

  final String version;
  final String tagName;
  final String downloadUrl;
  final String? sha256Url;
  final String? apkUrl;
}

class AppUpdateChecker {
  static const String repo = 'Danu-W/Shortirfilewindows';
  static const String zipPrefix = 'shortir-file-macos';
  static const String apkPrefix = 'shortir-file-android';

  static int compareVersions(String a, String b) {
    final na = _versionNumbers(a);
    final nb = _versionNumbers(b);
    final len = na.length > nb.length ? na.length : nb.length;
    for (var i = 0; i < len; i++) {
      final x = i < na.length ? na[i] : 0;
      final y = i < nb.length ? nb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }

  static List<int> _versionNumbers(String version) {
    final base = version
        .replaceFirst(RegExp(r'^v'), '')
        .split('+')
        .first;
    return base
        .split(RegExp(r'[.-]'))
        .map((s) => int.tryParse(s) ?? 0)
        .toList();
  }

  static Future<AppUpdateInfo?> checkLatest() async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      request.headers.set(HttpHeaders.userAgentHeader, 'ShortirFile/1.0');
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      return parseLatestRelease(body);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static AppUpdateInfo? parseLatestRelease(String body) {
    dynamic json;
    try {
      json = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (json is! Map<String, dynamic>) return null;
    final tag = (json['tag_name'] as String?) ?? '';
    final assets = json['assets'];
    if (assets is! List) return null;
    String? zipUrl;
    String? sha256Url;
    String? apkUrl;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = (asset['name'] as String?) ?? '';
      final url = (asset['browser_download_url'] as String?) ?? '';
      if (url.isEmpty) continue;
      if (name.startsWith(zipPrefix) && name.endsWith('.zip')) {
        zipUrl ??= url;
      } else if (name.startsWith(apkPrefix) && name.endsWith('.apk')) {
        apkUrl ??= url;
      } else if (name.endsWith('.sha256')) {
        sha256Url = url;
      }
    }
    if (zipUrl == null && apkUrl == null) return null;
    return AppUpdateInfo(
      version: tag.replaceFirst(RegExp(r'^v'), ''),
      tagName: tag,
      downloadUrl: zipUrl ?? apkUrl!,
      sha256Url: sha256Url,
      apkUrl: apkUrl,
    );
  }

  static Future<void> downloadToFile(
    String url,
    String targetPath, {
    void Function(int received, int total)? onProgress,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'ShortirFile/1.0');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('Download failed: ${response.statusCode}');
      }
      final total = response.contentLength;
      final file = File(targetPath);
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
      await sink.close();
    } finally {
      client.close();
    }
  }

  static Future<String> sha256OfFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return sha256.convert(bytes).toString();
  }

  static Future<bool> parentWritable(String path) async {
    final parent = Directory(path).parent;
    try {
      await parent.create(recursive: true);
      final probe = File('${parent.path}/.shortir_write_probe');
      await probe.writeAsString('x');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> installUpdate({
    required int currentPid,
    required String appPath,
    required String zipPath,
    required String tempDirPath,
  }) async {
    try {
      final unpackDir = Directory('$tempDirPath/unpacked');
      await unpackDir.create(recursive: true);
      final unzip = await Process.run(
        '/usr/bin/ditto',
        ['-x', '-k', zipPath, unpackDir.path],
      );
      if (unzip.exitCode != 0) {
        return 'Gagal membongkar arsip update.';
      }
      final newApp = Directory('${unpackDir.path}/shortir_file.app');
      if (!await newApp.exists()) {
        return 'Arsip update tidak berisi shortir_file.app.';
      }
      final script = File('$tempDirPath/apply_update.sh');
      await script.writeAsString('''
#!/bin/zsh
old_pid=\$1
new_app="\$2"
old_app="\$3"
tmp_dir="\$4"
while kill -0 "\$old_pid" 2>/dev/null; do
  sleep 0.5
done
rm -rf "\$old_app"
ditto "\$new_app" "\$old_app"
open "\$old_app"
rm -rf "\$tmp_dir"
''');
      final start = await Process.start(
        '/bin/zsh',
        [script.path, '$currentPid', newApp.path, appPath, tempDirPath],
        mode: ProcessStartMode.detached,
      );
      if (start.pid <= 0) return 'Gagal menjalankan pemasang update.';
      return null;
    } catch (e) {
      return 'Gagal memasang update: $e';
    }
  }
}
