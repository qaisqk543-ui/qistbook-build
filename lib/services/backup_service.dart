/// Backup & Restore: user ki JSON data file ka backup (Downloads folder + share)
/// aur restore (file picker se .json chuno → validate → replace).
/// Business data = livelihood, is liye sab kuch real aur mehfooz.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'error_log.dart';

class BackupService {
  static String _lastKey(String uid) => 'last_backup_at_$uid';

  static Future<DateTime?> lastBackupAt(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_lastKey(uid));
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<File> _userDataFile(String uid) async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'qistbook_$uid.json'));
  }

  /// "Backup banao": JSON copy karke Downloads me save + share option.
  /// Returns backup file path, ya null agar fail.
  static Future<String?> makeBackup(String uid) async {
    try {
      final src = await _userDataFile(uid);
      if (!await src.exists()) {
        ErrorLog.log('Backup', 'Data file nahi mili');
        return null;
      }
      Directory? dl;
      try {
        dl = await getDownloadsDirectory();
      } catch (_) {}
      dl ??= await getApplicationDocumentsDirectory();
      final stamp = DateTime.now();
      final name =
          'QistBook-Backup-${stamp.year}${stamp.month.toString().padLeft(2, '0')}${stamp.day.toString().padLeft(2, '0')}-${stamp.hour.toString().padLeft(2, '0')}${stamp.minute.toString().padLeft(2, '0')}.json';
      final dest = File(p.join(dl.path, name));
      await src.copy(dest.path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _lastKey(uid), DateTime.now().millisecondsSinceEpoch);
      return dest.path;
    } catch (e) {
      ErrorLog.log('Backup', e);
      return null;
    }
  }

  /// Backup file share karo (WhatsApp / email / Drive…).
  static Future<void> shareBackup(String path) async {
    try {
      await Share.shareXFiles([XFile(path)],
          text: 'QistBook backup — is file ko mehfooz rakhen.');
    } catch (e) {
      ErrorLog.log('Backup share', e);
      rethrow;
    }
  }

  /// Restore ke liye .db file chuno. Sirf valid QistBook DB accept hoti hai.
  static Future<File?> pickBackupFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Backup file (.json) chuno',
      );
      if (res == null || res.files.single.path == null) return null;
      return File(res.files.single.path!);
    } catch (e) {
      ErrorLog.log('Restore pick', e);
      return null;
    }
  }

  /// Kya ye file asli QistBook backup hai? (JSON structure check)
  static Future<bool> isValidBackup(File f) async {
    try {
      final content = await f.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      return data.containsKey('customers') &&
          data.containsKey('payments') &&
          data.containsKey('vouchers');
    } catch (e) {
      ErrorLog.log('Backup validate', e);
      return false;
    }
  }

  /// Current user data file ko backup file se replace karo.
  static Future<bool> restoreFrom(String uid, File backup) async {
    try {
      final dest = await _userDataFile(uid);
      if (await dest.exists()) {
        final bak = File('${dest.path}.pre-restore');
        if (await bak.exists()) await bak.delete();
        await dest.copy(bak.path); // safety: purani file ki copy
      }
      await backup.copy(dest.path);
      return true;
    } catch (e) {
      ErrorLog.log('Restore', e);
      return false;
    }
  }

  /// Data file check: JSON valid hai? 'ok' ya error text.
  static Future<String> checkIntegrity(String uid) async {
    try {
      final f = await _userDataFile(uid);
      if (!await f.exists()) return 'Data file nahi mili';
      final content = await f.readAsString();
      jsonDecode(content);
      return 'ok';
    } catch (e) {
      ErrorLog.log('Data check', e);
      return 'Error: $e';
    }
  }

  /// Temp/cache files saaf karo.
  static Future<int> clearCache() async {
    var n = 0;
    try {
      final tmp = await getTemporaryDirectory();
      if (await tmp.exists()) {
        await for (final e in tmp.list()) {
          try {
            await e.delete(recursive: true);
            n++;
          } catch (_) {}
        }
      }
    } catch (e) {
      ErrorLog.log('Cache clear', e);
    }
    return n;
  }

  /// App reset: user data file delete. Caller logout karke login screen par le jaye.
  static Future<void> wipeUserData(String uid) async {
    try {
      final f = await _userDataFile(uid);
      if (await f.exists()) await f.delete();
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().where((k) => k.endsWith('_$uid'))) {
        await prefs.remove(k);
      }
    } catch (e) {
      ErrorLog.log('App reset', e);
      rethrow;
    }
  }
}
