/// Import flow — 3 asaan tareeqe, dono document types ke liye:
///  1. Scan karo (camera) — ek ya zyada pages, ek ke baad ek
///  2. Gallery se photos chuno
///  3. PDF file upload karo (multiple customers)
///
/// Phir: OCR (on-device ML Kit) → parse → REVIEW screen → Confirm & Save.
/// Save karte hi data foran update + cloud sync.
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';

import '../models/customer.dart';
import '../services/customer_store.dart';
import '../services/error_log.dart';
import '../services/parsers.dart';
import '../services/pdf_text.dart';
import '../theme/app_theme.dart';
import 'manual_entry_screen.dart';

enum DocType { outstanding, statement }

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  DocType _docType = DocType.outstanding;
  bool _busy = false;
  String _status = '';

  /// Persistent result/error banner — kabhi finally me clear NAHI hota.
  /// Sirf nayi operation shuru hone par ya user ke dismiss par hat-ta hai,
  /// taake koi bhi failure "wapas khaali page" ban kar ghayab na ho.
  String _notice = '';
  bool _noticeIsError = true;

  /// Aakhri run ka raw OCR text — 0 rows parhe to diagnosis ke liye
  /// user ko dikhaya/copy karaya jata hai.
  String _rawOcr = '';

  /// Aakhri OCR ghalti (ML Kit) — 0 rows par banner me wajah dikhane ko.
  String _lastOcrError = '';

  /// Har failure yahin se guzre: log + busy off + persistent banner.
  /// Sirf user-cancel wala return silent rehta hai.
  void _fail(String msg, {Object? error, String screen = 'Import'}) {
    if (error != null) ErrorLog.log(screen, error);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _notice = msg;
      _noticeIsError = true;
    });
  }

  void _clearNotice() {
    if (!mounted) return;
    setState(() {
      _notice = '';
      _rawOcr = '';
    });
  }

  // Multi-page scan staging
  bool _staging = false;
  final List<String> _stagedPaths = [];

  // Parse results (review)
  List<OutstandingRow> _rows = [];
  List<String> _failed = [];
  List<OfficerGroupCheck> _groups = [];
  bool? _pageTotalOk;
  double _pageTotalDue = 0;
  double _parsedTotalDue = 0;
  List<_StatementDraft> _statements = [];
  bool _markCleared = true;

  final _picker = ImagePicker();

  String _rs(double v) => v.toStringAsFixed(0);

  // ------------------------------------------------------------ OCR helpers

  /// OCR with one retry — ML Kit ka text model pehli dafa background me
  /// download hota hai; pehli koshish fail ho to thodi der ruk kar doosri
  /// aksar kamyab ho jati hai. Aakhri ghalti _lastOcrError me rehti hai
  /// taake 0-rows wale banner me asal wajah likhi ja sake.
  Future<List<OcrLine>> _ocrImageLines(String path) async {
    try {
      return await _ocrImageLinesOnce(path);
    } catch (e) {
      _lastOcrError = '$e';
      await Future.delayed(const Duration(milliseconds: 1500));
      return _ocrImageLinesOnce(path);
    }
  }

  Future<List<OcrLine>> _ocrImageLinesOnce(String path) async {
    final input = InputImage.fromFilePath(path);
    final recognizer =
        TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(input);
      // Table OCR fix: ML Kit ki apni line-grouping par bharosa nahi —
      // kabhi do rows ek line me jor deta hai, kabhi ek row tor deta hai
      // (columns vertically parhne wali ghalti). Saare elements ikattha
      // karke Y-coordinate (14px tolerance) se rows banao, phir har row
      // left-to-right sort karo.
      final elems = <OcrWord>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          for (final el in line.elements) {
            final b = el.boundingBox;
            if (el.text.trim().isEmpty) continue;
            elems.add(OcrWord(el.text,
                left: b.left, right: b.right, top: b.top));
          }
        }
      }
      // Duplicate elements hatao: ML Kit aksar ek hi printed lafz ko do
      // overlapping boxes me do baar deta hai ("7150" + "7150"). Bina dedup
      // ke ye column me "7150 7150" jur kar _num me "71507150" ban jata tha
      // (screenshot wala bug). Markaz qareeb + text milta = duplicate.
      final deduped = <OcrWord>[];
      for (final e in elems) {
        var dupIdx = -1;
        for (var i = 0; i < deduped.length; i++) {
          final d = deduped[i];
          final te = e.text.trim(), td = d.text.trim();
          if (!(te == td || te.contains(td) || td.contains(te))) continue;
          final w = (e.right - e.left) < (d.right - d.left)
              ? (e.right - e.left)
              : (d.right - d.left);
          if ((e.cx - d.cx).abs() > w * 0.6) continue;
          if ((e.top - d.top).abs() > 14.0) continue;
          dupIdx = i;
          break;
        }
        if (dupIdx >= 0) {
          // Lamba (mukammal) wala rakho: "4100" rahe, "410" jaye.
          if (e.text.trim().length > deduped[dupIdx].text.trim().length) {
            deduped[dupIdx] = e;
          }
        } else {
          deduped.add(e);
        }
      }
      final rows = <List<OcrWord>>[];
      final rowTops = <double>[];
      for (final e in deduped) {
        var placed = -1;
        for (var i = 0; i < rows.length; i++) {
          if ((rowTops[i] - e.top).abs() < 14.0) {
            placed = i;
            break;
          }
        }
        if (placed >= 0) {
          rows[placed].add(e);
          final r = rows[placed];
          rowTops[placed] =
              r.map((w) => w.top).reduce((a, b) => a + b) / r.length;
        } else {
          rows.add([e]);
          rowTops.add(e.top);
        }
      }
      final lines = <OcrLine>[];
      for (final r in rows) {
        r.sort((a, b) => a.cx.compareTo(b.cx));
        lines.add(OcrLine(r));
      }
      lines.sort((a, b) =>
          a.words.first.top.compareTo(b.words.first.top));
      return lines;
    } finally {
      await recognizer.close();
    }
  }

  /// Rasterize every PDF page to a temp PNG so OCR can read it.
  /// Har page alag try/catch me — ek kharab page baqiyon ko nahi rokta.
  Future<List<String>> _pdfToImagePaths(
      String pdfPath, void Function(String) onStep) async {
    final doc = await PdfDocument.openFile(pdfPath);
    final out = <String>[];
    final tmp = Directory.systemTemp;
    try {
      final n = doc.pagesCount;
      for (var i = 1; i <= n; i++) {
        onStep('Page $i/$n tayaar ho raha hai…');
        try {
          final page = await doc.getPage(i);
          try {
            final img = await page.render(
                width: page.width * 2,
                height: page.height * 2,
                format: PdfPageImageFormat.png);
            final bytes = img?.bytes;
            if (bytes == null || bytes.isEmpty) {
              debugPrint('QistBook: PDF page $i rendered empty — skip');
              continue; // sirf ye page skip, baqi pages jari rahen
            }
            final file = File('${tmp.path}/kistbook_p$i.png');
            await file.writeAsBytes(bytes);
            out.add(file.path);
          } finally {
            await page.close();
          }
        } catch (e) {
          // Ye page skip — baqi pages ka data zaya nahi hoga.
          debugPrint('QistBook: PDF page $i render fail: $e');
        }
      }
    } finally {
      await doc.close();
    }
    return out;
  }

  // ------------------------------------------------------------ input methods

  /// Table OCR pipeline — Step 1-4: document detection, perspective
  /// correction, crop aur enhancement. ML Kit Document Scanner ye sab
  /// on-device karta hai (tasveer seedhi, saaf, table par cropped).
  /// Phir har page: rasterize → OCR → column parser (table rows/columns).
  Future<void> _scanDocument() async {
    DocumentScanner? scanner;
    try {
      scanner = DocumentScanner(
        options: DocumentScannerOptions(
          documentFormats: const {DocumentFormat.jpeg},
          pageLimit: 20,
          mode: ScannerMode.full,
          isGalleryImport: true,
        ),
      );
      final result = await scanner.scanDocument();
      final images = result.images ?? [];
      if (images.isEmpty) return; // user ne cancel kiya
      _clearNotice();
      if (!mounted) return;
      setState(() {
        _busy = true;
        _status = '${images.length} page(s) scan ho gaye — parh rahe hain…';
      });
      await _processImages(images);
    } catch (e) {
      // Scanner na chale (purana phone / Play Services nahi) → purana camera.
      debugPrint('QistBook: document scanner fail, camera fallback: $e');
      ErrorLog.log('Import document scanner', e);
      try {
        await _scanPageLegacy();
      } catch (e2) {
        // Camera bhi na chale (permission denied waghera) → kabhi silent nahi.
        _fail('Scan nahi ho saka: $e2\n'
            'Camera ki permission check karen (Settings → Apps → QistBook → Permissions).',
            error: e2, screen: 'Import scan');
      }
    } finally {
      try {
        await scanner?.close();
      } catch (_) {}
    }
  }

  /// Image preprocessing (pipeline step): gallery/photo ko OCR ke liye
  /// tayaar karo — grayscale + contrast normalize (saaye/kam roshni me
  /// behtar parhai). Scanner ki tasveeren pehle se saaf hoti hain.
  Future<String> _enhanceImage(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return path;
      var out = img.grayscale(decoded);
      out = img.normalize(out, min: 0, max: 255);
      final tmp = Directory.systemTemp;
      final f = File(
          '${tmp.path}/kistbook_enh_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await f.writeAsBytes(img.encodeJpg(out, quality: 95));
      return f.path;
    } catch (e) {
      debugPrint('QistBook: enhance fail, original: $e');
      return path;
    }
  }

  /// Method 1 (purana fallback): sadah camera photo.
  /// NOTE: exceptions yahan se BAHAR nikalne do taake _scanDocument
  /// unhe pakar kar user ko wazeh message dikhaye (silent kabhi nahi).
  Future<void> _scanPageLegacy() async {
    final x = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 95);
    if (x != null) {
      _clearNotice();
      if (!mounted) return;
      setState(() {
        _busy = true;
        _status = 'Photo saaf kar rahe hain…';
      });
      final enhanced = await _enhanceImage(x.path);
      if (!mounted) return;
      setState(() => _status = 'Parh rahe hain…');
      await _processImages([enhanced]);
    }
  }

  /// Method 1: scan pages with the camera, one after another.
  Future<void> _scanPage() async {
    try {
      // Naya pipeline: document scanner (auto-detect + seedha + crop).
      await _scanDocument();
    } catch (e) {
      // Button se nikli hui koi bhi exception silent nahi jayegi.
      _fail('Scan shuru nahi ho saka: $e', error: e, screen: 'Import scan');
    }
  }

  /// Method 2: photos from the gallery (multi-select) — preprocessing ke sath.
  Future<void> _pickGallery() async {
    try {
      final xs = await _picker.pickMultiImage(imageQuality: 95);
      if (xs.isEmpty) return; // user ne cancel kiya — yehi waahid silent return
      _clearNotice();
      setState(() {
        _busy = true;
        _status = 'Photos saaf kar rahe hain…';
      });
      final enhanced = <String>[];
      for (var i = 0; i < xs.length; i++) {
        if (mounted) {
          setState(() => _status = 'Photo ${i + 1}/${xs.length} saaf ho rahi hai…');
        }
        enhanced.add(await _enhanceImage(xs[i].path));
      }
      if (!mounted) return;
      await _processImages(enhanced);
    } catch (e) {
      _fail('Gallery se photos nahi aa sakin: $e\n'
          'Photos ki permission check karen (Settings → Apps → QistBook → Permissions).',
          error: e, screen: 'Import gallery');
    }
  }

  /// Method 3: PDF file with multiple customers.
  ///
  /// HARDENED (v1.0.35): picked PDF ko HAMESHA app temp file me copy karo —
  /// content:// ya provider path kabhi seedha PdfDocument.openFile ko nahi
  /// dena. Temp file ka size verify karo. Koi bhi failure → persistent
  /// _notice banner (silent wapas kabhi nahi). Sirf user-cancel silent hai.
  Future<void> _pickPdf() async {
    FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true, // kuch phones path nahi dete — bytes se kaam chalao
      );
    } catch (e) {
      _fail('PDF chunne me masla: $e\n'
          'Files app me PDF tak rasai check karen, ya gallery se photo len.',
          error: e, screen: 'Import PDF pick');
      return;
    }
    if (res == null || res.files.isEmpty) return; // user ne cancel kiya
    final picked = res.files.single;

    // STEP 1 — PDF ko hamesha app temp me materialize karo.
    late final String pdfPath;
    try {
      final tmpDir = await getTemporaryDirectory();
      final target = File(
          '${tmpDir.path}/qb_import_${DateTime.now().millisecondsSinceEpoch}.pdf');
      if (picked.path != null) {
        // Path mila to bhi copy karo — original content:// ho sakta hai.
        await File(picked.path!).copy(target.path);
      } else if (picked.bytes != null) {
        await target.writeAsBytes(picked.bytes!);
      } else {
        _fail('PDF ka path aur data dono nahi mile.\n'
            'Dobara koshish karo, ya gallery se us PDF ki photo lo.',
            screen: 'Import PDF pick');
        return;
      }
      final size = await target.length();
      if (size <= 0) {
        try {
          await target.delete();
        } catch (_) {}
        _fail('PDF file khaali nikli (0 bytes) — file dobara check karo.',
            screen: 'Import PDF pick');
        return;
      }
      pdfPath = target.path;
    } catch (e) {
      _fail('PDF tayaar nahi ho saki: $e', error: e, screen: 'Import PDF pick');
      return;
    }

    // STEP 2a — TEXT LAYER pehle (v1.0.36): PDF ke andar asal text ho to
    // OCR ki zaroorat hi nahi — na ML Kit model, na page renderer. Ye
    // sab se pakka rasta hai aur phone par fail nahi hota.
    // Text layer na ho ya us se rows na niklen to STEP 2b (render+OCR).
    _clearNotice();
    setState(() {
      _busy = true;
      _status = 'PDF parh rahe hain…';
    });
    try {
      final bytes = await File(pdfPath).readAsBytes();
      final textLines = extractPdfTextLines(bytes);
      final totalChars = textLines.fold<int>(0, (s, l) => s + l.length);
      if (totalChars >= 100) {
        if (mounted) {
          setState(() => _status = 'PDF ka text parh rahe hain…');
        }
        final page = textLines
            .map((l) => OcrLine([OcrWord(l, left: 0, right: 0, top: 0)]))
            .toList();
        await _processOcrPages([page]);
        if (_rows.isNotEmpty || _statements.isNotEmpty) return;
        // Text tha lekin rows nahi nikli — render+OCR ko mauqa do.
        if (mounted) {
          setState(() {
            _notice = '';
            _rawOcr = '';
            _busy = true;
            _status = 'PDF pages bana rahe hain…';
          });
        }
      }
    } catch (e) {
      debugPrint('QistBook: PDF text layer fail, OCR fallback: $e');
      if (mounted) {
        setState(() {
          _busy = true;
          _status = 'PDF pages bana rahe hain…';
        });
      }
    }

    // STEP 2b — render + OCR (photo wali / scanned PDF ke liye).
    try {
      final pages = await _pdfToImagePaths(
        pdfPath,
        (s) {
          if (mounted) setState(() => _status = s);
        },
      ).timeout(
        const Duration(minutes: 3),
        onTimeout: () => throw TimeoutException('PDF render me zyada waqt lag raha hai'),
      );
      if (pages.isEmpty) {
        throw Exception('PDF ke pages render nahi ho sake '
            '(kharaab/scan-image PDF ho sakti hai). Gallery se uski photo lo.');
      }
      await _processImages(pages);
    } catch (e) {
      _fail('PDF parhne me masla: $e', error: e, screen: 'Import PDF process');
    }
  }

  // ------------------------------------------------------------ process

  /// Har page alag try/catch me — ek page fail ho to baqi pages ka
  /// parsed data ZAYA NAHI hota. Failed pages retry/skip dialog me.
  ///
  /// HARDENED (v1.0.35): finally kabhi _notice clear NAHI karta — 0 rows ya
  /// exception par user ko hamesha wazeh paigham milta hai, khaali page kabhi nahi.
  /// Tasveeron ko OCR karke pages banao, phir _processOcrPages ko do.
  Future<void> _processImages(List<String> paths) async {
    final pages = <List<OcrLine>>[];
    final failedPages = <int>[];
    setState(() {
      _busy = true;
      _status = '${paths.length} page(s) parh rahe hain…';
    });
    for (var i = 0; i < paths.length; i++) {
      if (mounted) {
        setState(() => _status = 'Page ${i + 1}/${paths.length}…');
      }
      try {
        pages.add(await _ocrImageLines(paths[i]));
      } catch (e) {
        ErrorLog.log('Import OCR page ${i + 1}', e);
        _lastOcrError = '$e';
        failedPages.add(i);
      }
    }
    await _processOcrPages(pages,
        failedPages: failedPages, retryPaths: paths);
  }

  /// OCR pages (ya PDF text-layer ki lines) ko parse karke review banao.
  /// failedPages/retryPaths sirf OCR raste se aate hain (retry dialog ko).
  Future<void> _processOcrPages(List<List<OcrLine>> pages,
      {List<int> failedPages = const [], List<String>? retryPaths}) async {
    setState(() {
      _busy = true;
      _staging = false;
      _notice = '';
      _rawOcr = '';
      _rows = [];
      _failed = [];
      _groups = [];
      _pageTotalOk = null;
      _pageTotalDue = 0;
      _parsedTotalDue = 0;
      _statements = [];
      _status = 'Data samajh rahe hain…';
    });
    try {
      if (_docType == DocType.outstanding) {
        // Column-wise parser: header se columns, phir hisab cross-check.
        final report = parseOutstandingReport(pages);
        // Raw OCR text sambhaal lo — 0 rows aye to diagnosis ke liye dikhayenge.
        final raw = pages
            .map((p) => p.map((l) => l.text).join('\n'))
            .join('\n\n----- page -----\n\n');
        setState(() {
          _rows = report.rows;
          _failed = report.failed;
          _groups = report.groups;
          _pageTotalOk =
              report.pageTotalDue > 0 ? report.totalMatches : null;
          _pageTotalDue = report.pageTotalDue;
          _parsedTotalDue = report.parsedTotalDue;
          if (_rows.isEmpty) {
            _rawOcr = raw.length > 100000 ? raw.substring(0, 100000) : raw;
            _noticeIsError = true;
            final totalPages = pages.length + failedPages.length;
            final errLower = _lastOcrError.toLowerCase();
            final ocrErr = _lastOcrError.isEmpty
                ? ''
                : '\nParhai ki ghalti: $_lastOcrError'
                    '${errLower.contains('model') || errLower.contains('download') || errLower.contains('waiting') ? '\nInternet/Wi-Fi on karke 1-2 minute ruko — phone parhai wala model pehli dafa download karta hai, phir dobara try karo.' : ''}';
            _notice = failedPages.isNotEmpty
                ? '${failedPages.length}/$totalPages page(s) parhe hi nahi ja sake, '
                  'aur baqiyon se koi row nahi nikli.$ocrErr\n'
                  'Photo saaf/seedhi lo, roshni achi rakho, ya "Parha hua text dekho" '
                  'me dekho ke OCR ne kya parha.'
                : 'Koi row parhi nahi ja saki (${pages.length} page(s) parhe gaye).\n'
                  'Ho sakta hai photo dhundli/teri ho ya ye report ka format na ho.\n'
                  '"Parha hua text dekho" me dekho ke OCR ne asal me kya parha tha.';
          } else {
            _notice = '';
          }
        });
        if (failedPages.isNotEmpty && retryPaths != null && mounted) {
          await _failedPagesDialog(failedPages, retryPaths);
        }
      } else {
        final drafts = <_StatementDraft>[];
        for (var i = 0; i < pages.length; i++) {
          final text = pages[i].map((l) => l.text).join('\n');
          final tmp = parseStatementPage(text);
          drafts.add(_StatementDraft(
              customer: tmp, rawText: text, source: 'page ${i + 1}'));
        }
        setState(() {
          _statements = drafts;
          if (_statements.isEmpty) {
            _rawOcr = drafts.isEmpty
                ? ''
                : drafts.map((d) => d.rawText).join('\n\n----- page -----\n\n');
            _noticeIsError = true;
            _notice = 'Statement se koi data nahi nikla (${pages.length} page(s)).\n'
                'Ek customer ka poora hisaab wala page saaf photo me do.';
          } else {
            _notice = '';
          }
        });
        if (failedPages.isNotEmpty && retryPaths != null && mounted) {
          await _failedPagesDialog(failedPages, retryPaths);
        }
      }
    } catch (e) {
      ErrorLog.log('Import process', e);
      if (mounted) {
        setState(() {
          _noticeIsError = true;
          _notice = 'Import me masla aaya: $e\n'
              'Dobara koshish karo — masla barqarar rahe to Troubleshooting me Error Log dekho.';
        });
      }
    } finally {
      // NOTE: _notice yahan clear NAHI hota — user ko natija lazmi nazar aye.
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
          _stagedPaths.clear();
        });
      }
    }
  }

  /// Failed pages: retry (sirf fail walay) ya skip (kamyaab data rakho).
  Future<void> _failedPagesDialog(
      List<int> failedPages, List<String> paths) async {
    final retry = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kuch pages nahi parhe gaye'),
        content: Text(
          '${failedPages.length} page(s) parhne me masla aaya (page ${failedPages.map((i) => i + 1).join(', ')}). Baqi pages ka data MEHFOOZ hai.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Skip karo')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Dobara try karo')),
        ],
      ),
    );
    if (retry == true && mounted) {
      final retryPaths =
          failedPages.map((i) => paths[i]).toList();
      await _processImages(retryPaths);
    }
  }

  // ------------------------------------------------------------ save

  Future<void> _saveOutstanding() async {
    final store = context.read<CustomerStore>();
    try {
    var updated = 0, created = 0;
    for (final r in _rows) {
      final res = await store.applyOutstandingRow(r);
      if (res == 'updated') {
        updated++;
      } else {
        created++;
      }
    }
    // Jo naam nayi list me nahi — unki qist poori → cleared (toggle se).
    var cleared = 0;
    if (_markCleared) {
      cleared = await store.markMissingAsCleared(
          _rows.map((r) => r.accountNo).toSet());
    }
    final rowCount = _rows.length;
    final failedCount = _failed.length;
    await store.logImport({
      'type': 'outstanding',
      'rows': rowCount,
      'updated': updated,
      'created': created,
      'cleared': cleared,
      'failed': failedCount,
    });
    store.markUpdatedNow();
    if (!mounted) return;
    setState(() {
      _rows = [];
      _failed = [];
      _groups = [];
      _pageTotalOk = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Ho gaya: $updated update, $created naye, $cleared clear.')));
    } catch (e) {
      ErrorLog.log('Import save', e);
      if (mounted) {
        await showFriendlyError(
            context, 'Data save nahi ho saka: $e',
            screen: 'Import save',
            onRetry: () => _saveOutstanding());
      }
    }
  }

  Future<void> _saveStatements() async {
    final store = context.read<CustomerStore>();
    try {
    for (final d in _statements) {
      final existing =
          store.findByAccountNo(d.customer.accountNo);
      final merged = parseStatementPage(d.rawText,
          existing: existing ?? d.customer);
      await store.saveCustomer(merged);
    }
    final count = _statements.length;
    await store.logImport({'type': 'statement', 'pages': count});
    store.markUpdatedNow();
    if (!mounted) return;
    setState(() => _statements = []);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Statements save ho gayin.')));
    } catch (e) {
      ErrorLog.log('Import save', e);
      if (mounted) {
        await showFriendlyError(
            context, 'Data save nahi ho saka: $e',
            screen: 'Import save',
            onRetry: () => _saveStatements());
      }
    }
  }

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import')),
      body: _busy
          ? Center(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(_status),
              ],
            ))
          // Na parhi gayi lines hon to review lazmi dikhao — warna user
          // andha rahega ke "kuch to" parha gaya tha (0 rows + failed lines
          // wala case pehle khaali page par wapas jata tha).
          : _rows.isNotEmpty || _statements.isNotEmpty || _failed.isNotEmpty
              ? _review()
              : _staging
                  ? _stagingUi()
                  : _pickerUi(),
    );
  }

  Widget _sectionTitle(String t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }

  /// OCR ne asal me kya parha — diagnosis dialog (copy bhi ho sakta hai).
  Future<void> _showRawOcrDialog() async {
    if (!mounted || _rawOcr.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('OCR ne ye parha'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(_rawOcr,
                style: const TextStyle(fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _rawOcr));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Text copy ho gaya.')));
            },
            child: const Text('Copy karo'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Band karo'),
          ),
        ],
      ),
    );
  }

  /// Persistent notice banner — _processImages ke baad ka natija ya koi
  /// failure. Ye kabhi khud-ba-khud ghayab nahi hota.
  Widget _noticeBanner() {
    if (_notice.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _noticeIsError ? Colors.red.shade50 : Colors.green.shade50,
        border: Border.all(
            color: _noticeIsError ? Colors.red.shade300 : Colors.green.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                  _noticeIsError ? Icons.error_outline : Icons.check_circle,
                  color: _noticeIsError ? Colors.red : Colors.green),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(_notice,
                      style: const TextStyle(fontSize: 14))),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _clearNotice,
                tooltip: 'Hatao',
              ),
            ],
          ),
          if (_rawOcr.isNotEmpty) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.text_snippet, size: 18),
              label: const Text('Parha hua text dekho'),
              onPressed: _showRawOcrDialog,
            ),
          ],
        ],
      ),
    );
  }

  /// Step 1 + 2: pehle konsi file, phir kis tareeqe se deni hai.
  Widget _pickerUi() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _noticeBanner(),
        _sectionTitle('1. Konsi file hai?'),
        _docCard(
          doc: DocType.outstanding,
          icon: Icons.list_alt,
          title: 'Outstanding Report',
          subtitle: 'Maheene wali list — har customer ek line me',
        ),
        const SizedBox(height: 8),
        _docCard(
          doc: DocType.statement,
          icon: Icons.person,
          title: 'Customer Statement',
          subtitle: 'Ek customer ka poora hisaab (ek page)',
        ),
        const SizedBox(height: 20),
        _sectionTitle('2. Kis tarah dena hai?'),
        _methodButton(
          icon: Icons.picture_as_pdf,
          title: 'PDF file',
          subtitle: 'Multiple customers wali PDF upload karen',
          onPressed: _pickPdf,
        ),
        const SizedBox(height: 8),
        _methodButton(
          icon: Icons.document_scanner,
          title: 'Document scan karo',
          subtitle: 'Auto-detect + seedha + crop — ek ya zyada pages',
          onPressed: _scanPage,
        ),
        const SizedBox(height: 8),
        _methodButton(
          icon: Icons.photo_library,
          title: 'Gallery se photos',
          subtitle: 'Pehle se li hui tasveeren chunen',
          onPressed: _pickGallery,
        ),
        const SizedBox(height: 8),
        _methodButton(
          icon: Icons.edit,
          title: 'Manual likhen (aakhri option)',
          subtitle: 'Scan/PDF na ho to haath se likhen',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) =>
                    ManualEntryScreen(docType: _docType)),
          ),
        ),
        // NOTE (v1.0.35): purana transient red _status hata diya — ab saare
        // natije/nakami _noticeBanner me dikhte hain (persistent).
      ],
    );
  }

  Widget _docCard({
    required DocType doc,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _docType == doc;
    return InkWell(
      onTap: () => setState(() => _docType = doc),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.teal : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          color: selected ? Colors.teal.shade50 : null,
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 36,
                color: selected ? Colors.teal : Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle,
                  color: Colors.teal),
          ],
        ),
      ),
    );
  }

  Widget _methodButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(14),
        alignment: Alignment.centerLeft,
      ),
      onPressed: onPressed,
      child: Row(
        children: [
          Icon(icon, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                Text(subtitle,
                    style: const TextStyle(
                        fontWeight: FontWeight.normal,
                        fontSize: 14)),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 18),
        ],
      ),
    );
  }

  /// Staging: scanned pages ke thumbnails, aur page add karo ya process karo.
  Widget _stagingUi() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: Colors.teal.shade50,
          child: Text(
            '${_stagedPaths.length} page(s) scan ho gaye',
            style: const TextStyle(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8),
            itemCount: _stagedPaths.length,
            itemBuilder: (context, i) => Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child:
                      Image.file(File(_stagedPaths[i]), fit: BoxFit.cover),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    icon: const Icon(Icons.cancel,
                        color: Colors.red),
                    onPressed: () => setState(() {
                      _stagedPaths.removeAt(i);
                      if (_stagedPaths.isEmpty) _staging = false;
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('Aur page scan karo'),
                  onPressed: _scanPage,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text(
                      'Bas, ${_stagedPaths.length} pages parho'),
                  onPressed: _stagedPaths.isEmpty
                      ? null
                      : () =>
                          _processImages(List.of(_stagedPaths)),
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => setState(() {
            _staging = false;
            _stagedPaths.clear();
          }),
          child: const Text('Cancel'),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Na parhi gayi line ko wahin theek karo: manual form khulta hai jis me
  /// parser ka best guess pehle se bhara hota hai. Save par row review list
  /// me ajati hai — asal save Confirm & Save par hota hai.
  Future<void> _editFailedLine(int i) async {
    if (i < 0 || i >= _failed.length) return;
    final line = _failed[i];
    final guess = parseOutstandingRow(line);
    final row = await Navigator.of(context).push<OutstandingRow>(
      MaterialPageRoute(
        builder: (_) => ManualEntryScreen(
          docType: DocType.outstanding,
          prefill: guess,
          returnRow: true,
        ),
      ),
    );
    if (row != null && mounted) {
      setState(() {
        _rows.add(applyMathCheck(row));
        _failed.removeAt(i);
      });
    }
  }

  /// Review: save se pehle user confirm karega. Kuch ghalat ho to hata do.
  Widget _review() {
    if (_docType == DocType.outstanding) {
      final flagged = _rows.where((r) => !r.verified).length;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _noticeBanner(),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.blue.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: Text(
                            '${_rows.length} rows parh li gayin'
                            '${flagged > 0 ? ' • $flagged me hisab ka farq ⚠' : ' • sab ka hisab mil gaya ✓'}'
                            '${_failed.isNotEmpty ? ' • ${_failed.length} check karen' : ''}',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold))),
                    ElevatedButton(
                        // 0 rows par Confirm kabhi enable nahi — warna
                        // markMissingAsCleared({}) saare customers clear kar dega.
                        onPressed: _rows.isEmpty ? null : _saveOutstanding,
                        child: const Text('Confirm & Save')),
                  ],
                ),
                // Group totals ka milan (accuracy check)
                if (_groups.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _groups
                          .map((g) => Chip(
                                avatar: Icon(
                                  g.matches
                                      ? Icons.check_circle
                                      : Icons.warning,
                                  size: 18,
                                  color: g.matches
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                                label: Text(
                                  '${g.officer}: ${g.rowCount} rows'
                                  '${g.hasTotal ? ' • Due ${_rs(g.parsedDue)}/${_rs(g.expectedDue)}' : ''}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                if (_pageTotalOk != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _pageTotalOk!
                          ? 'Neeche wala Total mil gaya ✓ (${_rs(_parsedTotalDue)} / ${_rs(_pageTotalDue)})'
                          : 'Neeche wale Total me farq hai ⚠ (${_rs(_parsedTotalDue)} / ${_rs(_pageTotalDue)})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _pageTotalOk!
                            ? Colors.green.shade800
                            : Colors.orange.shade800,
                      ),
                    ),
                  ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                      'Jo naam is list me nahi — unki qist poori (naam hata do)',
                      style: TextStyle(fontSize: 14)),
                  value: _markCleared,
                  onChanged: (v) =>
                      setState(() => _markCleared = v ?? true),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _rows.length,
              itemBuilder: (context, i) {
                final r = _rows[i];
                return ListTile(
                  dense: true,
                  leading: r.mathChecked
                      ? Icon(
                          r.verified
                              ? Icons.check_circle
                              : Icons.warning,
                          color: r.verified
                              ? Colors.green
                              : Colors.orange,
                          size: 22,
                        )
                      : null,
                  title: Text('${r.name}  •  A/C ${r.accountNo}'),
                  subtitle: Text(
                      '${r.cell}  •  Qist Rs ${_rs(r.installment)}  •  Due Rs ${_rs(r.currentDue)}'
                      '${r.months > 0 ? '  •  ${r.months} mahine baqaya' : ''}'
                      '${r.verified ? '' : '\n${r.flagReason}'}'),
                  isThreeLine: !r.verified,
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () =>
                        setState(() => _rows.removeAt(i)),
                  ),
                );
              },
            ),
          ),
          if (_failed.isNotEmpty)
            ExpansionTile(
              title: Text(
                  'Na parhi gayi lines (${_failed.length}) — theek karen ya khud dekhen'),
              children: _failed
                  .asMap()
                  .entries
                  .map((e) => ListTile(
                        dense: true,
                        title: Text(e.value),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          tooltip: 'Theek karo',
                          onPressed: () => _editFailedLine(e.key),
                        ),
                      ))
                  .toList(),
            ),
        ],
      );
    }
    // statement review
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: _noticeBanner(),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.blue.shade50,
          child: Row(
            children: [
              Expanded(
                  child: Text(
                      '${_statements.length} statement(s) parh li gayin',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold))),
              ElevatedButton(
                  onPressed: _saveStatements,
                  child: const Text('Confirm & Save')),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _statements.length,
            itemBuilder: (context, i) {
              final c = _statements[i].customer;
              return ListTile(
                title:
                    Text('${c.name}  •  A/C ${c.accountNo}'),
                subtitle: Text(
                    '${c.cell}  •  ${c.item} ${c.modelNo}  •  Guarantors: ${c.guarantors.length}'),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () =>
                      setState(() => _statements.removeAt(i)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatementDraft {
  Customer customer;
  final String rawText;
  final String source;
  _StatementDraft(
      {required this.customer,
      required this.rawText,
      required this.source});
}
