/// Pure-Dart PDF text-layer extraction — koi native dependency nahi.
///
/// Kuch PDFs (jo software se seedha export hoti hain, jaise shop ki
/// Outstanding Report) ke andar asal text pehle se hota hai. Un ke liye
/// page ko image bana kar OCR karna bekaar bhi hai aur phone par sab se
/// zyada fail hone wala rasta bhi (ML Kit model / pdf renderer).
/// Ye extractor FlateDecode streams khol kar content stream ke
/// Tj / TJ / Td / Tm operators se text lines banata hai.
///
/// Scanned-image PDFs (photo wali) me text layer nahi hota — wahan ye
/// khaali list deta hai aur caller purane render+OCR raste par jata hai.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// PDF bytes → text lines (reading order ki best koshish).
/// Khaali/na-kaafi text mile to [] — caller OCR fallback lega.
List<String> extractPdfTextLines(List<int> bytes) {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final lines = <String>[];
  var idx = 0;
  while (true) {
    final s = _indexOfAscii(data, 'stream', idx);
    if (s < 0) break;
    var start = s + 6;
    if (start < data.length && data[start] == 13) start++;
    if (start < data.length && data[start] == 10) start++;
    final e = _indexOfAscii(data, 'endstream', start);
    if (e < 0) break;
    var end = e;
    while (end > start && (data[end - 1] == 10 || data[end - 1] == 13)) {
      end--;
    }
    idx = e + 9;
    if (end <= start) continue;
    final raw = data.sublist(start, end);
    // Is stream ke dictionary me konsi filters hain? (pichle ~1000 bytes)
    // Tartib wahi jo /Filter list me hai — pehle wahi apply hogi.
    // ReportLab jaisay generator ASCII85+Flate dono lagate hain.
    final dictStart = s - 1000 < 0 ? 0 : s - 1000;
    final dictText =
        latin1.decode(data.sublist(dictStart, s), allowInvalid: true);
    final filters = RegExp(r'/([A-Za-z0-9]+)Decode')
        .allMatches(dictText)
        .map((m) => m.group(1)!)
        .toList();
    List<int>? content = raw;
    for (final f in filters) {
      if (content == null) break;
      try {
        if (f == 'Flate' || f == 'Fl') {
          content = ZLibDecoder().convert(content);
        } else if (f == 'ASCII85' || f == 'A85') {
          content = _ascii85Decode(content);
        } else if (f == 'ASCIIHex' || f == 'AHx') {
          content = _asciiHexDecode(content);
        }
        // Baqi filters (DCT/JPEG waghera) text ke liye nahi — as-is rehne do,
        // neeche BT check khud reject kar dega.
      } catch (_) {
        content = null; // kharab stream — skip
      }
    }
    if (content == null) continue;
    final text = latin1.decode(content, allowInvalid: true);
    if (!text.contains('BT')) continue; // content stream nahi (font/image)
    lines.addAll(_parseContentStream(text));
  }
  // Khaali lines hatao, lekin tartib rakho.
  return lines.where((l) => l.trim().isNotEmpty).toList();
}

/// Adobe ASCII85 decode: '!' (33) se 'u' (117) tak ke 5 harf = 4 bytes,
/// 'z' = 4 zero bytes, aakhri adhoora group (2–4 harf) = 1–3 bytes.
/// '~>' terminator aur whitespace ignore hote hain.
List<int> _ascii85Decode(List<int> input) {
  final out = <int>[];
  final group = <int>[];
  void flushGroup(int count) {
    // count harf aaye (2..5) → count-1 bytes
    var val = 0;
    for (var k = 0; k < 5; k++) {
      val = val * 85 + (k < group.length ? group[k] : 84);
    }
    final bytes = [
      (val >> 24) & 0xFF,
      (val >> 16) & 0xFF,
      (val >> 8) & 0xFF,
      val & 0xFF,
    ];
    out.addAll(count >= 2 ? bytes.take(count - 1) : bytes);
    group.clear();
  }

  var i = 0;
  while (i < input.length) {
    final c = input[i];
    if (c == 126 /* ~ */ && i + 1 < input.length && input[i + 1] == 62) {
      break; // '~>' khatam
    }
    if (c == 122 /* z */ && group.isEmpty) {
      out.addAll(const [0, 0, 0, 0]);
      i++;
      continue;
    }
    if (c <= 32) {
      i++; // whitespace
      continue;
    }
    if (c < 33 || c > 117) {
      i++; // ajnabi harf — skip
      continue;
    }
    group.add(c - 33);
    i++;
    if (group.length == 5) flushGroup(5);
  }
  if (group.length >= 2) {
    flushGroup(group.length);
  }
  return out;
}

/// ASCIIHex decode: hex joray, '>' par khatam.
List<int> _asciiHexDecode(List<int> input) {
  final out = <int>[];
  int? hi;
  for (final c in input) {
    if (c == 62 /* > */) break;
    final v = _hexVal(c);
    if (v < 0) continue;
    if (hi == null) {
      hi = v;
    } else {
      out.add((hi << 4) | v);
      hi = null;
    }
  }
  if (hi != null) out.add(hi << 4);
  return out;
}

