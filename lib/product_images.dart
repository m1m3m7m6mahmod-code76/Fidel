
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

const Color _fidelBlue = Color(0xFF12345A);
const Color _fidelGold = Color(0xFFC5A66A);

final FirebaseFirestore _db = FirebaseFirestore.instance;
final FirebaseStorage _storage = FirebaseStorage.instance;

/// نمایش عکس اصلی محصول
class ProductImageWidget extends StatelessWidget {
  final String productId;

  const ProductImageWidget({
    super.key,
    required this.productId,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('product_images').doc(productId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _placeholder();
        }

        final data = snapshot.data!.data() ?? {};
        final images = List<Map<String, dynamic>>.from(
          (data['images'] ?? []).map(
            (e) => Map<String, dynamic>.from(e),
          ),
        );

        if (images.isNotEmpty) {
          images.sort((a, b) {
            final aPrimary = a['isPrimary'] == true ? 0 : 1;
            final bPrimary = b['isPrimary'] == true ? 0 : 1;
            if (aPrimary != bPrimary) {
              return aPrimary.compareTo(bPrimary);
            }
            return (a['sortOrder'] ?? 0).compareTo(
              b['sortOrder'] ?? 0,
            );
          });

          final url = images.first['url']?.toString() ?? '';

          if (url.isNotEmpty) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) => _placeholder(),
              ),
            );
          }
        }

        // پشتیبانی از عکس‌های قدیمی Base64
        final oldBase64 = data['base64']?.toString() ?? '';
        if (oldBase64.isNotEmpty) {
          try {
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                base64Decode(oldBase64),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            );
          } catch (_) {
            return _placeholder();
          }
        }

        return _placeholder();
      },
    );
  }

  Widget _placeholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.image_outlined,
        color: Colors.grey,
        size: 38,
      ),
    );
  }
}

