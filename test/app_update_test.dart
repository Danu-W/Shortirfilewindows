import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shortir_file/app_update.dart';

void main() {
  group('parseLatestRelease', () {
    test('parses latest release and picks macOS zip asset', () {
      final body = jsonEncode({
        'tag_name': 'v1.1.0',
        'assets': [
          {
            'name': 'shortir-file-windows-x64.zip',
            'browser_download_url': 'https://example.com/win.zip',
          },
          {
            'name': 'shortir-file-macos.zip',
            'browser_download_url': 'https://example.com/mac.zip',
          },
          {
            'name': 'shortir-file-macos.zip.sha256',
            'browser_download_url': 'https://example.com/mac.zip.sha256',
          },
        ],
      });
      final info = AppUpdateChecker.parseLatestRelease(body);
      expect(info, isNotNull);
      expect(info!.version, '1.1.0');
      expect(info.tagName, 'v1.1.0');
      expect(info.downloadUrl, 'https://example.com/mac.zip');
      expect(info.sha256Url, 'https://example.com/mac.zip.sha256');
    });

    test('returns null when no macOS zip asset', () {
      final body = jsonEncode({
        'tag_name': 'v1.1.0',
        'assets': [
          {
            'name': 'shortir-file-windows-x64.zip',
            'browser_download_url': 'https://example.com/win.zip',
          },
        ],
      });
      expect(AppUpdateChecker.parseLatestRelease(body), isNull);
    });

    test('returns null for invalid json', () {
      expect(AppUpdateChecker.parseLatestRelease('not json'), isNull);
    });

    test('returns null when assets is missing', () {
      expect(AppUpdateChecker.parseLatestRelease('{"tag_name":"v1.0.0"}'), isNull);
    });
  });

  group('compareVersions', () {
    test('compares numerically', () {
      expect(AppUpdateChecker.compareVersions('1.0.0', '1.0.1'), lessThan(0));
      expect(AppUpdateChecker.compareVersions('1.2.0', '1.10.0'), lessThan(0));
      expect(AppUpdateChecker.compareVersions('2.0.0', '1.99.99'), greaterThan(0));
      expect(AppUpdateChecker.compareVersions('1.0.0', '1.0.0'), 0);
    });

    test('ignores v prefix and build suffix', () {
      expect(AppUpdateChecker.compareVersions('v1.0.0', '1.0.0+3'), 0);
      expect(AppUpdateChecker.compareVersions('1.0.0', '1.0.0+1'), 0);
    });
  });
}
