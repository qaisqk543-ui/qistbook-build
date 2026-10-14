/// AI Scan (internet) — Outstanding Report ka page Gemini vision ko bhejo,
/// AI table parh kar SAAF JSON rows wapas de. Ye rows phir waheN review/
/// confirm pipeline me jati hain jo OCR wali rows use karti hain.
///
/// API KEY HARDCODE NAHI: user Profile → "AI Scan API Key (Gemini)" me apni
/// free Gemini key dalta hai (SharedPreferences, sirf is phone par).
/// Key sirf is feature ke HTTPS calls me use hoti hai.
///
/// v1.0.39 (bahar ke AI review ke baad): prompt/schema sakht kiya —
/// har row ke sath `raw_line` (audit), na-parh-sake hisso ki `unreadable`
/// list, printed total alag field me (rows se mix nahi), digit ka andaza
/// lagana mana. Poora page khaali aye to do overlapping halves me dobara
/// koshish hoti hai (lambi table par chhote digits ka hal).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import 'error_log.dart';
import 'parsers.dart';

class AiScanService {
  static const _prefsKey = 'qistbook_ai_scan_key';

  /// Flash vision model. Agar Google 404 de to AI Studio ke maujooda
  /// flash model naam se badal do (yehi waahid jagah hai jahan model naam hai).
  static const model = 'gemini-2.5-flash';
  static const _endpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';

  static const pageTimeout = Duration(seconds: 60);

  // ---------------------------------------------------------- key storage

  static Future<String?> getKey() async {
    final p = await SharedPreferences.getInstance();
    final k = p.getString(_prefsKey)?.trim();
    return (k == null || k.isEmpty) ? null : k;
  }

