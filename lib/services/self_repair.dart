/// Self Repair ("Khud Theek Karo"): automated repair sequence.
/// Har step progress UI me dikhta hai (spinner → ✓ / ✗).
/// Steps: DB sehat → recalculation → rollover → cache → reminders →
/// error patterns → storage. Aakhir me summary + support report.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'auth_service.dart';
import 'backup_service.dart';
import 'call_reminders.dart';
import 'customer_store.dart';
import 'error_log.dart';

enum RepairStatus { pending, running, ok, fixed, warn, fail }

class RepairStep {
  final String id;
  final String title;
  RepairStatus status;
  String detail;

  /// Optional one-tap action (e.g. restore offer).
  String? actionLabel;
  String? actionData;

  RepairStep(this.id, this.title)
      : status = RepairStatus.pending,
        detail = '';
}

class SelfRepair {
  static const _storageChannel =
      MethodChannel('qistbook/storage');

  /// Steps ko live stream karta hai; complete hone par full list return.
  static Stream<RepairStep> run(String uid, CustomerStore store) async* {
    final steps = [
      RepairStep('db', 'Database sehat check'),
      RepairStep('recalc', 'Data recalculation'),
      RepairStep('rollover', 'Monthly rollover check'),
      RepairStep('cache', 'Cache / temp saaf'),
      RepairStep('reminders', 'Reminders verify'),
      RepairStep('errors', 'Error history scan'),
      RepairStep('storage', 'Storage health'),
    ];

    for (final s in steps) {
      s.status = RepairStatus.running;
      yield s;
      try {
        switch (s.id) {
          case 'db':
            await _stepDb(uid, s);
            break;
          case 'recalc':
            await _stepRecalc(store, s);
            break;
          case 'rollover':
            await _stepRollover(store, s);
            break;
          case 'cache':
            await _stepCache(s);
            break;
          case 'reminders':
            await _stepReminders(s);
            break;
          case 'errors':
            await _stepErrors(s);
            break;
          case 'storage':
            await _stepStorage(s);
            break;
        }
      } catch (e) {
        s.status = RepairStatus.fail;
        s.detail = 'Check nahi ho saka: $e';
        ErrorLog.log('SelfRepair ${s.id}', e);
      }
      yield s;
    }
  }

  // ------------------------------------------------------------- steps

  /// 1. integrity_check + tables. Kharab ho to latest backup dhoond kar
  ///    auto-restore ki offer (one tap), warna wazeh hidayat.
  static Future<void> _stepDb(String uid, RepairStep s) async {
    final res = await BackupService.checkIntegrity(uid);
    if (res != 'ok') {
      final tablesOk = await _tablesExist(uid);
      s.status = RepairStatus.fail;
      s.detail = tablesOk
          ? 'Database me kharabi mili. '
          : 'Database kharab ya adhoori hai. ';
      final backup = await _latestBackup();
      if (backup != null) {
        s.detail +=
            'Mehfooz backup mil gaya (${backup.split('/').last}).';
        s.actionLabel = 'Backup se restore karo';
        s.actionData = backup;
      } else {
        s.detail +=
            'Koi backup nahi mila — Profile → Backup se pehle backup banao, phir support se rabta karo.';
      }
      return;
    }
    if (!await _tablesExist(uid)) {
      s.status = RepairStatus.fail;
      s.detail =
          'Database khaali/adhoori hai. Backup se restore karo ya support se rabta karo.';
      final backup = await _latestBackup();
      if (backup != null) {
        s.actionLabel = 'Backup se restore karo';
        s.actionData = backup;
      }
      return;
    }
    s.status = RepairStatus.ok;
    s.detail = 'Database bilkul theek hai.';
  }

