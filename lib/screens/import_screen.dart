/// Import flow — 3 asaan tareeqe, dono document types ke liye:
///  1. Scan karo (camera) — ek ya zyada pages, ek ke baad ek
///  2. Gallery se photos chuno
///  3. PDF file upload karo (multiple customers)
///
/// Phir: OCR (on-device ML Kit) → parse → REVIEW screen → Confirm & Save.
/// Save karte hi data foran update + cloud sync.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdfx/pdfx.dart';
import 'package:provider/provider.dart';

import '../models/customer.dart';
import '../services/customer_store.dart';
import '../services/error_log.dart';
import '../services/parsers.dart';
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

  Future<List<OcrLine>> _ocrImageLines(String path) async {
    final input = InputImage.fromFilePath(path);
    final recognizer =
        TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(input);
      final lines = <OcrLine>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final words = <OcrWord>[];
          for (final el in line.elements) {
            final b = el.boundingBox;
            if (el.text.trim().isEmpty) continue;
            words.add(OcrWord(el.text,
                left: b.left, right: b.right, top: b.top));
          }
          if (words.isEmpty) continue;
          words.sort((a, b) => a.cx.compareTo(b.cx));
          lines.add(OcrLine(words));
        }
      }
      lines.sort((a, b) =>
          a.words.first.top.compareTo(b.words.first.top));
      return lines;
    } finally {
      await recognizer.close();
    }
  }

  /// Rasterize every PDF page to a temp PNG so OCR can read it.
  Future<List<String>> _pdfToImagePaths(String pdfPath) async {
    final doc = await PdfDocument.openFile(pdfPath);
    final out = <String>[];
    final tmp = Directory.systemTemp;
    for (var i = 1; i <= doc.pagesCount; i++) {
      final page = await doc.getPage(i);
      final img = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: PdfPageImageFormat.png);
      final file = File('${tmp.path}/kistbook_p$i.png');
      await file.writeAsBytes(img!.bytes);
      out.add(file.path);
      await page.close();
    }
    await doc.close();
    return out;
  }

  // ------------------------------------------------------------ input methods

  /// Method 1: scan pages with the camera, one after another.
  Future<void> _scanPage() async {
    final x = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 95);
    if (x != null) {
      setState(() {
        _staging = true;
        _stagedPaths.add(x.path);
      });
    } else if (_stagedPaths.isEmpty) {
      setState(() => _staging = false);
    }
  }

  /// Method 2: photos from the gallery (multi-select).
  Future<void> _pickGallery() async {
    final xs = await _picker.pickMultiImage(imageQuality: 95);
    if (xs.isNotEmpty) _processImages(xs.map((e) => e.path).toList());
  }

  /// Method 3: PDF file with multiple customers.
  Future<void> _pickPdf() async {
    final res = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf']);
    if (res == null || res.files.single.path == null) return;
    setState(() {
      _busy = true;
      _status = 'PDF parh rahe hain…';
    });
    try {
      final pages = await _pdfToImagePaths(res.files.single.path!);
      await _processImages(pages);
    } catch (e) {
      setState(() {
        _busy = false;
        _status = 'PDF error: $e';
      });
    }
  }

  // ------------------------------------------------------------ process

  /// Har page alag try/catch me — ek page fail ho to baqi pages ka
  /// parsed data ZAYA NAHI hota. Failed pages retry/skip dialog me.
  Future<void> _processImages(List<String> paths) async {
    setState(() {
      _busy = true;
      _staging = false;
      _rows = [];
      _failed = [];
      _groups = [];
      _pageTotalOk = null;
      _pageTotalDue = 0;
      _parsedTotalDue = 0;
      _statements = [];
      _status = '${paths.length} page(s) parh rahe hain…';
    });
    try {
      if (_docType == DocType.outstanding) {
        final pages = <List<OcrLine>>[];
        final failedPages = <int>[];
        for (var i = 0; i < paths.length; i++) {
          setState(
              () => _status = 'Page ${i + 1}/${paths.length}…');
          try {
            pages.add(await _ocrImageLines(paths[i]));
          } catch (e) {
            ErrorLog.log('Import OCR page ${i + 1}', e);
            failedPages.add(i);
          }
        }
        setState(() => _status = 'Data samajh rahe hain…');
        // Column-wise parser: header se columns, phir hisab cross-check.
        final report = parseOutstandingReport(pages);
        setState(() {
          _rows = report.rows;
          _failed = report.failed;
          _groups = report.groups;
          _pageTotalOk =
              report.pageTotalDue > 0 ? report.totalMatches : null;
          _pageTotalDue = report.pageTotalDue;
          _parsedTotalDue = report.parsedTotalDue;
        });
        if (failedPages.isNotEmpty && mounted) {
          await _failedPagesDialog(failedPages, paths);
        }
      } else {
        final drafts = <_StatementDraft>[];
        final failedPages = <int>[];
        for (var i = 0; i < paths.length; i++) {
          setState(
              () => _status = 'Page ${i + 1}/${paths.length}…');
          try {
            final lines = await _ocrImageLines(paths[i]);
            final text = lines.map((l) => l.text).join('\n');
            final tmp = parseStatementPage(text);
            drafts.add(_StatementDraft(
                customer: tmp, rawText: text, source: paths[i]));
          } catch (e) {
            ErrorLog.log('Import OCR page ${i + 1}', e);
            failedPages.add(i);
          }
        }
        setState(() => _statements = drafts);
        if (failedPages.isNotEmpty && mounted) {
          await _failedPagesDialog(failedPages, paths);
        }
      }
    } catch (e) {
      ErrorLog.log('Import process', e);
      if (mounted) {
        await showFriendlyError(
            context, 'Import me masla aaya: $e',
            screen: 'Import');
      }
      setState(() => _status = 'Error ho gaya');
    } finally {
      setState(() {
        _busy = false;
        _status = '';
        _stagedPaths.clear();
      });
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
          : _rows.isNotEmpty || _statements.isNotEmpty
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

  /// Step 1 + 2: pehle konsi file, phir kis tareeqe se deni hai.
  Widget _pickerUi() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
          title: 'Scan karo (camera)',
          subtitle: 'Ek ya zyada pages — ek ke baad ek scan karen',
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
        if (_status.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(_status, style: const TextStyle(color: Colors.red)),
        ],
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

  /// Review: save se pehle user confirm karega. Kuch ghalat ho to hata do.
  Widget _review() {
    if (_docType == DocType.outstanding) {
      final flagged = _rows.where((r) => !r.verified).length;
      return Column(
        children: [
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
                        onPressed: _saveOutstanding,
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
                  'Na parhi gayi lines (${_failed.length}) — khud dekhen'),
              children: _failed
                  .map((l) =>
                      ListTile(dense: true, title: Text(l)))
                  .toList(),
            ),
        ],
      );
    }
    // statement review
    return Column(
      children: [
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
