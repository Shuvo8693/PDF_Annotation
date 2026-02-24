import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:file_save_directory/file_save_directory.dart';
import 'package:open_file_android/open_file_android.dart';

class PdfEditorScreen extends StatefulWidget {
  final String pdfPath;
  const PdfEditorScreen({super.key, required this.pdfPath});

  @override
  State<PdfEditorScreen> createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends State<PdfEditorScreen> {
  final PdfViewerController _pdfController = PdfViewerController();

  Uint8List? _pdfBytes;
  bool _isLoading = true;
  bool _isPinMode = false;
  bool _isSaving = false;

  // All placed pins
  final List<_PinData> _pins = [];

  static const List<Color> _pinColors = [
    Color(0xFFFFC107),
    Color(0xFFFF5722),
    Color(0xFF4CAF50),
    Color(0xFF2196F3),
    Color(0xFF9C27B0),
    Color(0xFFF44336),
  ];
  Color _pinColor = const Color(0xFFFF5722);

  final GlobalKey _viewerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadPdfBytes();
  }

  Future<void> _loadPdfBytes() async {
    final bytes = await File(widget.pdfPath).readAsBytes();
    if (mounted) {
      setState(() {
        _pdfBytes = bytes;
        _isLoading = false;
      });
    }
  }

  void _togglePin() {
    setState(() => _isPinMode = !_isPinMode);
    HapticFeedback.lightImpact();
  }

  void _exitPinMode() {
    setState(() => _isPinMode = false);
  }

