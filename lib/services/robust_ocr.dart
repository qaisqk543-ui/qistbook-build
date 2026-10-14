/// Robust OCR (v1.0.39) — do bahar ke AI reviews ke baad ki overhaul.
///
/// Donon reviews ka ek hi nateeja tha: parser theek hai, masla ML Kit ko
/// diye jane wale IMAGE ka hai. Is liye har page pehle NORMALIZE hota hai:
///   decode → EXIF orientation pixels me bake → bohat bara ho to 4200px
///   cap → taaza JPEG likh kar wahi OCR ko do.
/// Aur jo page bohat lamba/chora ho, wo TILES me kat kar parha jata hai —
/// ML Kit andar se bari image ko chhota kar deta hai jis se chhote digits
/// mit jate hain; tile karne se har hisse ke digits pure size par rehte
/// hain. Har tile ke words asal page ke coordinates par wapas jor kar
/// dedupe kiye jate hain.
///
/// InputImage.fromBytes JAN BOOJH kar istemal nahi hua: JPEG bytes ko
/// NV21/raw keh kar dene se khamoshi se khaali result ata hai (review ki
/// warning). Hamesha fromFilePath, hamesha asal JPEG file.
///
/// Har run ki diagnosis [lastDiag] me rehti hai — khaali result par banner
/// me wazeh wajah (file size / dimensions) dikhti hai, andaza nahi lagta.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'error_log.dart';
import 'parsers.dart';

/// Ek OCR run ki diagnosis — banner + error log ke liye.
class OcrDiag {
  String verdict = 'OK'; // OK | FILE_MISSING_OR_EMPTY | DECODE_FAIL | NO_TEXT
  int fileBytes = 0;
  int width = 0;
  int height = 0;
  int words = 0;
  int tiles = 1;

  /// User ko dikhane wali saada wajah (khaali result par).
  String get userHint {
    switch (verdict) {
      case 'FILE_MISSING_OR_EMPTY':
        return 'Photo wali file khaali ya mili hi nahi — photo dobara lo.';
      case 'DECODE_FAIL':
        return 'Photo khul hi nahi saki (format kharab) — photo dobara lo.';
      case 'NO_TEXT':
        return 'Page parh kar koi lafz nahi mila '
            '($width×$height, ${(fileBytes / 1024).toStringAsFixed(0)} KB). '
            'Photo seedhi, qareeb se aur achi roshni me dobara lo — ya AI Scan try karo.';
      default:
        return '';
    }
  }

  @override
  String toString() =>
      'verdict=$verdict bytes=$fileBytes size=${width}x$height words=$words tiles=$tiles';
}

class RobustOcr {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  /// Aakhri run ki diagnosis.
  OcrDiag lastDiag = OcrDiag();

  static const int _capDimension = 4200;
  static const int _tileThreshold = 2800;
  static const int _tileTarget = 2200;

  Future<void> close() async {
    try {
      await _recognizer.close();
    } catch (_) {}
  }

  /// Page ki file → positioned words (asal page ke coordinates par).
  /// Khaali list bhi ek valid nateeja hai — wajah [lastDiag] me milegi.
  /// Sirf asal nakami (file gayab waghera) par throw hota hai.
  Future<List<OcrWord>> recognizeWords(String path) async {
    final diag = OcrDiag();
    lastDiag = diag;
    final file = File(path);
    if (!await file.exists()) {
      diag.verdict = 'FILE_MISSING_OR_EMPTY';
      throw const FileSystemException('OCR wali file nahi mili');
    }
    diag.fileBytes = await file.length();
    if (diag.fileBytes < 16) {
      diag.verdict = 'FILE_MISSING_OR_EMPTY';
      throw const FormatException('OCR wali file khaali hai');
    }

    // ---- normalize: decode + EXIF bake (+ cap) -------------------------
    img.Image? decoded;
    try {
      decoded = img.decodeImage(await file.readAsBytes());
    } catch (e) {
      ErrorLog.log('RobustOCR decode', e);
    }
    if (decoded == null) {
      // Decode fail — asal file par ek seedhi koshish phir bhi karo
      // (kuch formats image package nahi, ML Kit parh leta hai).
      diag.verdict = 'DECODE_FAIL';
      final words = await _recognizeFile(path, 0, 0);
      diag.words = words.length;
      if (words.isNotEmpty) diag.verdict = 'OK';
      return words;
    }
    final oriented = img.bakeOrientation(decoded);
    diag.width = oriented.width;
    diag.height = oriented.height;

    // ---- tiles banao (lambi/choray safhay ke liye) ----------------------
    final tiles = await _writeTiles(oriented);
    diag.tiles = tiles.length;
    final all = <OcrWord>[];
    for (final t in tiles) {
      all.addAll(await _recognizeFile(t.path, t.dx, t.dy));
      try {
        await File(t.path).delete();
      } catch (_) {}
    }
    final words = dedupeOcrWords(all);
    diag.words = words.length;
    diag.verdict = words.isEmpty ? 'NO_TEXT' : 'OK';
    ErrorLog.log('RobustOCR', diag.toString());
    return words;
  }

