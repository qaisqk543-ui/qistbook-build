/// AI Scan (internet) — Outstanding Report ka page Gemini vision ko bhejo,
/// AI table parh kar SAAF JSON rows wapas de. Ye rows phir waheN review/
/// confirm pipeline me jati hain jo OCR wali rows use karti hain.
///
/// API KEY HARDCODE NAHI: user Profile → "AI Scan API Key (Gemini)" me apni
/// free Gemini key dalta hai (SharedPreferences, sirf is phone par).
/// Key sirf is feature ke HTTPS calls me use hoti hai.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
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
Extract EVERY customer data row into a JSON array. IGNORE: shop title, address, print date,
column header row, officer group header rows, and the Total row at the bottom.

Return ONLY the JSON array — no markdown, no explanation, no other text.

Each object must have exactly these keys:
- accountNo: string, e.g. "003112"
- accDate: string, e.g. "10-Aug-26"
- customerName: string
- inquiryOfficer: string
- cell: string of digits, e.g. "03001234567" (may be "03000000000")
- item: string, e.g. "MOBILE", "Bike", "AIR COOLER", "FRIDGE", "AC"
- price, balance, installment, osAmount, paid, currentDue: numbers WITHOUT commas
- lastInstDate: string, e.g. "30-Sep-26"
- officerGroup: the officer group section this row belongs to, e.g. "Amir Shehzad"

Rules:
- One object per printed customer row, in top-to-bottom order.
- If a printed value is unreadable: use "" for strings and 0 for numbers. NEVER invent values.
- currentDue must equal osAmount - paid as printed; copy the printed numbers, do not recompute.
''';

  /// Ek page ki photo AI ko bhejo → saaf rows + na-manzoor rows ki wajuhat.
  /// Kabhi throw nahi karta — har nakami `failed` me wazeh lafzon me ati hai.
  static Future<({List<OutstandingRow> rows, List<String> failed})> scanPage(
      String imagePath, String apiKey) async {
    final rows = <OutstandingRow>[];
    final failed = <String>[];
    try {
      final bytes = await File(imagePath).readAsBytes();
      if (bytes.isEmpty) {
        failed.add('Photo khaali hai — dobara lo.');
        return (rows: rows, failed: failed);
      }
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
        },
      });

      final resp = await http
          .post(
            Uri.parse('$_endpoint?key=$apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(pageTimeout);

      if (resp.statusCode == 400 || resp.statusCode == 403) {
        failed.add(
            'API key ghalat ya band hai (HTTP ${resp.statusCode}). Profile me key dobara dalo.');
        ErrorLog.log('AI scan auth', 'HTTP ${resp.statusCode}: ${resp.body}');
        return (rows: rows, failed: failed);
      }
      if (resp.statusCode == 404) {
        failed.add(
            'Model "$model" nahi mila (HTTP 404) — developer se model naam update karwao.');
        ErrorLog.log('AI scan model', resp.body);
        return (rows: rows, failed: failed);
      }
      if (resp.statusCode != 200) {
        failed.add('AI service ne jawab nahi diya (HTTP ${resp.statusCode}).');
        ErrorLog.log('AI scan http', 'HTTP ${resp.statusCode}: ${resp.body}');
        return (rows: rows, failed: failed);
      }

      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        failed.add('AI ne koi jawab nahi diya — photo dobara lo.');
        return (rows: rows, failed: failed);
      }
      final parts =
          (candidates[0]['content']['parts'] as List?) ?? const [];
      final text = parts
          .map((p) => (p['text'] ?? '').toString())
          .join('')
          .trim();
      final arr = _extractJsonArray(text);
      if (arr == null) {
        failed.add('AI ka jawab samajh nahi aya — dobara koshish karo.');
        ErrorLog.log('AI scan parse', text.substring(0, text.length > 220 ? 220 : text.length));
        return (rows: rows, failed: failed);
      }

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
    return (rows: rows, failed: failed);
  }

  /// Model ke jawab se JSON array nikalo — code fences waghera bardasht karo.
  static List? _extractJsonArray(String text) {
    var t = text.trim();
    // ```json ... ``` fences hatao
    final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$');
    final fm = fence.firstMatch(t);
    if (fm != null) t = fm.group(1)!.trim();
    final start = t.indexOf('[');
    final end = t.lastIndexOf(']');
    if (start < 0 || end <= start) return null;
    try {
      final v = jsonDecode(t.substring(start, end + 1));
      return v is List ? v : null;
    } catch (_) {
      return null;
    }
  }
}