  // ── Called by SfPdfViewer's onTap — gives us exact PDF page coordinates ───────────
  void _onViewerTap(PdfGestureDetails details) {
    if (!_isPinMode) return;

    // details.pagePosition = tap position in PDF page coordinates ✅
    // details.position     = tap position on screen (for overlay preview)
    // details.pageNumber   = which page was tapped (1-indexed)

    setState(() {
      _pins.add(_PinData(
        page: details.pageNumber,
        pdfX: details.pagePosition.dx,
        pdfY: details.pagePosition.dy,
        screenX: details.position.dx,
        screenY: details.position.dy,
        color: _pinColor,
      ));
    });

    HapticFeedback.mediumImpact();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('📍 Pin placed! Tap Save to embed it.'),
        duration: const Duration(seconds: 1),
        backgroundColor: const Color(0xFF2E8B72),
        behavior: SnackBarBehavior.floating,
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ── Burn all pins into PDF and save to Downloads ──────────────────────────────
  Future<void> _savePdf() async {
    if (_pdfBytes == null) return;
    setState(() => _isSaving = true);

    try {
      final PdfDocument document = PdfDocument(inputBytes: _pdfBytes!);

      for (final pin in _pins) {
        final PdfPage page = document.pages[pin.page - 1];

        // ✅ Use PDF coordinates directly — no conversion needed
        _drawPinOnPage(
          page: page,
          x: pin.pdfX,
          y: pin.pdfY,
          color: pin.color,
        );
      }

      final List<int> savedBytes = document.saveSync();
      document.dispose();
      final Uint8List annotatedBytes = Uint8List.fromList(savedBytes);

      final baseName =
      widget.pdfPath.split('/').last.replaceAll('.pdf', '');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${baseName}_pinned_$ts.pdf';

      // Save to public Downloads folder
      await FileSaveDirectory.instance.saveFile(
        fileName: fileName,
        fileBytes: annotatedBytes,
        location: SaveLocation.downloads,
        openAfterSave: false,
      );

      // Private copy for reliable open
      final dir = await getApplicationDocumentsDirectory();
      final privatePath = '${dir.path}/$fileName';
      await File(privatePath).writeAsBytes(annotatedBytes);

      // Update state — pins are now burned in, clear them
      setState(() {
        _pdfBytes = annotatedBytes;
        _pins.clear();
        _isSaving = false;
        _isPinMode = false;
      });

      if (!mounted) return;

      // Open file immediately
      await OpenFileAndroid().open(privatePath);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF2E8B72),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r)),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Saved to Downloads!',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.sp)),
                    Text(fileName,
                        style: TextStyle(fontSize: 10.sp),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Save failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ── Draw 📍 pin shape directly on PDF page ───────────────────────────────────
  void _drawPinOnPage({
    required PdfPage page,
    required double x,
    required double y,
    required Color color,
    double size = 30,
  }) {
    final PdfGraphics g = page.graphics;

    final PdfColor pinColor =
    PdfColor(color.red, color.green, color.blue);
    final PdfColor darkColor = PdfColor(
      (color.red * 0.7).toInt(),
      (color.green * 0.7).toInt(),
      (color.blue * 0.7).toInt(),
    );
    final PdfColor whiteColor = PdfColor(255, 255, 255);

    final double headRadius = size * 0.38;
    final double headCX = x;
    final double headCY = y - size * 0.55;

    // Pin circle head
    g.drawEllipse(
      Rect.fromCircle(
          center: Offset(headCX, headCY), radius: headRadius),
      pen: PdfPen(darkColor, width: 1.2),
      brush: PdfSolidBrush(pinColor),
    );

    // White inner highlight dot
    g.drawEllipse(
      Rect.fromCircle(
          center: Offset(
              headCX - headRadius * 0.25, headCY - headRadius * 0.25),
          radius: headRadius * 0.3),
      brush: PdfSolidBrush(whiteColor),
    );

    // Pin tail triangle pointing down to tap point
    final PdfPath tail = PdfPath();
    tail.addPolygon([
      Offset(headCX - headRadius * 0.55, headCY + headRadius * 0.35),
      Offset(headCX + headRadius * 0.55, headCY + headRadius * 0.35),
      Offset(x, y),
    ]);
    g.drawPath(
      tail,
      pen: PdfPen(darkColor, width: 1.2),
      brush: PdfSolidBrush(pinColor),
    );

    // Dark tip dot at the very point
    g.drawEllipse(
      Rect.fromCircle(center: Offset(x, y), radius: 2),
      brush: PdfSolidBrush(darkColor),
    );
  }

  // ── Color picker bottom sheet ─────────────────────────────────────────────────
  void _showColorPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 20.h),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pin Color',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700)),
            SizedBox(height: 16.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _pinColors.map((c) {
                final selected = c == _pinColor;
                return GestureDetector(
                  onTap: () {
                    setState(() => _pinColor = c);
                    HapticFeedback.selectionClick();
                    Navigator.pop(ctx);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 44.w,
                    height: 44.h,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                      boxShadow: [
                        BoxShadow(
                            color: c.withOpacity(0.5),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: selected
                        ? const Icon(Icons.check,
                        color: Colors.white, size: 20)
                        : null,
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }

  // ── Saved files list ─────────────────────────────────────────────────────────
  Future<void> _showSavedFilesList() async {
    final dir = await getApplicationDocumentsDirectory();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pdf'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
            BorderRadius.vertical(top: Radius.circular(20.r)),
          ),
          child: Column(
            children: [
              SizedBox(height: 12.h),
              Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              SizedBox(height: 16.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Row(
                  children: [
                    Icon(Icons.folder_open,
                        color: const Color(0xFF2E8B72), size: 22.sp),
                    SizedBox(width: 8.w),
                    Text('Saved PDFs',
                        style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(
                        '${files.length} file${files.length == 1 ? '' : 's'}',
                        style: TextStyle(
                            fontSize: 12.sp,
                            color: Colors.grey.shade500)),
                  ],
                ),
              ),
              SizedBox(height: 12.h),
              Expanded(
                child: files.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.picture_as_pdf_outlined,
                          size: 48.sp,
                          color: Colors.grey.shade300),
                      SizedBox(height: 8.h),
                      Text('No saved files yet.',
                          style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 14.sp)),
                    ],
                  ),
                )
                    : ListView.separated(
                  controller: scrollCtrl,
                  padding: EdgeInsets.symmetric(
                      horizontal: 16.w, vertical: 4.h),
                  itemCount: files.length,
                  separatorBuilder: (_, __) =>
                      SizedBox(height: 8.h),
                  itemBuilder: (_, i) {
                    final file = files[i];
                    final name = file.path.split('/').last;
                    final modified = file.lastModifiedSync();
                    final sizeKb = (file.lengthSync() / 1024).toStringAsFixed(1);
                    return Container(
                      padding: EdgeInsets.all(14.w),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius:
                        BorderRadius.circular(12.r),
                        border: Border.all(
                            color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42.w,
                            height: 42.h,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5F1),
                              borderRadius:
                              BorderRadius.circular(10.r),
                            ),
                            child: Icon(Icons.picture_as_pdf,
                                color: const Color(0xFF2E8B72),
                                size: 22.sp),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: TextStyle(
                                        fontSize: 12.sp,
                                        fontWeight:
                                        FontWeight.w600),
                                    maxLines: 1,
                                    overflow:
                                    TextOverflow.ellipsis),
                                SizedBox(height: 3.h),
                                Text(
                                  '${modified.day}/${modified.month}/${modified.year}  •  $sizeKb KB',
                                  style: TextStyle(
                                      fontSize: 10.sp,
                                      color:
                                      Colors.grey.shade500),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.open_in_new,
                                color: const Color(0xFF2E8B72),
                                size: 20.sp),
                            onPressed: () {
                              Navigator.pop(ctx);
                              OpenFileAndroid().open(file.path);
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                color: Colors.redAccent,
                                size: 20.sp),
                            onPressed: () async {
                              await file.delete();
                              Navigator.pop(ctx);
                              _showSavedFilesList();
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: 16.h),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A2A3A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.pdfPath.split('/').last,
              style: TextStyle(
                  fontSize: 13.sp, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            if (_isPinMode)
              Text(
                '📍 Tap on the PDF to place a pin',
                style: TextStyle(
                    fontSize: 10.sp, color: Colors.yellowAccent),
              ),
          ],
        ),
        actions: [
          // Pin count badge
          if (_pins.isNotEmpty)
            Center(
              child: Container(
                margin: EdgeInsets.only(right: 4.w),
                padding: EdgeInsets.symmetric(
                    horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: _pinColor,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  '${_pins.length} pin${_pins.length > 1 ? 's' : ''}',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Saved files',
            icon: const Icon(Icons.folder_open),
            onPressed: _showSavedFilesList,
          ),
          // Undo last pin
          if (_pins.isNotEmpty)
            IconButton(
              tooltip: 'Remove last pin',
              icon: const Icon(Icons.undo),
              onPressed: () => setState(() => _pins.removeLast()),
            ),
          _isSaving
              ? Padding(
            padding: EdgeInsets.symmetric(horizontal: 14.w),
            child: SizedBox(
                width: 20.w,
                height: 20.h,
                child: const CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2)),
          )
              : IconButton(
            tooltip: 'Save PDF',
            icon: const Icon(Icons.save_alt),
            onPressed: _pdfBytes != null ? _savePdf : null,
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── PDF Viewer ──────────────────────────────────────────────────
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF2E8B72)),
            )
          else
            SfPdfViewer.memory(
              key: _viewerKey,
              _pdfBytes!,
              controller: _pdfController,
              // ✅ Use SfPdfViewer's own onTap — not GestureDetector
              onTap: _onViewerTap,
            ),

          // ── Flutter pin overlays for live preview before saving ─────────
          if (!_isLoading)
            ..._pins.map(
                  (pin) => Positioned(
                left: pin.screenX - 14,
                top: pin.screenY - 32,
                child: IgnorePointer(
                  child: Icon(
                    Icons.location_on,
                    color: pin.color,
                    size: 32,
                    shadows: const [
                      Shadow(
                          color: Colors.black45,
                          blurRadius: 4,
                          offset: Offset(1, 2))
                    ],
                  ),
                ),
              ),
            ),

          // ── Toolbar ─────────────────────────────────────────────────────
          if (!_isLoading)
            Positioned(
              bottom: 24.h,
              left: 24.w,
              right: 24.w,
              child: SafeArea(child: _buildToolbar()),
            ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 20,
              offset: const Offset(0, 6))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Pin toggle button
          Expanded(
            child: GestureDetector(
              onTap: _togglePin,
              onLongPress: _showColorPicker,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(
                    horizontal: 12.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color: _isPinMode
                      ? _pinColor.withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14.r),
                  border: _isPinMode
                      ? Border.all(color: _pinColor, width: 1.5)
                      : Border.all(color: Colors.transparent),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_on,
                      color: _isPinMode
                          ? _pinColor
                          : Colors.white.withOpacity(0.7),
                      size: 26.sp,
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      _isPinMode ? 'Tap to pin' : 'Pin',
                      style: TextStyle(
                        color: _isPinMode
                            ? _pinColor
                            : Colors.white.withOpacity(0.7),
                        fontSize: 10.sp,
                        fontWeight: _isPinMode
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          _divider(),

          // Color picker button
          Expanded(
            child: GestureDetector(
              onTap: _showColorPicker,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _pinColors.take(3).map((c) {
                      return Container(
                        width: 14.w,
                        height: 14.h,
                        margin:
                        EdgeInsets.symmetric(horizontal: 2.w),
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: c == _pinColor
                              ? Border.all(
                              color: Colors.white, width: 2)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  SizedBox(height: 4.h),
                  Text('Color',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 10.sp)),
                ],
              ),
            ),
          ),

          _divider(),

          // Done / Save button
          Expanded(
            child: GestureDetector(
              onTap: _isPinMode ? _exitPinMode : _savePdf,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isPinMode ? Icons.check_circle : Icons.save_alt,
                    color: _isPinMode
                        ? Colors.greenAccent
                        : Colors.white.withOpacity(0.7),
                    size: 26.sp,
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    _isPinMode ? 'Done' : 'Save',
                    style: TextStyle(
                      color: _isPinMode
                          ? Colors.greenAccent
                          : Colors.white.withOpacity(0.7),
                      fontSize: 10.sp,
                      fontWeight: _isPinMode
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
      width: 1,
      height: 40.h,
      color: Colors.white.withOpacity(0.15));
}

// ── Pin data model ────────────────────────────────────────────────────────────
class _PinData {
  final int page;
  final double pdfX;    // PDF page coordinate (used for burning into PDF)
  final double pdfY;    // PDF page coordinate (used for burning into PDF)
  final double screenX; // Screen coordinate (used for overlay preview)
  final double screenY; // Screen coordinate (used for overlay preview)
  final Color color;

  const _PinData({
    required this.page,
    required this.pdfX,
    required this.pdfY,
    required this.screenX,
    required this.screenY,
    required this.color,
  });
}