int _hexVal(int c) {
  if (c >= 48 && c <= 57) return c - 48;
  if (c >= 65 && c <= 70) return c - 55;
  if (c >= 97 && c <= 102) return c - 87;
  return -1;
}

int _indexOfAscii(Uint8List data, String needle, int from) {
  final n = needle.codeUnits;
  outer:
  for (var i = from; i + n.length <= data.length; i++) {
    for (var j = 0; j < n.length; j++) {
      if (data[i + j] != n[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// Ek string operand ko bytes se text me badlo (UTF-16BE BOM ya WinAnsi).
String _decodePdfBytes(List<int> b) {
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
    final sb = StringBuffer();
    for (var i = 2; i + 1 < b.length; i += 2) {
      sb.writeCharCode((b[i] << 8) | b[i + 1]);
    }
    return sb.toString();
  }
  return latin1.decode(b, allowInvalid: true);
}

/// Ek text run: position (Tm/Td se) + text. Baad me y se lines banti hain.
class _Run {
  final double x;
  final double y;
  final String text;
  const _Run(this.x, this.y, this.text);
}

/// Content stream tokenizer + text operators.
/// Har text run apni (x, y) position ke sath ikattha hota hai; aakhir me
/// runs ko y (line) aur x (tartib) se jor kar asal lines banti hain —
/// ReportLab jaisay generators har cell alag run me likhte hain, is liye
/// sirf operator tartib par lines banana galat hota.
List<String> _parseContentStream(String s) {
  final runs = <_Run>[];
  final buf = StringBuffer();
  var curX = 0.0;
  var curY = 0.0;
  var runX = 0.0;
  var runY = 0.0;
  void flushRun() {
    final t = buf.toString();
    if (t.isNotEmpty) runs.add(_Run(runX, runY, t));
    buf.clear();
  }

  final stack = <Object?>[];
  var i = 0;
  final len = s.length;
  while (i < len) {
    final c = s[i];
    // Whitespace / comment
    if (c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f') {
      i++;
      continue;
    }
    if (c == '%') {
      while (i < len && s[i] != '\n') i++;
      continue;
    }
    // Literal string (...)
    if (c == '(') {
      final (str, next) = _readLiteral(s, i);
      stack.add(str);
      i = next;
      continue;
    }
    // Hex string <...> (<< dict nahi)
    if (c == '<' && (i + 1 >= len || s[i + 1] != '<')) {
      final (str, next) = _readHex(s, i);
      stack.add(str);
      i = next;
      continue;
    }
    // Array [...]
    if (c == '[') {
      final arr = <Object?>[];
      i++;
      while (i < len && s[i] != ']') {
        final ch = s[i];
        if (ch == '(') {
          final (str, next) = _readLiteral(s, i);
          arr.add(str);
          i = next;
        } else if (ch == '<' && (i + 1 >= len || s[i + 1] != '<')) {
          final (str, next) = _readHex(s, i);
          arr.add(str);
          i = next;
        } else if (_isNumStart(ch)) {
          final (num, next) = _readNumber(s, i);
          arr.add(num);
          i = next;
        } else {
          i++;
        }
      }
      i++; // ']'
      stack.add(arr);
      continue;
    }
    // Number
    if (_isNumStart(c)) {
      final (num, next) = _readNumber(s, i);
      stack.add(num);
      i = next;
      continue;
    }
    // Name /name — operand, ignore ('/' khud delimiter hai, pehle aage barho)
    if (c == '/') {
      i++;
      while (i < len && !_isDelimiter(s[i])) i++;
      stack.add(null);
      continue;
    }
    // Bare word = operator
    if (_isLetter(c) || c == "'" || c == '"' || c == '*') {
      var j = i;
      while (j < len &&
          (_isLetter(s[j]) || s[j] == "'" || s[j] == '"' || s[j] == '*')) {
        j++;
      }
      final op = s.substring(i, j);
      i = j;
      // ---- text operators (position-aware) ----
      switch (op) {
        case 'Tj':
          if (stack.isNotEmpty && stack.last is String) {
            buf.write(stack.last as String);
          }
        case "'":
        case '"':
          // Agli line par ja kar text — purana run band, y neeche
          flushRun();
          curY -= 12;
          runX = curX;
          runY = curY;
          if (stack.isNotEmpty && stack.last is String) {
            buf.write(stack.last as String);
          }
        case 'TJ':
          if (stack.isNotEmpty && stack.last is List) {
            for (final el in stack.last as List) {
              if (el is String) {
                buf.write(el);
              } else if (el is num && el <= -120) {
                buf.write(' '); // bara gap = lafzon ke darmiyan space
              }
            }
          }
        case 'Td':
        case 'TD':
          if (stack.length >= 2) {
            final tx = stack[stack.length - 2];
            final ty = stack.last;
            flushRun();
            if (tx is num) curX += tx.toDouble();
            if (ty is num) curY += ty.toDouble();
            runX = curX;
            runY = curY;
          }
        case 'T*':
          flushRun();
          curY -= 12;
          runX = curX;
          runY = curY;
        case 'Tm':
          // operands: a b c d e f — e=x, f=y (absolute position)
          if (stack.length >= 6) {
            final e = stack[stack.length - 2];
            final f = stack.last;
            flushRun();
            if (e is num) curX = e.toDouble();
            if (f is num) curY = f.toDouble();
            runX = curX;
            runY = curY;
          }
        case 'BT':
          curX = 0;
          curY = 0;
          runX = 0;
          runY = 0;
        case 'ET':
          flushRun();
      }
      stack.clear();
      continue;
    }
    i++; // koi aur delimiter — aage barho
  }
  flushRun();

  // Runs → lines: y descending (page par upar wali line pehle),
  // 2pt tolerance se grouping, line ke andar x ascending.
  runs.sort((a, b) {
    final dy = b.y.compareTo(a.y);
    if (dy != 0) return dy;
    return a.x.compareTo(b.x);
  });
  final lines = <String>[];
  double? lineY;
  var parts = <_Run>[];
  void flushLine() {
    if (parts.isEmpty) return;
    parts.sort((a, b) => a.x.compareTo(b.x));
    final t = parts.map((r) => r.text.trim()).where((t) => t.isNotEmpty).join(' ');
    if (t.trim().isNotEmpty) lines.add(t);
    parts = <_Run>[];
  }

  for (final r in runs) {
    if (lineY == null || (r.y - lineY).abs() > 2.0) {
      flushLine();
      lineY = r.y;
    }
    parts.add(r);
  }
  flushLine();
  return lines;
}

bool _isDelimiter(String c) =>
    c == ' ' ||
    c == '\t' ||
    c == '\r' ||
    c == '\n' ||
    c == '\f' ||
    c == '(' ||
    c == ')' ||
    c == '<' ||
    c == '>' ||
    c == '[' ||
    c == ']' ||
    c == '/' ||
    c == '%';

bool _isLetter(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 65 && u <= 90) || (u >= 97 && u <= 122);
}

bool _isNumStart(String c) =>
    (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) ||
    c == '-' ||
    c == '+' ||
    c == '.';

(double, int) _readNumber(String s, int i) {
  var j = i;
  while (j < s.length) {
    final c = s[j];
    if ((c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) ||
        c == '-' ||
        c == '+' ||
        c == '.') {
      j++;
    } else {
      break;
    }
  }
  return (double.tryParse(s.substring(i, j)) ?? 0, j);
}

/// Literal string: escapes + nested parens. (value, nextIndex) deta hai.
(String, int) _readLiteral(String s, int i) {
  final bytes = <int>[];
  var depth = 1;
  i++; // '('
  while (i < s.length && depth > 0) {
    final c = s[i];
    if (c == '\\' && i + 1 < s.length) {
      final n = s[i + 1];
      switch (n) {
        case 'n':
          bytes.add(10);
          i += 2;
        case 'r':
          bytes.add(13);
          i += 2;
        case 't':
          bytes.add(9);
          i += 2;
        case '(':
          bytes.add(40);
          i += 2;
        case ')':
          bytes.add(41);
          i += 2;
        case '\\':
          bytes.add(92);
          i += 2;
        default:
          // Octal escape \ddd (1-3 digits) ya agla harf as-is
          if (_isDigit(n)) {
            var j = i + 1;
            var val = 0;
            var count = 0;
            while (j < s.length && count < 3 && _isDigit(s[j])) {
              val = val * 8 + (s[j].codeUnitAt(0) - 48);
              j++;
              count++;
            }
            bytes.add(val & 0xFF);
            i = j;
          } else {
            bytes.add(n.codeUnitAt(0) & 0xFF);
            i += 2;
          }
      }
      continue;
    }
    if (c == '(') {
      depth++;
      bytes.add(40);
      i++;
      continue;
    }
    if (c == ')') {
      depth--;
      if (depth > 0) bytes.add(41);
      i++;
      continue;
    }
    bytes.add(c.codeUnitAt(0) & 0xFF);
    i++;
  }
  return (_decodePdfBytes(bytes), i);
}

bool _isDigit(String c) {
  final u = c.codeUnitAt(0);
  return u >= 48 && u <= 57;
}

/// Hex string <4A6F...>: (value, nextIndex).
(String, int) _readHex(String s, int i) {
  i++; // '<'
  final hex = StringBuffer();
  while (i < s.length && s[i] != '>') {
    final c = s[i];
    if (c.trim().isNotEmpty) hex.write(c);
    i++;
  }
  i++; // '>'
  var h = hex.toString();
  if (h.length.isOdd) h = '${h}0';
  final bytes = <int>[];
  for (var k = 0; k + 2 <= h.length; k += 2) {
    bytes.add(int.tryParse(h.substring(k, k + 2), radix: 16) ?? 0);
  }
  return (_decodePdfBytes(bytes), i);
}
