import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';

/// Result of a compression operation.
class CompressionResult {
  CompressionResult({required this.file, required this.originalSize, required this.compressedSize});
  final File file;
  final int originalSize;
  final int compressedSize;

  double get ratio => originalSize > 0 ? compressedSize / originalSize : 1.0;
  double get savedPercent => (1 - ratio) * 100;
}

class MediaCompressor {
  /// Max file sizes after compression
  static const int maxImageSizeBytes = 15 * 1024 * 1024; // 15 MB
  static const int maxVideoSizeBytes = 50 * 1024 * 1024; // 50 MB

  /// Max file sizes BEFORE compression (reject if bigger — compression unlikely to work)
  static const int maxImageInputBytes = 100 * 1024 * 1024; // 100 MB
  static const int maxVideoInputBytes = 200 * 1024 * 1024; // 200 MB

  /// Compress an image to JPEG with good quality. Targets < 15MB.
  static Future<CompressionResult?> compressImage(File file) async {
    final originalSize = await file.length();

    if (originalSize > maxImageInputBytes) return null;

    // If already small enough, skip compression
    if (originalSize < 500 * 1024) {
      return CompressionResult(file: file, originalSize: originalSize, compressedSize: originalSize);
    }

    try {
      final dir = await getTemporaryDirectory();
      final targetPath = '${dir.path}/img_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Progressive quality: try 85, then 75, then 65 if still too big
      int quality = 85;
      XFile? result;

      for (int attempt = 0; attempt < 3; attempt++) {
        result = await FlutterImageCompress.compressAndGetFile(
          file.absolute.path,
          targetPath,
          quality: quality,
          minWidth: 1920,
          minHeight: 1920,
          format: CompressFormat.jpeg,
        );
        if (result == null) break;
        final size = await File(result.path).length();
        if (size <= maxImageSizeBytes) break;
        quality -= 15;
        if (quality < 40) break;
      }

      if (result == null) return null;
      final compressedFile = File(result.path);
      final compressedSize = await compressedFile.length();

      return CompressionResult(file: compressedFile, originalSize: originalSize, compressedSize: compressedSize);
    } catch (e) {
      debugPrint('Image compression error: $e');
      return null;
    }
  }

  /// Compress a video with medium quality preset. Targets < 50MB.
  ///
  /// Note: video_compress always outputs H.264. If the source is already in
  /// H.265 / HEVC (modern iPhones, Pixels), transcoding to H.264 typically
  /// inflates the file because H.264 is ~30-40% less efficient. We mitigate
  /// this with two guards: (a) skip outright for files under 20 MB (well-
  /// encoded 1080p clips usually live there), and (b) compare sizes after
  /// compression and keep whichever is smaller.
  static Future<CompressionResult?> compressVideo(File file) async {
    final originalSize = await file.length();

    if (originalSize > maxVideoInputBytes) return null;

    // Skip threshold raised from 10 MB → 20 MB: a well-encoded 1080p video
    // (modern phone in H.265, ~3-4 Mbps) often sits between 10-20 MB. The
    // package's H.264 transcode would inflate those clips significantly.
    if (originalSize < 20 * 1024 * 1024) {
      return CompressionResult(file: file, originalSize: originalSize, compressedSize: originalSize);
    }

    try {
      final info = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.Res1920x1080Quality,
        frameRate: 30, // cap 60 fps → 30 fps (~30% size cut, no visible loss for salon content)
        deleteOrigin: false,
        includeAudio: true,
      );

      if (info == null || info.file == null) return null;

      final compressedFile = info.file!;
      final compressedSize = await compressedFile.length();

      // Garde-fou: if compression made the file bigger (or barely changed it),
      // keep the original. This happens when the source is in an efficient
      // codec (H.265) and we re-encoded to H.264, or when the original was
      // already optimized. We require a meaningful gain (>5%) to bother.
      if (compressedSize >= originalSize * 0.95) {
        // Drop the useless compressed file from the temp dir
        try {
          await compressedFile.delete();
        } catch (_) {}
        return CompressionResult(
          file: file,
          originalSize: originalSize,
          compressedSize: originalSize,
        );
      }

      return CompressionResult(file: compressedFile, originalSize: originalSize, compressedSize: compressedSize);
    } catch (e) {
      debugPrint('Video compression error: $e');
      return null;
    }
  }

  /// Show an overlay during compression. Returns a function to dismiss it.
  static OverlayEntry showCompressionOverlay(BuildContext context, {required bool isVideo}) {
    final overlay = OverlayEntry(
      builder: (_) => Container(
        color: Colors.black54,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  isVideo ? 'Optimisation de la vidéo...' : 'Optimisation de l\'image...',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Cela peut prendre quelques secondes',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(overlay);
    return overlay;
  }

  /// Show an error dialog for oversized files (either before or after compression).
  static Future<void> showSizeErrorDialog(BuildContext context, {required bool isVideo, required bool afterCompression}) {
    final limit = isVideo ? '50 MB' : '15 MB';
    final mediaLabel = isVideo ? 'vidéo' : 'image';
    return showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 48),
        title: const Text('Fichier trop volumineux'),
        content: Text(
          afterCompression
              ? 'Même après optimisation, la $mediaLabel dépasse la limite de $limit. Choisis un fichier plus petit.'
              : 'La $mediaLabel est trop volumineuse. Choisis un fichier plus petit.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
