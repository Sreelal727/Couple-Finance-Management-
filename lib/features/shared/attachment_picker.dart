import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// A receipt photo or screenshot waiting to be saved with a transaction.
class PendingImage {
  final Uint8List bytes;
  final String mime;
  const PendingImage(this.bytes, {this.mime = 'image/jpeg'});
}

/// Lets the user take a photo of a receipt or pick a screenshot/photo from
/// the gallery. Images are downscaled so sync stays fast.
Future<PendingImage?> pickAttachment(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_rounded),
            title: const Text('Take a photo of the receipt'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_rounded),
            title: const Text('Pick a screenshot or photo'),
            subtitle: const Text('UPI confirmation screenshots work great'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  return pickFromSource(source);
}

Future<PendingImage?> pickFromSource(ImageSource source) async {
  try {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final isPng = file.mimeType == 'image/png' || file.path.toLowerCase().endsWith('.png');
    return PendingImage(bytes, mime: isPng ? 'image/png' : 'image/jpeg');
  } catch (_) {
    return null;
  }
}
