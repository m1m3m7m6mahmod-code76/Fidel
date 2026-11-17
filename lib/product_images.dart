

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// نمایش عکس محصول
class ProductImageWidget extends StatelessWidget {
  final String productId;
  final double width;
  final double height;
  final bool showPlaceholder;

  const ProductImageWidget({
    super.key,
    required this.productId,
    this.width = 64,
    this.height = 64,
    this.showPlaceholder = true,
  });

  Widget _placeholder() {
    if (!showPlaceholder) {
      return const SizedBox.shrink();
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.bed_outlined,
        color: Colors.grey.shade500,
        size: 32,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('product_images')
          .doc(productId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError ||
            !snapshot.hasData ||
            !snapshot.data!.exists) {
          return _placeholder();
        }

        final imageData = snapshot.data!.data()?['base64'];

        if (imageData is! String || imageData.isEmpty) {
          return _placeholder();
        }

        try {
          final bytes = base64Decode(imageData);

          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              bytes,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _placeholder();
              },
            ),
          );
        } catch (_) {
          return _placeholder();
        }
      },
    );
  }
}

/// پنجره انتخاب، ثبت و حذف عکس محصول
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
  Uint8List? selectedBytes;
  bool busy = false;

  static const int maxImageSize = 500 * 1024;

  Future<void> pickImage() async {
    try {
      final picker = ImagePicker();

      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 65,
      );

      if (pickedFile == null || !mounted) return;

      final bytes = await pickedFile.readAsBytes();

      if (bytes.length > maxImageSize) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'حجم عکس بیشتر از حد مجاز است. لطفاً عکس کوچک‌تری انتخاب کنید.',
            ),
          ),
        );
        return;
      }

      setState(() {
        selectedBytes = bytes;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در انتخاب عکس: $e')),
      );
    }
  }

  Future<void> saveImage() async {
    if (selectedBytes == null || busy) return;

    setState(() => busy = true);

    final messenger = ScaffoldMessenger.of(context);

    try {
      final encodedImage = base64Encode(selectedBytes!);

      await FirebaseFirestore.instance
          .collection('product_images')
          .doc(widget.productId)
          .set({
        'base64': encodedImage,
        'productName': widget.productName,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      messenger.showSnackBar(
        const SnackBar(
          content: Text('عکس محصول با موفقیت ذخیره شد.'),
        ),
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      setState(() => busy = false);

      messenger.showSnackBar(
        SnackBar(content: Text('خطا در ذخیره عکس: $e')),
      );
    }
  }

  Future<void> deleteImage() async {
    if (busy) return;

    final messenger = ScaffoldMessenger.of(context);

    setState(() => busy = true);

    try {
      await FirebaseFirestore.instance
          .collection('product_images')
          .doc(widget.productId)
          .delete();

      messenger.showSnackBar(
        const SnackBar(
          content: Text('عکس محصول حذف شد.'),
        ),
      );

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      setState(() => busy = false);

      messenger.showSnackBar(
        SnackBar(content: Text('خطا در حذف عکس: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('عکس ${widget.productName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selectedBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  selectedBytes!,
                  width: 190,
                  height: 160,
                  fit: BoxFit.cover,
                ),
              )
            else
              ProductImageWidget(
                productId: widget.productId,
                width: 190,
                height: 160,
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: busy ? null : pickImage,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('انتخاب عکس از گالری'),
            ),
            const SizedBox(height: 8),
            const Text(
              'حجم عکس باید کمتر از ۵۰۰ کیلوبایت باشد.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : deleteImage,
          child: const Text(
            'حذف عکس',
            style: TextStyle(color: Colors.red),
          ),
        ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('انصراف'),
        ),
        ElevatedButton(
          onPressed:
              busy || selectedBytes == null ? null : saveImage,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Text('ذخیره عکس'),
        ),
      ],
    );
  }
}
