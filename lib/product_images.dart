
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

const Color _fidelBlue = Color(0xFF12345A);
const Color _fidelGold = Color(0xFFC5A66A);

final FirebaseFirestore _db = FirebaseFirestore.instance;

const int _maxImageBytes = 600 * 1024;

/// نمایش عکس اصلی محصول
class ProductImageWidget extends StatelessWidget {
  final String productId;

  const ProductImageWidget({
    super.key,
    required this.productId,
  });

  @override
  Widget build(BuildContext context) {
    final imagesRef = _db
        .collection('product_images')
        .doc(productId)
        .collection('images');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: imagesRef.orderBy('sortOrder').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final docs = [...snapshot.data!.docs];

          docs.sort((a, b) {
            final aPrimary = a.data()['isPrimary'] == true ? 0 : 1;
            final bPrimary = b.data()['isPrimary'] == true ? 0 : 1;

            if (aPrimary != bPrimary) {
              return aPrimary.compareTo(bPrimary);
            }

            return (a.data()['sortOrder'] ?? 0)
                .compareTo(b.data()['sortOrder'] ?? 0);
          });

          final encoded = docs.first.data()['base64']?.toString() ?? '';

          if (encoded.isNotEmpty) {
            try {
              return _showImage(base64Decode(encoded));
            } catch (_) {}
          }
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _db.collection('product_images').doc(productId).snapshots(),
          builder: (context, oldSnapshot) {
            final data = oldSnapshot.data?.data() ?? {};
            final oldBase64 = data['base64']?.toString() ?? '';

            if (oldBase64.isNotEmpty) {
              try {
                return _showImage(base64Decode(oldBase64));
              } catch (_) {}
            }

            return _placeholder();
          },
        );
      },
    );
  }

  Widget _showImage(Uint8List bytes) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.memory(
        bytes,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _placeholder(),
      ),
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

  bool _loading = true;
  bool _saving = false;
  double _progress = 0;

  CollectionReference<Map<String, dynamic>> get _imagesRef =>
      _db.collection('product_images')
          .doc(widget.productId)
          .collection('images');

  DocumentReference<Map<String, dynamic>> get _parentRef =>
      _db.collection('product_images').doc(widget.productId);

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    try {
      final result = await _imagesRef.orderBy('sortOrder').get();

      if (result.docs.isNotEmpty) {
        final loaded = <Map<String, dynamic>>[];

        for (final doc in result.docs) {
          final data = doc.data();
          final encoded = data['base64']?.toString() ?? '';

          if (encoded.isEmpty) continue;

          try {
            loaded.add({
              'id': doc.id,
              'key': doc.id,
              'bytes': base64Decode(encoded),
              'isPrimary': data['isPrimary'] == true,
              'sortOrder': data['sortOrder'] ?? 0,
            });
          } catch (_) {}
        }

        if (mounted) {
          setState(() => _images = loaded);
        }
      } else {
        // سازگاری با عکس قدیمی
        final oldDoc = await _parentRef.get();
        final oldBase64 = oldDoc.data()?['base64']?.toString() ?? '';

        if (oldBase64.isNotEmpty) {
          try {
            final bytes = base64Decode(oldBase64);

            if (mounted) {
              setState(() {
                _images = [
                  {
                    'id': 'legacy',
                    'key': 'legacy',
                    'bytes': bytes,
                    'isPrimary': true,
                    'sortOrder': 0,
                  }
                ];
              });
            }
          } catch (_) {}
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
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 50,
      );

      if (files.isEmpty) return;

      int added = 0;

      for (final file in files) {
        final bytes = await file.readAsBytes();

        if (bytes.isEmpty) continue;

        if (bytes.length > _maxImageBytes) {
          _message(
            'حجم یکی از تصاویر بیشتر از ۶۰۰ کیلوبایت است؛ '
            'لطفاً تصویر کم‌حجم‌تری انتخاب کن.',
          );
          continue;
        }

        final key =
            'new_${DateTime.now().microsecondsSinceEpoch}_$added';

        setState(() {
          _images.add({
            'id': null,
            'key': key,
            'bytes': bytes,
            'isPrimary': _images.isEmpty,
            'sortOrder': _images.length,
          });
        });

        added++;
      }
    } catch (e) {
      _message('خطا در انتخاب تصاویر: $e');
    }
  }

  void _removeImage(int index) {
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
      final existing = await _imagesRef.get();
      final retainedIds = <String>{};

      if (_images.isEmpty) {
        for (final doc in existing.docs) {
          await doc.reference.delete();
        }

        await _parentRef.delete();
      } else {
        if (!_images.any((e) => e['isPrimary'] == true)) {
          _images[0]['isPrimary'] = true;
        }

        for (int i = 0; i < _images.length; i++) {
          final image = _images[i];
          final bytes = image['bytes'] as Uint8List;

          if (bytes.length > _maxImageBytes) {
            throw Exception('حجم یکی از تصاویر بیش از حد مجاز است.');
          }

          String? id = image['id']?.toString();

          if (id == null || id == 'legacy') {
            id = _imagesRef.doc().id;
          }

          retainedIds.add(id);

          await _imagesRef.doc(id).set({
            'base64': base64Encode(bytes),
            'isPrimary': image['isPrimary'] == true,
            'sortOrder': i,
            'productName': widget.productName,
            'updatedAt': FieldValue.serverTimestamp(),
          });

          if (mounted) {
            setState(() {
              _progress = (i + 1) / _images.length;
            });
          }
        }

        // حذف تصاویر قدیمی که از گالری حذف شده‌اند
        for (final doc in existing.docs) {
          if (!retainedIds.contains(doc.id)) {
            await doc.reference.delete();
          }
        }

        // ثبت اطلاعات گالری و حذف عکس Base64 قدیمی از سند اصلی
        await _parentRef.set({
          'productName': widget.productName,
          'imageCount': _images.length,
          'updatedAt': FieldValue.serverTimestamp(),
          'base64': FieldValue.delete(),
        }, SetOptions(merge: true));
      }

      if (!mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('گالری تصاویر ذخیره شد'),
        ),
      );
    } catch (e) {
      _message('خطا در ذخیره تصاویر: $e');

      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Widget _imagePreview(Map<String, dynamic> image) {
    final bytes = image['bytes'] as Uint8List;

    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) =>
          const Icon(Icons.broken_image_outlined),
    );
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
                  'برای تغییر ترتیب، تصاویر را جابه‌جا کن. '
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
                                key: ValueKey(image['key']),
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
                                    'برای جابه‌جایی نگه دار',
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
                    minimumSize: const Size(double.infinity, 46),
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
