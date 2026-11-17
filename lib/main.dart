
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

// حافظه موقت عکس‌ها برای جلوگیری از دریافت تکراری
final Map<String, Future<String?>> _productImageCache = {};

Future<String?> loadProductImage(String productId) {
  return _productImageCache.putIfAbsent(productId, () async {
    final doc = await FirebaseFirestore.instance
        .collection('product_images')
        .doc(productId)
        .get();

    final data = doc.data();
    final image = data?['imageBase64'];

    if (image is String && image.isNotEmpty) {
      return image;
    }

    return null;
  });
}

void clearProductImageCache(String productId) {
  _productImageCache.remove(productId);
}

// نمایش عکس محصول
class ProductImageWidget extends StatelessWidget {
  final String productId;
  final double width;
  final double height;
  final bool showPlaceholder;

  const ProductImageWidget({
    super.key,
    required this.productId,
    this.width = 58,
    this.height = 58,
    this.showPlaceholder = true,
  });

  Widget placeholder() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EEF5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.bed_outlined,
        color: Color(0xFF12345A),
        size: 30,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: loadProductImage(productId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return showPlaceholder
              ? placeholder()
              : const SizedBox.shrink();
        }

        final encoded = snapshot.data;

        if (snapshot.hasError ||
            encoded == null ||
            encoded.isEmpty) {
          return showPlaceholder
              ? placeholder()
              : const SizedBox.shrink();
        }

        try {
          final bytes = base64Decode(encoded);

          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              bytes,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) {
                return showPlaceholder
                    ? placeholder()
                    : const SizedBox.shrink();
              },
            ),
          );
        } catch (_) {
          return showPlaceholder
              ? placeholder()
              : const SizedBox.shrink();
        }
      },
    );
  }
}

// پنجره انتخاب، تغییر و حذف عکس محصول
class ProductImageEditorDialog extends StatefulWidget {
  final String productId;
  final String productName;

  const ProductImageEditorDialog({
    super.key,
    required this.productId,
    required this.productName,
  });

  @override
  State<ProductImageEditorDialog> createState() =>
      _ProductImageEditorDialogState();
}

class _ProductImageEditorDialogState
    extends State<ProductImageEditorDialog> {
  Uint8List? imageBytes;

  bool loading = true;
  bool saving = false;
  bool changed = false;

  @override
  void initState() {
    super.initState();
    loadExistingImage();
  }

  Future<void> loadExistingImage() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('product_images')
          .doc(widget.productId)
          .get();

      final encoded = doc.data()?['imageBase64'];

      if (encoded is String && encoded.isNotEmpty) {
        imageBytes = base64Decode(encoded);
      }
    } catch (_) {
      // در صورت نبود عکس، تصویر پیش‌فرض نمایش داده می‌شود.
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  void showMessage(String value) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  Future<void> pickImage() async {
    try {
      final picker = ImagePicker();

      final XFile? selected = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 900,
        maxHeight: 900,
        imageQuality: 50,
      );

      if (selected == null) return;

      final bytes = await selected.readAsBytes();

      // حداکثر حجم عکس خام: 500 کیلوبایت
      if (bytes.length > 500 * 1024) {
        showMessage(
          'حجم عکس هنوز زیاد است. لطفاً عکس کم‌حجم‌تری انتخاب کنید.',
        );
        return;
      }

      if (!mounted) return;

      setState(() {
        imageBytes = bytes;
        changed = true;
      });
    } catch (e) {
      showMessage('انتخاب عکس با خطا روبه‌رو شد: $e');
    }
  }

  void removeImage() {
    setState(() {
      imageBytes = null;
      changed = true;
    });
  }

  Future<void> saveImage() async {
    if (saving) return;

    setState(() => saving = true);

    try {
      final ref = FirebaseFirestore.instance
          .collection('product_images')
          .doc(widget.productId);

      if (imageBytes == null) {
        await ref.delete();
      } else {
        await ref.set({
          'imageBase64': base64Encode(imageBytes!),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      clearProductImageCache(widget.productId);

      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);

      Navigator.pop(context);

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            imageBytes == null
                ? 'عکس محصول حذف شد.'
                : 'عکس محصول با موفقیت ذخیره شد.',
          ),
        ),
      );
    } catch (e) {
      showMessage('ذخیره عکس با خطا روبه‌رو شد: $e');
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'عکس محصول\n${widget.productName}',
        style: const TextStyle(
          color: Color(0xFF12345A),
          fontWeight: FontWeight.bold,
          fontSize: 17,
        ),
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 250,
              height: 190,
              decoration: BoxDecoration(
                color: const Color(0xFFE8EEF5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: loading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : imageBytes == null
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 55,
                              color: Color(0xFF12345A),
                            ),
                            SizedBox(height: 8),
                            Text('هنوز عکسی انتخاب نشده است'),
                          ],
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            imageBytes!,
                            width: 250,
                            height: 190,
                            fit: BoxFit.contain,
                          ),
                        ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: loading || saving ? null : pickImage,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('انتخاب عکس از گالری'),
              ),
            ),
            if (imageBytes != null)
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: loading || saving ? null : removeImage,
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                  ),
                  label: const Text(
                    'حذف عکس',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),
            const SizedBox(height: 5),
            const Text(
              'برای عملکرد بهتر، عکس کم‌حجم و باکیفیت انتخاب کنید.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving
              ? null
              : () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        FilledButton.icon(
          onPressed: loading || saving ? null : saveImage,
          icon: saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.save),
          label: const Text('ذخیره عکس'),
        ),
      ],
    );
  }
}
