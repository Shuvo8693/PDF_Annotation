import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'pdf_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<File> _savedFiles = [];

  @override
  void initState() {
    super.initState();
    _loadSavedFiles();
  }

  Future<void> _loadSavedFiles() async {
    final dir = await getApplicationDocumentsDirectory();
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pdf'))
        .toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    if (mounted) setState(() => _savedFiles = files);
  }

  Future<void> _pickAndOpenPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.single.path == null) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PdfEditorScreen(pdfPath: result.files.single.path!),
      ),
    );
    _loadSavedFiles();
  }

  Future<void> _deleteFile(File file) async {
    await file.delete();
    _loadSavedFiles();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E2E),
        foregroundColor: Colors.white,
        title: Text('PDF Annotator',
            style: TextStyle(
                fontSize: 18.sp, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          // Open PDF button
          Padding(
            padding: EdgeInsets.all(20.w),
            child: GestureDetector(
              onTap: _pickAndOpenPdf,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(20.w),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2E8B72), Color(0xFF1A5C4C)],
                  ),
                  borderRadius: BorderRadius.circular(16.r),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2E8B72).withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 52.w,
                      height: 52.h,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Icon(Icons.upload_file,
                          color: Colors.white, size: 26.sp),
                    ),
                    SizedBox(width: 16.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Open PDF to Annotate',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w700)),
                          SizedBox(height: 4.h),
                          Text(
                            'Draw, pin, highlight, and save',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 12.sp),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios,
                        color: Colors.white.withOpacity(0.7),
                        size: 14.sp),
                  ],
                ),
              ),
            ),
          ),

          // Saved files list
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Saved Files',
                  style: TextStyle(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1E1E2E))),
            ),
          ),
          SizedBox(height: 10.h),
          Expanded(
            child: _savedFiles.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.picture_as_pdf_outlined,
                      size: 56.sp, color: Colors.grey.shade300),
                  SizedBox(height: 12.h),
                  Text('No saved PDFs yet',
                      style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 14.sp)),
                ],
              ),
            )
                : ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              itemCount: _savedFiles.length,
              separatorBuilder: (_, __) => SizedBox(height: 10.h),
              itemBuilder: (_, i) {
                final file = _savedFiles[i];
                final name = file.path.split('/').last;
                final modified = file.lastModifiedSync();
                return _FileTile(
                  name: name,
                  modified: modified,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            PdfEditorScreen(pdfPath: file.path),
                      ),
                    );
                    _loadSavedFiles();
                  },
                  onDelete: () => _deleteFile(file),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  final String name;
  final DateTime modified;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _FileTile(
      {required this.name,
        required this.modified,
        required this.onTap,
        required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42.w,
              height: 42.h,
              decoration: BoxDecoration(
                  color: const Color(0xFFE8F5F1),
                  borderRadius: BorderRadius.circular(10.r)),
              child: Icon(Icons.picture_as_pdf,
                  color: const Color(0xFF2E8B72), size: 22.sp),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          fontSize: 13.sp, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  SizedBox(height: 3.h),
                  Text(
                    '${modified.day}/${modified.month}/${modified.year}  ${modified.hour}:${modified.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                        fontSize: 11.sp, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: Colors.redAccent, size: 20.sp),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}