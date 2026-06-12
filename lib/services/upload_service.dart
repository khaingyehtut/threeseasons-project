import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';

class UploadService {
  static final UploadService _instance = UploadService._internal();
  factory UploadService() => _instance;
  UploadService._internal();

  // Single source of truth — change the IP only in AppConstants.socketUrl
  static String get _baseUrl => AppConstants.socketUrl;

  /// Rewrites any stored backend URL to point to the current server.
  /// Handles: relative paths (/productImages/...), IP changes, http/https.
  static String fixUrl(String url) {
    if (url.isEmpty) return url;
    // Relative path from server (e.g. "/productImages/x.jpg") → prepend base
    if (url.startsWith('/')) return '$_baseUrl$url';
    // Rewrite any stored host:port to the current server (handles IP changes)
    return url.replaceFirst(RegExp(r'https?://[^/]+'), _baseUrl);
  }

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.socketUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    ),
  );

  /// Upload a single image — returns the public URL.
  /// [firebaseIdToken] must be a valid Firebase ID token.
  Future<String> uploadImage(File imageFile, String firebaseIdToken) async {
    try {
      final fileName = imageFile.path.split('/').last;
      final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';

      // Map extension → MIME subtype; default to jpeg (covers .heic from iOS camera)
      final mimeSubtype = switch (ext) {
        'png'  => 'png',
        'gif'  => 'gif',
        'webp' => 'webp',
        _      => 'jpeg',
      };

      // Rename files with non-image extensions (e.g. .heic) so the server saves them correctly
      final safeFileName = {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(ext)
          ? fileName
          : '${fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName}.jpg';

      // Backend expects field name 'file'
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          imageFile.path,
          filename: safeFileName,
          // Without an explicit contentType, Dio 5 defaults to application/octet-stream,
          // which is rejected by the backend's multer file-type filter.
          contentType: DioMediaType('image', mimeSubtype),
        ),
      });

      final response = await _dio.post(
        '/api/upload',
        data: formData,
        options: Options(
          headers: {
            'Authorization': 'Bearer $firebaseIdToken',
          },
        ),
      );

      final data = response.data;
      if (data is Map) {
        final url = data['url'] ?? data['imageUrl'] ?? data['path'] ?? '';
        if (url.toString().isNotEmpty) return url.toString();
      }

      throw Exception('Upload succeeded but no URL was returned.');
    } on DioException catch (e) {
      throw Exception(_handleDioError(e));
    }
  }

  /// Upload from in-memory bytes — avoids PathNotFoundException when the
  /// Android cache file picked by image_picker has been evicted before submit.
  Future<String> uploadImageBytes(
    Uint8List bytes,
    String fileName,
    String firebaseIdToken,
  ) async {
    try {
      final ext = fileName.contains('.')
          ? fileName.split('.').last.toLowerCase()
          : '';

      final mimeSubtype = switch (ext) {
        'png'  => 'png',
        'gif'  => 'gif',
        'webp' => 'webp',
        _      => 'jpeg',
      };

      final safeFileName = {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(ext)
          ? fileName
          : '${fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName}.jpg';

      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: safeFileName,
          contentType: DioMediaType('image', mimeSubtype),
        ),
      });

      final response = await _dio.post(
        '/api/upload',
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $firebaseIdToken'},
        ),
      );

      final data = response.data;
      if (data is Map) {
        final url = data['url'] ?? data['imageUrl'] ?? data['path'] ?? '';
        if (url.toString().isNotEmpty) return url.toString();
      }

      throw Exception('Upload succeeded but no URL was returned.');
    } on DioException catch (e) {
      throw Exception(_handleDioError(e));
    }
  }

  /// Extract filename from a productImages URL, or null if not a local server URL.
  String? filenameFromUrl(String url) {
    if (!url.contains('/productImages/')) return null;
    return url.split('/productImages/').last;
  }

  /// Delete an image from the server by its URL.
  /// Silently succeeds if the URL is not a local server image.
  Future<void> deleteImage(String imageUrl, String firebaseIdToken) async {
    final filename = filenameFromUrl(imageUrl);
    if (filename == null || filename.isEmpty) return;
    try {
      await _dio.delete(
        '/api/upload/$filename',
        options: Options(headers: {'Authorization': 'Bearer $firebaseIdToken'}),
      );
    } on DioException catch (e) {
      // Non-fatal — log but don't throw
      debugPrint('[UploadService] deleteImage failed: ${e.message}');
    }
  }

  /// Upload multiple images and return a list of URLs.
  Future<List<String>> uploadImages(
    List<File> imageFiles,
    String firebaseIdToken,
  ) async {
    final urls = <String>[];
    for (final file in imageFiles) {
      final url = await uploadImage(file, firebaseIdToken);
      urls.add(url);
    }
    return urls;
  }

  String _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
        return 'Upload timed out. Check your connection.';
      case DioExceptionType.receiveTimeout:
        return 'Server took too long to respond.';
      case DioExceptionType.sendTimeout:
        return 'Upload timed out while sending file.';
      case DioExceptionType.connectionError:
        return 'Cannot reach upload server at ${AppConstants.socketUrl}. Make sure backend is running on port 5001.';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        final msg  = e.response?.data is Map
            ? (e.response!.data['message'] ?? e.response!.data['error'])
            : null;
        if (msg != null) return msg.toString();
        if (code == 401) return 'Unauthorized. Please log in again.';
        if (code == 413) return 'File is too large.';
        if (code == 415) return 'Unsupported file type.';
        return 'Upload failed (HTTP $code).';
      default:
        return e.message ?? 'An unexpected error occurred during upload.';
    }
  }
}