  static Future<bool> _tablesExist(String uid) async {
    Database? db;
    try {
      final dir = await getDatabasesPath();
      final f =
          File(p.join(dir, AuthService.userDbName(uid)));
      if (!await f.exists()) return false;
      db = await openDatabase(f.path, readOnly: true);
      for (final t in ['customers', 'payments', 'vouchers']) {
        final r = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='$t'");
        if (r.isEmpty) return false;
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      await db?.close();
    }
  }

  /// Downloads me sab se naya valid QistBook backup dhoondo.
  static Future<String?> _latestBackup() async {
    try {
      Directory? dl;
      try {
        dl = await getDownloadsDirectory();
      } catch (_) {}
      if (dl == null || !await dl.exists()) return null;
      final cands = <File>[];
      await for (final e in dl.list()) {
        final name = p.basename(e.path);
        if (e is File &&
            name.startsWith('QistBook-Backup-') &&
            name.endsWith('.db')) {
          cands.add(e);
        }
      }
      cands.sort((a, b) => b
          .lastModifiedSync()
          .compareTo(a.lastModifiedSync()));
      for (final f in cands) {
        if (await BackupService.isValidBackup(f)) {
          return f.path;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 2. DB se dobara load + totals recalculate (refreshData).
  static Future<void> _stepRecalc(
      CustomerStore store, RepairStep s) async {
    await store.refreshData();
    s.status = RepairStatus.fixed;
    s.detail =
        'Saare totals/dues dobara calculate ho gaye (${store.active.length} customers).';
  }

  /// 3. Agar is mahine ka rollover pending hai to chala do.
  static Future<void> _stepRollover(
      CustomerStore store, RepairStep s) async {
    final n = await store.maybeRollover();
    if (n > 0) {
      s.status = RepairStatus.fixed;
      s.detail = '$n customers ki due update kar di.';
    } else {
      s.status = RepairStatus.ok;
      s.detail = 'Rollover already done hai — kuch nahi karna tha.';
    }
  }

  /// 4. Stale temp files + purani export files saaf.
  static Future<void> _stepCache(RepairStep s) async {
    final n = await BackupService.clearCache();
    var csv = 0;
    try {
      final tmp = await getTemporaryDirectory();
      await for (final e in tmp.list()) {
        if (e is File && e.path.endsWith('.csv')) {
          final age = DateTime.now()
              .difference(await e.lastModified());
          if (age.inHours > 24) {
            await e.delete();
            csv++;
          }
        }
      }
    } catch (_) {}
    if (n + csv > 0) {
      s.status = RepairStatus.fixed;
      s.detail = '${n + csv} aarzi files saaf kar di.';
    } else {
      s.status = RepairStatus.ok;
      s.detail = 'Cache pehle se saaf tha.';
    }
  }

  /// 5. Reminders verify: guzre hue saaf, ghaib dobara schedule.
  static Future<void> _stepReminders(RepairStep s) async {
    final r = await CallReminderService.verifyReminders();
    final re = r['rescheduled'] ?? 0;
    final cl = r['cleaned'] ?? 0;
    if (re > 0 || cl > 0) {
      s.status = RepairStatus.fixed;
      final parts = <String>[];
      if (re > 0) parts.add('$re reminder dobara lagaye');
      if (cl > 0) parts.add('$cl purane hata diye');
      s.detail = '${parts.join(', ')}.';
    } else {
      s.status = RepairStatus.ok;
      s.detail = 'Saare reminders theek hain.';
    }
  }

  /// 6. Error history me known patterns → auto-fix ya mashwara.
  static Future<void> _stepErrors(RepairStep s) async {
    final entries = ErrorLog.entries;
    if (entries.isEmpty) {
      s.status = RepairStatus.ok;
      s.detail = 'Koi error record nahi.';
      return;
    }
    final texts =
        entries.map((e) => e.message.toLowerCase()).join(' | ');
    final advices = <String>[];

    if (texts.contains('database is locked')) {
      advices.add(
          '• "Database locked" mila — app band karke dobara kholo, masla hal ho jayega.');
    }
    final importFails =
        RegExp('import|ocr').allMatches(texts).length;
    if (importFails >= 2) {
      advices.add(
          '• Import me baar baar masla — saaf roshni me seedhi photo lo ya PDF use karo; na ho to manual entry try karo.');
    }
    if (texts.contains('whatsapp')) {
      advices.add(
          '• WhatsApp khulne me masla — Support screen me number check karo.');
    }
    if (texts.contains('backup') || texts.contains('restore')) {
      advices.add(
          '• Backup/restore me masla — Downloads me nayi backup banao aur purani delete karo.');
    }

    if (advices.isEmpty) {
      s.status = RepairStatus.ok;
      s.detail =
          '${entries.length} errors mile lekin koi known pattern nahi — sab chhote masle thay.';
    } else {
      s.status = RepairStatus.warn;
      s.detail =
          '${entries.length} errors me ye patterns mile:\n${advices.join('\n')}';
    }
  }

  /// 7. Free space check (Android MethodChannel). Kam ho to warning.
  static Future<void> _stepStorage(RepairStep s) async {
    int? free;
    try {
      free = await _storageChannel
          .invokeMethod<int>('getFreeBytes');
    } catch (_) {
      free = null;
    }
    if (free == null) {
      s.status = RepairStatus.warn;
      s.detail = 'Storage check nahi ho saka.';
      return;
    }
    final mb = free ~/ (1024 * 1024);
    if (mb < 500) {
      s.status = RepairStatus.warn;
      s.detail =
          'Phone me sirf $mb MB jagah bachi hai! Purani backup files / photos delete karo, warna app slow hogi.';
    } else {
      s.status = RepairStatus.ok;
      s.detail = '$mb MB jagah khaali hai — kafi hai.';
    }
  }

  // ------------------------------------------------------------- summary

  /// Support report ke liye mukhtasar summary text.
  static String summaryText(List<RepairStep> steps) {
    final sb = StringBuffer(
        'Assalam-o-Alaikum, QistBook "Khud Theek Karo" ki report:\n');
    for (final s in steps) {
      final icon = switch (s.status) {
        RepairStatus.ok => '✓',
        RepairStatus.fixed => '🔧',
        RepairStatus.warn => '⚠',
        RepairStatus.fail => '✗',
        _ => '…',
      };
      sb.writeln('$icon ${s.title}: ${s.detail}');
    }
    return sb.toString();
  }
}
