import 'dart:convert';
import 'dart:math' show max;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/theme.dart';
import '../../models/product_model.dart';
import '../../services/bt_printer_service.dart';
import 'pos_screen.dart';

class LabelPrintScreen extends StatefulWidget {
  final String? initialBarcode;
  final String? initialTopText;
  const LabelPrintScreen({super.key, this.initialBarcode, this.initialTopText});

  @override
  State<LabelPrintScreen> createState() => _LabelPrintScreenState();
}

class _LabelPrintScreenState extends State<LabelPrintScreen> {
  ProductModel? _product;
  String _line1 = '', _barcodeData = '', _priceText = '';
  double _labelW = 50, _labelH = 30;
  double _line1Fs = 7, _priceFs = 8;
  double _barcodeH = 12.0;
  double _barcodeFontSize = 7.0;
  double _padMm = 3.0;
  int _copies = 1, _dpi = 203;
  bool _printing = false, _loadingProducts = false;
  List<ProductModel> _products = [];
  List<Map<String, dynamic>> _layouts = [];
  String _searchQ = '';

  static const _spLayoutsKey = 'label_layouts_v1';

  final _line1Ctrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadLayouts();
    if (widget.initialBarcode != null) {
      _barcodeData = widget.initialBarcode!;
      _barcodeCtrl.text = widget.initialBarcode!;
    }
    if (widget.initialTopText != null) {
      _line1 = widget.initialTopText!;
      _line1Ctrl.text = widget.initialTopText!;
    }
  }

  @override
  void dispose() {
    _line1Ctrl.dispose();
    _barcodeCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _loadingProducts = true);
    try {
      final snap =
          await FirebaseFirestore.instance.collection('products').get();
      _products = snap.docs
          .map((d) => ProductModel.fromJson({...d.data(), 'id': d.id}))
          .toList();
    } finally {
      if (mounted) setState(() => _loadingProducts = false);
    }
  }

  void _selectProduct(ProductModel p) {
    final fmt = NumberFormat('#,###');
    setState(() {
      _product = p;
      _line1 = p.name;
      _line1Ctrl.text = p.name;
      _barcodeData = p.barcode;
      _barcodeCtrl.text = p.barcode;
      _priceText = '${fmt.format(p.price)} Ks';
      _priceCtrl.text = '${fmt.format(p.price)} Ks';
    });
  }

  Future<Uint8List> _buildLabelPdf() async {
    final doc = pw.Document();
    final format =
        PdfPageFormat(_labelW * PdfPageFormat.mm, _labelH * PdfPageFormat.mm);
    doc.addPage(pw.Page(
      pageFormat: format,
      margin: pw.EdgeInsets.all(_padMm * PdfPageFormat.mm),
      build: (pw.Context ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (_line1.isNotEmpty)
            pw.Text(_line1,
                style: pw.TextStyle(
                    fontSize: _line1Fs, fontWeight: pw.FontWeight.bold),
                maxLines: 2),
          if (_barcodeData.isNotEmpty) ...[
            pw.SizedBox(height: 0.8 * PdfPageFormat.mm),
            pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: _barcodeData,
              height: _barcodeH * PdfPageFormat.mm,
              drawText: false,
            ),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(_barcodeData,
                  style: pw.TextStyle(fontSize: _barcodeFontSize)),
            ),
          ],
          pw.Spacer(),
          if (_priceText.isNotEmpty) ...[
            pw.SizedBox(height: 0.8 * PdfPageFormat.mm),
            pw.Align(
              alignment: pw.Alignment.bottomRight,
              child: pw.Text(_priceText,
                  style: pw.TextStyle(
                      fontSize: _priceFs, fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ],
      ),
    ));
    return doc.save();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(fontSize: 13)),
      backgroundColor:
          error ? const Color(0xFFC0392B) : const Color(0xFF27AE60),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  /// Composites a raster page onto a solid white background.
  /// Without this, transparent PDF pixels have RGB=0,0,0 which the
  /// printer's threshold logic treats as black → all-black output.
  Future<Uint8List> _flattenToWhitePng(PdfRaster rasterImg) async {
    final source = await rasterImg.toImage();
    final w = source.width;
    final h = source.height;

    final recorder = ui.PictureRecorder();
    final canvas =
        ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.drawColor(const Color(0xFFFFFFFF), ui.BlendMode.src);
    canvas.drawImage(source, ui.Offset.zero, ui.Paint());
    source.dispose();

    final picture = recorder.endRecording();
    final flat = await picture.toImage(w, h);
    final data = await flat.toByteData(format: ui.ImageByteFormat.png);
    flat.dispose();
    return data!.buffer.asUint8List();
  }

  Future<void> _print() async {
    final svc = BtPrinterService.to;
    setState(() => _printing = true);
    try {
      final pdfBytes = await _buildLabelPdf();
      final stream =
          Printing.raster(pdfBytes, pages: [0], dpi: _dpi.toDouble());
      final PdfRaster rasterImg = await stream.first;
      final png = await _flattenToWhitePng(rasterImg);
      // Stack all copies into one image so the printer doesn't insert
      // a feed gap between each separate printImage() call.
      final combined = _copies > 1 ? await _stackCopies(png, _copies) : png;
      final ok = await svc.printImage(combined);
      if (ok) {
        _snack('$_copies ကော်ပီ ရိုက်ထုတ်ပြီး');
      } else {
        _snack('ပရင်တာနှင့် မချိတ်ဆက်နိုင်ပါ', error: true);
      }
    } catch (e) {
      _snack(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  /// Stacks [copies] of the same label PNG vertically into one image.
  Future<Uint8List> _stackCopies(Uint8List singlePng, int copies) async {
    final codec = await ui.instantiateImageCodec(singlePng);
    final frame = await codec.getNextFrame();
    final src = frame.image;
    final w = src.width;
    final h = src.height;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, w.toDouble(), (h * copies).toDouble()),
    );
    for (int i = 0; i < copies; i++) {
      canvas.drawImage(src, ui.Offset(0, (h * i).toDouble()), ui.Paint());
    }
    src.dispose();

    final picture = recorder.endRecording();
    final flat = await picture.toImage(w, h * copies);
    final data = await flat.toByteData(format: ui.ImageByteFormat.png);
    flat.dispose();
    return data!.buffer.asUint8List();
  }

  List<ProductModel> get _filtered => _products
      .where((p) =>
          _searchQ.isEmpty ||
          p.name.toLowerCase().contains(_searchQ) ||
          p.barcode.contains(_searchQ))
      .toList();

  static const _presetSizes = [
    (50.0, 30.0),
    (60.0, 40.0),
    (80.0, 50.0),
  ];

  bool get _isCustomSize =>
      !_presetSizes.any((s) => s.$1 == _labelW && s.$2 == _labelH);

  // Max safe padding: never exceed half the shorter label dimension minus 1mm
  double get _maxPad =>
      ((_labelW < _labelH ? _labelW : _labelH) / 2 - 1).clamp(0.0, 10.0);

  void _showCustomSizeDialog() {
    final wCtrl = TextEditingController(text: _labelW.toStringAsFixed(0));
    final hCtrl = TextEditingController(text: _labelH.toStringAsFixed(0));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Custom Label Size',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('mm ဖြင့် ထည့်သွင်းပါ',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: AppColors.textMedium)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: _SizeField(label: 'Width (mm)', ctrl: wCtrl),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('×',
                    style: GoogleFonts.poppins(
                        fontSize: 20,
                        color: AppColors.textMedium,
                        fontWeight: FontWeight.w400)),
              ),
              Expanded(
                child: _SizeField(label: 'Height (mm)', ctrl: hCtrl),
              ),
            ]),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('မလုပ်တော့',
                style: GoogleFonts.poppins(color: AppColors.textMedium)),
          ),
          ElevatedButton(
            onPressed: () {
              final w = double.tryParse(wCtrl.text.trim());
              final h = double.tryParse(hCtrl.text.trim());
              if (w != null && h != null && w > 0 && h > 0) {
                setState(() {
                  _labelW = w;
                  _labelH = h;
                  _padMm = _padMm.clamp(0, _maxPad);
                });
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('အတည်ပြုရန်',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Saved layouts ────────────────────────────────────────────────────────
  Future<void> _loadLayouts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_spLayoutsKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        if (mounted)
          setState(() => _layouts = list.cast<Map<String, dynamic>>());
      } catch (_) {}
    }
  }

  Map<String, dynamic> _layoutSnapshot(String name) => {
        'name': name,
        'labelW': _labelW,
        'labelH': _labelH,
        'line1Fs': _line1Fs,
        'priceFs': _priceFs,
        'barcodeH': _barcodeH,
        'barcodeFontSize': _barcodeFontSize,
        'padMm': _padMm,
        'copies': _copies,
        'dpi': _dpi,
      };

  Future<void> _persistLayouts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_spLayoutsKey, jsonEncode(_layouts));
  }

  Future<void> _saveCurrentLayout(String name) async {
    final layout = _layoutSnapshot(name);
    final idx = _layouts.indexWhere((l) => l['name'] == name);
    setState(() {
      if (idx >= 0)
        _layouts[idx] = layout;
      else
        _layouts.add(layout);
    });
    await _persistLayouts();
    _snack('"$name" သိမ်းပြီး');
  }

  void _applyLayout(Map<String, dynamic> l) {
    final newW = (l['labelW'] as num).toDouble();
    final newH = (l['labelH'] as num).toDouble();
    final maxPad = ((newW < newH ? newW : newH) / 2 - 1).clamp(0.0, 10.0);
    setState(() {
      _labelW = newW;
      _labelH = newH;
      _line1Fs = (l['line1Fs'] as num).toDouble();
      _priceFs = (l['priceFs'] as num).toDouble();
      _barcodeH = (l['barcodeH'] as num).toDouble();
      _barcodeFontSize = (l['barcodeFontSize'] as num).toDouble();
      _padMm = ((l['padMm'] as num).toDouble()).clamp(0, maxPad);
      _copies = (l['copies'] as num).toInt();
      _dpi = (l['dpi'] as num).toInt();
    });
  }

  Future<void> _deleteLayout(int index) async {
    final name = _layouts[index]['name'] as String;
    setState(() => _layouts.removeAt(index));
    await _persistLayouts();
    _snack('"$name" ဖျက်ပြီး');
  }

  void _showSaveLayoutDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Layout သိမ်းမည်',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style:
              GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Layout အမည် (ဥပမာ: Standard 50×40)',
            hintStyle:
                GoogleFonts.poppins(fontSize: 12, color: AppColors.textMedium),
            filled: true,
            fillColor: AppColors.bg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('မလုပ်တော့',
                style: GoogleFonts.poppins(color: AppColors.textMedium)),
          ),
          ElevatedButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx);
                _saveCurrentLayout(name);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('သိမ်းမည်',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Live label canvas (instant, no PDF needed) ──────────────────────────
  Widget _buildLiveCanvas() {
    final isEmpty =
        _line1.isEmpty && _barcodeData.isEmpty && _priceText.isEmpty;
    final aspectW = _labelW / 50.0;
    final aspectH = _labelH / 30.0;

    return Container(
      width: double.infinity,
      height: 170,
      decoration: BoxDecoration(
        color: const Color(0xFF3A3A3A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: isEmpty
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.label_outline_rounded,
                      color: Colors.white.withValues(alpha: 0.35), size: 36),
                  const SizedBox(height: 8),
                  Text('ဘယ်ဘက်မှ ကုန်ပစ္စည်း ရွေးပါ',
                      style: GoogleFonts.poppins(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 12)),
                ],
              )
            : Container(
                width: 220 * aspectW,
                height: 132 * aspectH,
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 14)
                  ],
                ),
                padding: EdgeInsets.all(_padMm * 4.4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_line1.isNotEmpty)
                      Text(_line1,
                          style: TextStyle(
                              fontSize: _line1Fs * 1.55 * aspectW,
                              fontWeight: FontWeight.w700,
                              color: Colors.black),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    if (_barcodeData.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      SizedBox(
                        height: _barcodeH * 4.4,
                        child: CustomPaint(
                          size: const Size(double.infinity, double.infinity),
                          painter: _BarcodePainter(_barcodeData),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(_barcodeData,
                            style: TextStyle(
                                fontSize: _barcodeFontSize * 1.55 * aspectW,
                                color: Colors.black87),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ] else
                      const Spacer(),
                    if (_priceText.isNotEmpty)
                      Align(
                        alignment: Alignment.bottomRight,
                        child: Text(_priceText,
                            style: TextStyle(
                                fontSize: _priceFs * 1.55 * aspectW,
                                fontWeight: FontWeight.w800,
                                color: Colors.black)),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        title: Text('Label ရိုက်ရန်',
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            tooltip: 'Layout သိမ်းမည်',
            icon: const Icon(Icons.bookmark_add_rounded),
            color: AppColors.textPrimary,
            onPressed: _showSaveLayoutDialog,
          ),
          Obx(() {
            final svc = BtPrinterService.to;
            final connected = svc.isConnected.value;
            final color = connected ? Colors.green : Colors.red;
            final row = Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.print_rounded, color: color, size: 18),
              const SizedBox(width: 4),
              Text(
                connected
                    ? (svc.connectedDevice.value?.name ?? 'Connected')
                    : 'မချိတ်ရသေးဘူး',
                style: GoogleFonts.poppins(fontSize: 11, color: color),
              ),
              if (!connected) ...[
                const SizedBox(width: 4),
                Icon(Icons.settings_rounded, color: color, size: 14),
              ],
            ]);
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: connected
                  ? row
                  : GestureDetector(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const HardwarePage())),
                      child: row,
                    ),
            );
          }),
        ],
      ),
      body: Row(
        children: [
          // ── Left: product list ───────────────────────────────────────────
          Container(
            width: 165,
            color: AppColors.card,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQ = v.toLowerCase()),
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'ထုတ်ကုန် ရှာ...',
                    hintStyle: GoogleFonts.poppins(
                        fontSize: 11, color: AppColors.textMedium),
                    prefixIcon: const Icon(Icons.search, size: 16),
                    filled: true,
                    fillColor: AppColors.bg,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none),
                  ),
                ),
              ),
              Expanded(
                child: _loadingProducts
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (ctx, i) {
                          final p = _filtered[i];
                          final sel = _product?.id == p.id;
                          return GestureDetector(
                            onTap: () => _selectProduct(p),
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: sel
                                    ? AppColors.primary.withValues(alpha: 0.15)
                                    : AppColors.bg,
                                borderRadius: BorderRadius.circular(10),
                                border: sel
                                    ? Border.all(
                                        color: AppColors.primary, width: 1.5)
                                    : null,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name,
                                      style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          color: AppColors.textPrimary,
                                          fontWeight: sel
                                              ? FontWeight.w700
                                              : FontWeight.w500),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 2),
                                  Text(
                                      '${NumberFormat('#,###').format(p.price)} Ks',
                                      style: GoogleFonts.poppins(
                                          fontSize: 10,
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600)),
                                  if (p.barcode.isNotEmpty)
                                    Text(p.barcode,
                                        style: GoogleFonts.poppins(
                                            fontSize: 9,
                                            color: AppColors.textMedium),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),
          // ── Right: live canvas + editor ──────────────────────────────────
          Expanded(
            child: Column(children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Live canvas — updates instantly on every keystroke
                      _buildLiveCanvas(),
                      const SizedBox(height: 12),
                      // Saved layouts
                      if (_layouts.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(children: [
                          Text('Layouts:',
                              style: GoogleFonts.poppins(
                                  color: AppColors.textMedium, fontSize: 12)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: _layouts
                                    .asMap()
                                    .entries
                                    .map((e) => GestureDetector(
                                          onTap: () => _applyLayout(e.value),
                                          onLongPress: () =>
                                              _deleteLayout(e.key),
                                          child: Container(
                                            margin:
                                                const EdgeInsets.only(right: 6),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 5),
                                            decoration: BoxDecoration(
                                              color: AppColors.card,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                  color: AppColors.border),
                                            ),
                                            child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.layers_rounded,
                                                      size: 11,
                                                      color:
                                                          AppColors.textMedium),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                      e.value['name'] as String,
                                                      style:
                                                          GoogleFonts.poppins(
                                                              fontSize: 11,
                                                              color: AppColors
                                                                  .textPrimary,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500)),
                                                ]),
                                          ),
                                        ))
                                    .toList(),
                              ),
                            ),
                          ),
                        ]),
                      ],
                      const SizedBox(height: 10),
                      // Size chips
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Label ဆိုဒ်:',
                              style: GoogleFonts.poppins(
                                  color: AppColors.textMedium, fontSize: 12)),
                          ...[
                            ('50×30', 50.0, 30.0),
                            ('60×40', 60.0, 40.0),
                            ('80×50', 80.0, 50.0),
                          ].map((s) {
                            final sel = _labelW == s.$2 && _labelH == s.$3;
                            return GestureDetector(
                              onTap: () => setState(() {
                                _labelW = s.$2;
                                _labelH = s.$3;
                                _padMm = _padMm.clamp(0, _maxPad);
                              }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color:
                                      sel ? AppColors.primary : AppColors.card,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(s.$1,
                                    style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: sel
                                            ? Colors.white
                                            : AppColors.textPrimary,
                                        fontWeight: FontWeight.w600)),
                              ),
                            );
                          }),
                          // Custom size chip
                          GestureDetector(
                            onTap: _showCustomSizeDialog,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _isCustomSize
                                    ? AppColors.primary
                                    : AppColors.card,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _isCustomSize
                                      ? AppColors.primary
                                      : AppColors.border,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.tune_rounded,
                                      size: 13,
                                      color: _isCustomSize
                                          ? Colors.white
                                          : AppColors.textMedium),
                                  const SizedBox(width: 4),
                                  Text(
                                    _isCustomSize
                                        ? '${_labelW.toStringAsFixed(0)}×${_labelH.toStringAsFixed(0)}'
                                        : 'Custom',
                                    style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: _isCustomSize
                                            ? Colors.white
                                            : AppColors.textPrimary,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _FsRow(
                          label: 'Padding:',
                          value: _padMm,
                          unit: 'mm',
                          min: 0,
                          max: _maxPad,
                          onChange: (v) => setState(() => _padMm = v)),
                      const SizedBox(height: 10),
                      _Field(
                          hint: 'အပေါ် စာသား (Top Text)',
                          ctrl: _line1Ctrl,
                          onChanged: (v) => setState(() => _line1 = v)),
                      const SizedBox(height: 4),
                      _FsRow(
                          label: 'Font (အပေါ်):',
                          value: _line1Fs,
                          onChange: (v) => setState(() => _line1Fs = v)),
                      const SizedBox(height: 8),
                      _Field(
                          hint: 'ဘားကုဒ်',
                          ctrl: _barcodeCtrl,
                          onChanged: (v) => setState(() => _barcodeData = v)),
                      const SizedBox(height: 4),
                      _FsRow(
                          label: 'Barcode အမြင့်:',
                          value: _barcodeH,
                          unit: 'mm',
                          min: 4,
                          max: 30,
                          onChange: (v) => setState(() => _barcodeH = v)),
                      const SizedBox(height: 4),
                      _FsRow(
                          label: 'Barcode ဂဏန်း Font:',
                          value: _barcodeFontSize,
                          min: 4,
                          max: 16,
                          onChange: (v) =>
                              setState(() => _barcodeFontSize = v)),
                      const SizedBox(height: 8),
                      _Field(
                          hint: 'အောက် စာသား (Bottom Text)',
                          ctrl: _priceCtrl,
                          onChanged: (v) => setState(() => _priceText = v)),
                      const SizedBox(height: 4),
                      _FsRow(
                          label: 'Font (အောက်):',
                          value: _priceFs,
                          onChange: (v) => setState(() => _priceFs = v)),
                      const SizedBox(height: 8),
                      const SizedBox(height: 12),
                      // Copies + DPI
                      Row(children: [
                        Text('ကော်ပီ:',
                            style: GoogleFonts.poppins(
                                color: AppColors.textMedium, fontSize: 12)),
                        const SizedBox(width: 8),
                        _Counter(
                          value: _copies,
                          onDec: () =>
                              setState(() => _copies = max(1, _copies - 1)),
                          onInc: () => setState(() => _copies++),
                        ),
                        const Spacer(),
                        Text('DPI:',
                            style: GoogleFonts.poppins(
                                color: AppColors.textMedium, fontSize: 12)),
                        const SizedBox(width: 6),
                        ...[203, 300].map((d) {
                          final sel = _dpi == d;
                          return GestureDetector(
                            onTap: () => setState(() => _dpi = d),
                            child: Container(
                              margin: const EdgeInsets.only(left: 5),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: sel ? AppColors.primary : AppColors.card,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('$d',
                                  style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      color: sel
                                          ? Colors.white
                                          : AppColors.textPrimary)),
                            ),
                          );
                        }),
                      ]),
                    ],
                  ),
                ),
              ),
              // Print button
              Container(
                color: AppColors.card,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed:
                        (_line1.isEmpty && _barcodeData.isEmpty) || _printing
                            ? null
                            : _print,
                    icon: _printing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.print_rounded),
                    label: Text(
                        _printing
                            ? 'ရိုက်နေသည်...'
                            : 'Print  ($_copies ကော်ပီ)',
                        style: GoogleFonts.poppins(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00B4D8),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.card,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ── Barcode visual painter (for live preview only, not for scanning) ─────────
class _BarcodePainter extends CustomPainter {
  final String data;
  const _BarcodePainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()..color = Colors.black;
    // Represent each byte as 8 narrow bars with gaps
    const barsPerChar = 9;
    final totalSlots = data.length * barsPerChar + 4.0;
    final slotW = size.width / totalSlots;
    double x = slotW * 2; // left quiet zone
    for (int i = 0; i < data.length; i++) {
      final byte = data.codeUnitAt(i);
      for (int b = 7; b >= 0; b--) {
        if ((byte >> b) & 1 == 1) {
          canvas.drawRect(Rect.fromLTWH(x, 0, slotW * 0.8, size.height), paint);
        }
        x += slotW;
      }
      x += slotW * 0.5;
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter old) => old.data != data;
}

// ── Shared helper widgets ────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final String hint;
  final TextEditingController ctrl;
  final ValueChanged<String> onChanged;
  const _Field(
      {required this.hint, required this.ctrl, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      onChanged: onChanged,
      style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            GoogleFonts.poppins(fontSize: 12, color: AppColors.textMedium),
        filled: true,
        fillColor: AppColors.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  final int value;
  final VoidCallback onDec;
  final VoidCallback onInc;
  const _Counter(
      {required this.value, required this.onDec, required this.onInc});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _btn(icon: Icons.remove, onTap: onDec),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text('$value',
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
      ),
      _btn(icon: Icons.add, onTap: onInc),
    ]);
  }

  Widget _btn({required IconData icon, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
              color: AppColors.card, borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: AppColors.textPrimary),
        ),
      );
}