/// مدیریت گالری تصاویر محصول
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
  final ImagePicker _picker = ImagePicker();

  List<Map<String, dynamic>> _images = [];
  final List<String> _removedPaths = [];

  bool _loading = true;
  bool _saving = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    try {
      final doc = await _db
          .collection('product_images')
          .doc(widget.productId)
          .get();

      if (doc.exists) {
        final data = doc.data() ?? {};

        final images = List<Map<String, dynamic>>.from(
          (data['images'] ?? []).map(
            (e) => Map<String, dynamic>.from(e),
          ),
        );

        // حفظ سازگاری با عکس قدیمی
        final oldBase64 = data['base64']?.toString() ?? '';

        if (images.isEmpty && oldBase64.isNotEmpty) {
          try {
            images.add({
              'url': null,
              'path': null,
              'bytes': base64Decode(oldBase64),
              'isPrimary': true,
              'sortOrder': 0,
            });
          } catch (_) {}
        }

        images.sort(
          (a, b) => (a['sortOrder'] ?? 0).compareTo(
            b['sortOrder'] ?? 0,
          ),
        );

        if (mounted) {
          setState(() {
            _images = images;
          });
        }
      }
    } catch (e) {
      _message('خطا در دریافت تصاویر: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickImages() async {
    try {
      final files = await _picker.pickMultiImage(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );

      if (files.isEmpty) return;

      for (final file in files) {
        final bytes = await file.readAsBytes();

        if (bytes.isEmpty) continue;

        setState(() {
          _images.add({
            'url': null,
            'path': null,
            'bytes': bytes,
            'isPrimary': _images.isEmpty,
            'sortOrder': _images.length,
          });
        });
      }
    } catch (e) {
      _message('خطا در انتخاب تصاویر: $e');
    }
  }

  void _removeImage(int index) {
    final image = _images[index];
    final path = image['path']?.toString();

    if (path != null && path.isNotEmpty) {
      _removedPaths.add(path);
    }

    setState(() {
      _images.removeAt(index);

      if (_images.isNotEmpty &&
          !_images.any((e) => e['isPrimary'] == true)) {
        _images[0]['isPrimary'] = true;
      }

      _updateOrders();
    });
  }

  void _setPrimary(int index) {
    setState(() {
      for (int i = 0; i < _images.length; i++) {
        _images[i]['isPrimary'] = i == index;
      }
    });
  }

  void _updateOrders() {
    for (int i = 0; i < _images.length; i++) {
      _images[i]['sortOrder'] = i;
    }
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;

      final item = _images.removeAt(oldIndex);
      _images.insert(newIndex, item);

      _updateOrders();
    });
  }

  Future<void> _saveImages() async {
    if (_saving) return;

    setState(() {
      _saving = true;
      _progress = 0;
    });

    try {
      final savedImages = <Map<String, dynamic>>[];

      for (int i = 0; i < _images.length; i++) {
        final image = _images[i];

        String? url = image['url']?.toString();
        String? path = image['path']?.toString();

        final bytes = image['bytes'] as Uint8List?;

        // آپلود عکس‌های جدید و عکس قدیمی Base64
        if (bytes != null && (url == null || url.isEmpty)) {
          final fileName =
              '${DateTime.now().microsecondsSinceEpoch}_$i.jpg';

          path = 'product_images/${widget.productId}/$fileName';

          final reference = _storage.ref().child(path);

          await reference.putData(
            bytes,
            SettableMetadata(contentType: 'image/jpeg'),
          );

          url = await reference.getDownloadURL();
        }

        if (url != null && url.isNotEmpty) {
          savedImages.add({
            'url': url,
            'path': path,
            'isPrimary': image['isPrimary'] == true,
            'sortOrder': i,
          });
        }

        if (mounted) {
          setState(() {
            _progress = (i + 1) / (_images.isEmpty ? 1 : _images.length);
          });
        }
      }

      // اگر عکس‌ها حذف شده‌اند، فایل‌های قبلی هم حذف شوند
      for (final path in _removedPaths) {
        try {
          await _storage.ref().child(path).delete();
        } catch (_) {}
      }

      if (savedImages.isEmpty) {
        await _db
            .collection('product_images')
            .doc(widget.productId)
            .delete();
      } else {
        // اطمینان از وجود فقط یک عکس اصلی
        if (!savedImages.any((e) => e['isPrimary'] == true)) {
          savedImages[0]['isPrimary'] = true;
        }

        await _db
            .collection('product_images')
            .doc(widget.productId)
            .set({
          'productName': widget.productName,
          'images': savedImages,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('گالری تصاویر با موفقیت ذخیره شد'),
        ),
      );
    } catch (e) {
      _message('خطا در ذخیره تصاویر: $e');
      setState(() => _saving = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Widget _imagePreview(Map<String, dynamic> image) {
    final bytes = image['bytes'] as Uint8List?;
    final url = image['url']?.toString() ?? '';

    if (bytes != null) {
      return Image.memory(bytes, fit: BoxFit.cover);
    }

    if (url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.broken_image_outlined),
      );
    }

    return const Icon(Icons.image_outlined);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.photo_library_outlined,
                    color: _fidelBlue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'گالری تصاویر ${widget.productName}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _fidelBlue,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(35),
                  child: CircularProgressIndicator(),
                )
              else ...[
                const Text(
                  'برای تغییر ترتیب، تصاویر را جابه‌جا کنید. '
                  'با انتخاب ستاره، عکس اصلی مشخص می‌شود.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SizedBox(
                    height: 340,
                    child: _images.isEmpty
                        ? const Center(
                            child: Text('هنوز تصویری ثبت نشده است'),
                          )
                        : ReorderableListView.builder(
                            itemCount: _images.length,
                            onReorder: _reorder,
                            itemBuilder: (context, index) {
                              final image = _images[index];
                              final isPrimary =
                                  image['isPrimary'] == true;

                              return Card(
                                key: ValueKey(image),
                                margin: const EdgeInsets.only(
                                  bottom: 9,
                                ),
                                child: ListTile(
                                  leading: SizedBox(
                                    width: 65,
                                    height: 65,
                                    child: ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(8),
                                      child: _imagePreview(image),
                                    ),
                                  ),
                                  title: Text(
                                    isPrimary
                                        ? 'عکس اصلی'
                                        : 'تصویر ${index + 1}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isPrimary
                                          ? _fidelGold
                                          : _fidelBlue,
                                    ),
                                  ),
                                  subtitle: const Text(
                                    'برای جابه‌جایی نگه دارید',
                                    style: TextStyle(fontSize: 10),
                                  ),
                                  trailing: Wrap(
                                    spacing: 0,
                                    children: [
                                      IconButton(
                                        tooltip: 'انتخاب عکس اصلی',
                                        onPressed: _saving
                                            ? null
                                            : () => _setPrimary(index),
                                        icon: Icon(
                                          isPrimary
                                              ? Icons.star
                                              : Icons.star_border,
                                          color: _fidelGold,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'حذف تصویر',
                                        onPressed: _saving
                                            ? null
                                            : () => _removeImage(index),
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickImages,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('افزودن تصاویر جدید'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _fidelBlue,
                    side: const BorderSide(color: _fidelBlue),
                    minimumSize: const Size(
                      double.infinity,
                      46,
                    ),
                  ),
                ),
                if (_saving) ...[
                  const SizedBox(height: 14),
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 6),
                  const Text(
                    'در حال ذخیره تصاویر...',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text('انصراف'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saving || _loading
                            ? null
                            : _saveImages,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('ذخیره گالری'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _fidelBlue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 46),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