  /// Oriented image ko temp JPEG tiles me likho. Chhota page = 1 tile.
  /// Tile ka (dx, dy) = page par us tile ke top-left ka offset.
  Future<List<({String path, int dx, int dy})>> _writeTiles(
      img.Image page) async {
    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final out = <({String path, int dx, int dy})>[];

    Future<String> save(img.Image im, String suffix) async {
      final f = File('${tmp.path}/qist_ocr_${stamp}_$suffix.jpg');
      await f.writeAsBytes(img.encodeJpg(im, quality: 92), flush: true);
      return f.path;
    }

    final w = page.width, h = page.height;
    final longest = math.max(w, h);
    var work = page;
    var scale = 1.0;
    if (longest > _capDimension) {
      scale = _capDimension / longest;
      work = img.copyResize(
        page,
        width: (w * scale).round(),
        height: (h * scale).round(),
        interpolation: img.Interpolation.linear,
      );
    }
    final ww = work.width, hh = work.height;
    if (math.max(ww, hh) <= _tileThreshold) {
      out.add((path: await save(work, 'full'), dx: 0, dy: 0));
      return out;
    }
    // Lambi simt ko _tileTarget ke hisson me kato, 12% overlap ke sath.
    final alongWidth = ww >= hh;
    final longSide = alongWidth ? ww : hh;
    final count = (longSide / _tileTarget).ceil();
    final seg = longSide / count;
    final overlap = seg * 0.12;
    for (var i = 0; i < count; i++) {
      final start = math.max(0.0, i * seg - (i == 0 ? 0 : overlap));
      final end = math.min(
          longSide.toDouble(), (i + 1) * seg + (i == count - 1 ? 0 : overlap));
      final tile = alongWidth
          ? img.copyCrop(work,
              x: start.round(),
              y: 0,
              width: (end - start).round(),
              height: hh)
          : img.copyCrop(work,
              x: 0,
              y: start.round(),
              width: ww,
              height: (end - start).round());
      out.add((
        path: await save(tile, 't$i'),
        dx: alongWidth ? start.round() : 0,
        dy: alongWidth ? 0 : start.round(),
      ));
    }
    return out;
  }

  /// Ek file OCR karo → words, (dx, dy) offset ke sath.
  Future<List<OcrWord>> _recognizeFile(String path, int dx, int dy) async {
    final input = InputImage.fromFilePath(path);
    final result = await _recognizer.processImage(input);
    final words = <OcrWord>[];
    for (final block in result.blocks) {
      for (final line in block.lines) {
        for (final el in line.elements) {
          if (el.text.trim().isEmpty) continue;
          final b = el.boundingBox;
          words.add(OcrWord(el.text,
              left: b.left + dx, right: b.right + dx, top: b.top + dy));
        }
      }
    }
    return words;
  }

  /// Engine self-test (Troubleshooting ke liye): khud text bana kar OCR
  /// karo. Ye pass ho jaye to engine/model theek hai — masla photo ka hai.
  /// Fail ho to masla engine ka hai. Returns (ok, tafseel).
  Future<(bool, String)> selfTest() async {
    try {
      final canvas = img.Image(width: 1200, height: 420);
      img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
      img.drawString(canvas, 'QISTBOOK 12345',
          font: img.arial48, x: 60, y: 90, color: img.ColorRgb8(0, 0, 0));
      img.drawString(canvas, 'Total 678.90 Due',
          font: img.arial48, x: 60, y: 220, color: img.ColorRgb8(0, 0, 0));
      final tmp = await getTemporaryDirectory();
      final f = File('${tmp.path}/qist_ocr_selftest.png');
      await f.writeAsBytes(img.encodePng(canvas), flush: true);
      final words = await _recognizeFile(f.path, 0, 0);
      try {
        await f.delete();
      } catch (_) {}
      final joined = words.map((w) => w.text).join(' ');
      final ok = joined.contains('QISTBOOK') || joined.contains('12345');
      return (
        ok,
        ok
            ? 'Engine theek hai ✓ — $joined'
            : 'Engine ne apna banaya hua text bhi nahi parha (words: ${words.length}). '
                'Masla OCR engine/model ka hai, photo ka nahi.'
      );
    } catch (e) {
      return (false, 'Self-test chal hi nahi saka: $e');
    }
  }
}