class _FsRow extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChange;
  final String unit;
  final double min;
  final double max;
  const _FsRow({
    required this.label,
    required this.value,
    required this.onChange,
    this.unit = 'pt',
    this.min = 5,
    this.max = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label,
          style:
              GoogleFonts.poppins(fontSize: 10, color: AppColors.textMedium)),
      const Spacer(),
      GestureDetector(
        onTap: () => onChange((value - 1).clamp(min, max)),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
              color: AppColors.card, borderRadius: BorderRadius.circular(7)),
          child: Icon(Icons.remove_rounded,
              size: 14, color: AppColors.textPrimary),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text('${value.toStringAsFixed(0)}$unit',
            style: GoogleFonts.poppins(
                fontSize: 11,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700)),
      ),
      GestureDetector(
        onTap: () => onChange((value + 1).clamp(min, max)),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
              color: AppColors.card, borderRadius: BorderRadius.circular(7)),
          child:
              Icon(Icons.add_rounded, size: 14, color: AppColors.textPrimary),
        ),
      ),
    ]);
  }
}

class _SizeField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  const _SizeField({required this.label, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.center,
      style: GoogleFonts.poppins(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            GoogleFonts.poppins(fontSize: 11, color: AppColors.textMedium),
        filled: true,
        fillColor: AppColors.bg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none),
      ),
    );
  }
}