  static Future<void> saveKey(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_prefsKey, key.trim());
  }

  static Future<bool> hasKey() async => await getKey() != null;

  // ---------------------------------------------------------- AI call

  static const _prompt = '''
You are reading a Pakistani electronics shop's printed "Outstanding Report" table photo.
Extract EVERY customer data row. IGNORE: shop title, address, print date,
column header row, officer group header rows, and the Total row at the bottom.

Return ONLY a JSON object with exactly these keys:
- "rows": array of row objects (schema below)
- "printed_total_current_due": the Current Due total printed in the page's Total row (number), or null if there is no Total row
- "unreadable": array of short strings naming anything printed that you could NOT read clearly (e.g. "row 7 cell number", "row 12 current due")

Each row object:
- accountNo: string, e.g. "003112"
- accDate: string, e.g. "10-Aug-26"
- customerName: string
- inquiryOfficer: string
- cell: string of digits, e.g. "03001234567" (may be "03000000000")
- item: string, e.g. "MOBILE", "Bike", "AIR COOLER", "FRIDGE", "AC"
- price, balance, installment, osAmount, paid, currentDue: numbers WITHOUT commas
- lastInstDate: string, e.g. "30-Sep-26"
- officerGroup: the officer group section this row belongs to, e.g. "Amir Shehzad"
- raw_line: the printed line for this row, copied as closely as you can

STRICT RULES:
- NEVER guess or invent a digit. If a value is not clearly readable, use "" for a string or 0 for a number AND add an entry to "unreadable" naming that row and field.
- One object per printed customer row, in top-to-bottom order.
- currentDue must be copied as printed (it equals osAmount - paid in the print); do not recompute or "fix" numbers.
''';

  static Map<String, dynamic> get _responseSchema => {
        'type': 'object',
        'properties': {
          'rows': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'accountNo': {'type': 'string'},
                'accDate': {'type': 'string'},
                'customerName': {'type': 'string'},
                'inquiryOfficer': {'type': 'string'},
                'cell': {'type': 'string'},
                'item': {'type': 'string'},
                'price': {'type': 'number'},
                'balance': {'type': 'number'},
                'installment': {'type': 'number'},
                'osAmount': {'type': 'number'},
                'paid': {'type': 'number'},
                'currentDue': {'type': 'number'},
                'lastInstDate': {'type': 'string'},
                'officerGroup': {'type': 'string'},
                'raw_line': {'type': 'string'},
              },
              'required': ['accountNo', 'customerName'],
            },
          },
          'printed_total_current_due': {'type': 'number', 'nullable': true},
          'unreadable': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'required': ['rows'],
      };

  /// Ek page ki photo AI ko bhejo → saaf rows + na-parhi wajuhat + printed
  /// total. Kabhi throw nahi karta — har nakami `failed` me wazeh ati hai.
  /// Poora page khaali aye to halves me dobara try hota hai.
  static Future<
      ({
        List<OutstandingRow> rows,
        List<String> failed,
        double? printedTotalDue
      })> scanPage(String imagePath, String apiKey) async {
    Uint8List bytes;
    try {
      bytes = await File(imagePath).readAsBytes();
    } catch (e) {
      return (
        rows: <OutstandingRow>[],
        failed: ['Photo parhi nahi ja saki: $e'],
        printedTotalDue: null
      );
    }
    if (bytes.isEmpty) {
      return (
        rows: <OutstandingRow>[],
        failed: ['Photo khaali hai — dobara lo.'],
        printedTotalDue: null
      );
    }
    final full = await _scanBytes(bytes, apiKey);
    if (full.rows.isNotEmpty) return full;
    // Poora page khaali — lambi/bari table par halves me dobara try:
    // chhote digits har hisse me bare nazar ate hain.
    final halves = _splitHalves(bytes);
    if (halves == null) return full;
    final merged = <OutstandingRow>[];
    final failed = <String>[...full.failed];
    double? total = full.printedTotalDue;
    final seen = <String>{};
    for (final half in halves) {
      final res = await _scanBytes(half, apiKey);
      for (final r in res.rows) {
        final key = r.accountNo.isNotEmpty
            ? r.accountNo
            : '${r.name}|${r.cell}';
        if (seen.add(key)) merged.add(r);
      }
      failed.addAll(res.failed);
      total ??= res.printedTotalDue;
    }
    if (merged.isEmpty) return full;
    return (rows: merged, failed: failed, printedTotalDue: total);
  }

  /// Image ko lambi simt par do overlapping (10%) hisson me kato.
  /// Chhoti image par null (halves ka faida nahi).
  static List<Uint8List>? _splitHalves(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final oriented = img.bakeOrientation(decoded);
      final w = oriented.width, h = oriented.height;
      if ((w > h ? w : h) < 1400) return null;
      final out = <Uint8List>[];
      if (h >= w) {
        final half = h ~/ 2;
        final ov = (h * 0.05).round();
        out.add(img.encodeJpg(
            img.copyCrop(oriented, x: 0, y: 0, width: w, height: half + ov),
            quality: 92));
        out.add(img.encodeJpg(
            img.copyCrop(oriented,
                x: 0, y: half - ov, width: w, height: h - half + ov),
            quality: 92));
      } else {
        final half = w ~/ 2;
        final ov = (w * 0.05).round();
        out.add(img.encodeJpg(
            img.copyCrop(oriented, x: 0, y: 0, width: half + ov, height: h),
            quality: 92));
        out.add(img.encodeJpg(
            img.copyCrop(oriented,
                x: half - ov, y: 0, width: w - half + ov, height: h),
            quality: 92));
      }
      return out;
    } catch (e) {
      ErrorLog.log('AI scan halves', e);
      return null;
    }
  }

  /// Asal API call + jawab ki parsing (ek image ke bytes par).
  static Future<
      ({
        List<OutstandingRow> rows,
        List<String> failed,
        double? printedTotalDue
      })> _scanBytes(Uint8List bytes, String apiKey) async {
    final rows = <OutstandingRow>[];
    final failed = <String>[];
    double? printedTotal;
    try {
      // Pehle schema ke sath; schema par 400 aye to baghair schema ke
      // dobara (model/API ke chhote farq se feature band na ho).
      var resp = await _post(bytes, apiKey, withSchema: true);
      if (resp.statusCode == 400) {
        ErrorLog.log('AI scan schema 400', resp.body);
        resp = await _post(bytes, apiKey, withSchema: false);
      }
      if (resp.statusCode == 400 || resp.statusCode == 403) {
        failed.add(
            'API key ghalat ya band hai (HTTP ${resp.statusCode}). Profile me key dobara dalo.');
        ErrorLog.log('AI scan auth', 'HTTP ${resp.statusCode}: ${resp.body}');
        return (rows: rows, failed: failed, printedTotalDue: null);
      }
      if (resp.statusCode == 404) {
        failed.add(
            'Model "$model" nahi mila (HTTP 404) — developer se model naam update karwao.');
        ErrorLog.log('AI scan model', resp.body);
        return (rows: rows, failed: failed, printedTotalDue: null);
      }
      if (resp.statusCode != 200) {
        failed.add('AI service ne jawab nahi diya (HTTP ${resp.statusCode}).');
        ErrorLog.log('AI scan http', 'HTTP ${resp.statusCode}: ${resp.body}');
        return (rows: rows, failed: failed, printedTotalDue: null);
      }

      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        failed.add('AI ne koi jawab nahi diya — photo dobara lo.');
        return (rows: rows, failed: failed, printedTotalDue: null);
      }
      final parts =
          (candidates[0]['content']['parts'] as List?) ?? const [];
      final text = parts
          .map((p) => (p['text'] ?? '').toString())
          .join('')
          .trim();
      final payload = _extractPayload(text);
      if (payload == null) {
        failed.add('AI ka jawab samajh nahi aya — dobara koshish karo.');
        ErrorLog.log('AI scan parse',
            text.substring(0, text.length > 220 ? 220 : text.length));
        return (rows: rows, failed: failed, printedTotalDue: null);
      }

      final totalRaw = payload['printed_total_current_due'];
      if (totalRaw is num) printedTotal = totalRaw.toDouble();
      for (final u in (payload['unreadable'] as List? ?? const [])) {
        final s = u.toString().trim();
        if (s.isNotEmpty) failed.add('AI: na parh saka — $s');
      }

      final arr = payload['rows'] as List? ?? const [];
      var k = 0;
      for (final item in arr) {
        k++;
        if (item is! Map) {
          failed.add('Row $k: ghalat format — chhor di.');
          continue;
        }
        final m = Map<String, dynamic>.from(item);
        final accountNo = (m['accountNo'] ?? '').toString().trim();
        final name = (m['customerName'] ?? '').toString().trim();
        if (accountNo.isEmpty && name.isEmpty) {
          failed.add('Row $k: naam aur A/C dono khaali — chhor di.');
          continue;
        }
        double num(String key) {
          final v = (m[key] ?? 0).toString().replaceAll(',', '').trim();
          return double.tryParse(v) ?? 0;
        }

        final row = OutstandingRow(
          accountNo: accountNo,
          accDate: (m['accDate'] ?? '').toString().trim(),
          name: name,
          officer: (m['officerGroup'] ?? m['inquiryOfficer'] ?? '')
              .toString()
              .trim(),
          cell: (m['cell'] ?? '').toString().replaceAll(RegExp(r'\D'), ''),
          item: (m['item'] ?? '').toString().trim(),
          price: num('price'),
          balance: num('balance'),
          installment: num('installment'),
          osAmount: num('osAmount'),
          paid: num('paid'),
          currentDue: num('currentDue'),
          lastInstDate: (m['lastInstDate'] ?? '').toString().trim(),
        );
        rows.add(applyMathCheck(row));
      }
    } catch (e) {
      ErrorLog.log('AI scan page', e);
      failed.add('AI se rabta nahi ho saka: $e');
    }
    return (rows: rows, failed: failed, printedTotalDue: printedTotal);
  }

  static Future<http.Response> _post(Uint8List bytes, String apiKey,
      {required bool withSchema}) {
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': _prompt},
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Encode(bytes),
              }
            },
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.0,
        'responseMimeType': 'application/json',
        if (withSchema) 'responseSchema': _responseSchema,
      },
    });
    return http
        .post(
          Uri.parse('$_endpoint?key=$apiKey'),
          headers: {'Content-Type': 'application/json'},
          body: body,
        )
        .timeout(pageTimeout);
  }

  /// Model ke jawab se payload nikalo — object {"rows":[...]} ya purani
  /// bare array, code fences ke sath/bar — sab bardasht karo.
  static Map<String, dynamic>? _extractPayload(String text) {
    var t = text.trim();
    final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$');
    final fm = fence.firstMatch(t);
    if (fm != null) t = fm.group(1)!.trim();
    // Object ki koshish pehle.
    final os = t.indexOf('{');
    final oe = t.lastIndexOf('}');
    if (os >= 0 && oe > os) {
      try {
        final v = jsonDecode(t.substring(os, oe + 1));
        if (v is Map<String, dynamic> && v['rows'] is List) return v;
      } catch (_) {}
    }
    final start = t.indexOf('[');
    final end = t.lastIndexOf(']');
    if (start < 0 || end <= start) return null;
    try {
      final v = jsonDecode(t.substring(start, end + 1));
      if (v is List) return {'rows': v};
      return null;
    } catch (_) {
      return null;
    }
  }
}
