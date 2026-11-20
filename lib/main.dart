
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';

const Color fidelBlue = Color(0xFF12345A);
final FirebaseFirestore db = FirebaseFirestore.instance;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const FidelCustomerApp());
}

class FidelCustomerApp extends StatelessWidget {
  const FidelCustomerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'تشک فیدل',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: fidelBlue,
          primary: fidelBlue,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: fidelBlue,
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
      ),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      home: const CustomerMainPage(),
    );
  }
}

class CustomerMainPage extends StatefulWidget {
  const CustomerMainPage({super.key});

  @override
  State<CustomerMainPage> createState() => _CustomerMainPageState();
}

class _CustomerMainPageState extends State<CustomerMainPage> {
  int selectedPage = 0;

  final List<Widget> pages = const [
    ProductsPage(),
    BranchesPage(),
    ContactPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'تشک فیدل',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: IndexedStack(
        index: selectedPage,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedPage,
        onDestinationSelected: (index) {
          setState(() => selectedPage = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bed_outlined),
            selectedIcon: Icon(Icons.bed),
            label: 'محصولات',
          ),
          NavigationDestination(
            icon: Icon(Icons.store_outlined),
            selectedIcon: Icon(Icons.store),
            label: 'شعب و نمایندگی‌ها',
          ),
          NavigationDestination(
            icon: Icon(Icons.support_agent_outlined),
            selectedIcon: Icon(Icons.support_agent),
            label: 'ارتباط با ما',
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------
// ابزارهای عمومی
// --------------------------------------------------

String toPersianDigits(String value) {
  const english = '0123456789';
  const persian = '۰۱۲۳۴۵۶۷۸۹';

  for (int i = 0; i < 10; i++) {
    value = value.replaceAll(english[i], persian[i]);
  }
  return value;
}

String normalizeDigits(String value) {
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  const arabic = '٠١٢٣٤٥٦٧٨٩';

  for (int i = 0; i < 10; i++) {
    value = value.replaceAll(persian[i], '$i');
    value = value.replaceAll(arabic[i], '$i');
  }
  return value;
}

String formatPrice(dynamic value) {
  if (value == null) return 'قیمت ثبت نشده';

  String raw = normalizeDigits(value.toString());
  raw = raw.replaceAll(',', '').replaceAll('٬', '');
  raw = raw.replaceAll('تومان', '').trim();

  final number = num.tryParse(raw);
  if (number == null) return 'قیمت ثبت نشده';

  final formatted = intl.NumberFormat('#,###', 'en_US').format(number);
  return '${toPersianDigits(formatted)} تومان';
}

String getProductName(Map<String, dynamic> data) {
  return (data['name'] ??
          data['نام'] ??
          data['نام_محصول'] ??
          'محصول فیدل')
      .toString();
}

String getProductCategory(
  Map<String, dynamic> data,
  String documentId,
) {
  final value = (data['category'] ?? data['دسته‌بندی'] ?? '')
      .toString()
      .toLowerCase()
      .trim();

  if (value.contains('plus') ||
      value.contains('پلاس') ||
      documentId.toLowerCase().endsWith('_plus')) {
    return 'plus';
  }

  return 'economy';
}

String getSizeLabel(int size) {
  if (size == 70) return '۷۰ × ۱۳۰';
  if (size == 80) return '۱۸۰ × ۸۰';
  return '${toPersianDigits(size.toString())} × ۲۰۰';
}

dynamic getProductPrice(
  Map<String, dynamic> data,
  int size,
) {
  final possibleKeys = [
    'price_$size',
    'price$size',
    'قیمت_$size',
    'قیمت$size',
    '${size}cm',
    '${size}x200',
    '${size}×200',
  ];

  for (final key in possibleKeys) {
    if (data[key] != null) return data[key];
  }

  final priceMap = data['prices'] ?? data['price'] ?? data['قیمت'];

  if (priceMap is Map) {
    for (final key in possibleKeys) {
      if (priceMap[key] != null) return priceMap[key];
    }

    if (priceMap['$size'] != null) {
      return priceMap['$size'];
    }
  }

  return null;
}

String getText(
  Map<String, dynamic> data,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = data[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }
  return fallback;
}

// --------------------------------------------------
// ارتباط با واتساپ شرکت
// --------------------------------------------------

Future<void> openCompanyWhatsApp(
  BuildContext context,
  String message,
) async {
  try {
    final snapshot = await db
        .collection('app_settings')
        .doc('contact')
        .get();

    String number =
        (snapshot.data()?['whatsappNumber'] ?? '').toString();

    number = number.replaceAll(RegExp(r'[^0-9]'), '');

    if (number.startsWith('00')) {
      number = number.substring(2);
    } else if (number.startsWith('0')) {
      number = '98${number.substring(1)}';
    }

    if (number.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('شماره واتساپ شرکت هنوز ثبت نشده است.'),
          ),
        );
      }
      return;
    }

    final uri = Uri.parse(
      'https://wa.me/$number?text=${Uri.encodeComponent(message)}',
    );

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('باز کردن واتساپ امکان‌پذیر نشد.'),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ارتباط با سرور برقرار نشد.'),
        ),
      );
    }
  }
}

// --------------------------------------------------
// نمایش تصویر محصول از فایراستور
// --------------------------------------------------

class ProductImageWidget extends StatelessWidget {
  final String productId;
  final double height;

  const ProductImageWidget({
    super.key,
    required this.productId,
    this.height = 180,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db
            .collection('product_images')
            .doc(productId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _placeholder();
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return _placeholder();
          }

          final base64Image = snapshot.data!.data()?['base64'];

          if (base64Image == null ||
              base64Image.toString().isEmpty) {
            return _placeholder();
          }

          try {
            final bytes = base64Decode(base64Image.toString());

            return Image.memory(
              bytes,
              fit: BoxFit.contain,
              width: double.infinity,
              errorBuilder: (_, __, ___) => _placeholder(),
            );
          } catch (_) {
            return _placeholder();
          }
        },
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      height: height,
      color: const Color(0xFFF0F2F5),
      child: const Center(
        child: Icon(
          Icons.bed,
          size: 65,
          color: fidelBlue,
        ),
      ),
    );
  }
}

// --------------------------------------------------
// صفحه محصولات
// --------------------------------------------------

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  String selectedCategory = 'economy';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: fidelBlue,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            children: [
              Text(
                'کیفیت رمز ماندگاریست',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'آرامش خواب با محصولات فیدل',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'economy',
                label: Text('Economy'),
                icon: Icon(Icons.bed_outlined),
              ),
              ButtonSegment(
                value: 'plus',
                label: Text('Plus'),
                icon: Icon(Icons.star_outline),
              ),
            ],
            selected: {selectedCategory},
            onSelectionChanged: (selection) {
              setState(() {
                selectedCategory = selection.first;
              });
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('products').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text(
                    'دریافت محصولات با مشکل مواجه شد.',
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              final products = snapshot.data!.docs.where((doc) {
                final category = getProductCategory(
                  doc.data(),
                  doc.id,
                );
                return category == selectedCategory;
              }).toList();

              if (products.isEmpty) {
                return const Center(
                  child: Text('در این گروه هنوز محصولی ثبت نشده است.'),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final doc = products[index];

                  return ProductCard(
                    productId: doc.id,
                    data: doc.data(),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------
// کارت محصول
// --------------------------------------------------

class ProductCard extends StatefulWidget {
  final String productId;
  final Map<String, dynamic> data;

  const ProductCard({
    super.key,
    required this.productId,
    required this.data,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  final List<int> sizes = [70, 80, 90, 120, 140, 160, 180];

  int selectedSize = 90;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;

    final name = getProductName(data);

    final warranty = getText(
      data,
      ['warranty', 'ضمانت'],
      fallback: 'ثبت نشده',
    );

    final height = getText(
      data,
      ['height', 'thickness', 'ارتفاع', 'ضخامت'],
    );

    final type = getText(
      data,
      ['type', 'نوع'],
    );

    final description = getText(
      data,
      ['description', 'توضیحات'],
    );

    final features = getText(
      data,
      ['features', 'ویژگی‌ها'],
    );

    final price = getProductPrice(data, selectedSize);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProductImageWidget(
            productId: widget.productId,
            height: 190,
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: fidelBlue,
                  ),
                ),
                const SizedBox(height: 10),
                if (type.isNotEmpty)
                  _infoRow('نوع تشک', type),
                if (height.isNotEmpty)
                  _infoRow('ارتفاع', height),
                _infoRow('ضمانت', warranty),
                if (features.isNotEmpty)
                  _infoRow('ویژگی‌ها', features),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Colors.black87,
                      height: 1.7,
                    ),
                  ),
                ],
                const Divider(height: 25),
                const Text(
                  'انتخاب سایز:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: selectedSize,
                  isExpanded: true,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: sizes.map((size) {
                    return DropdownMenuItem<int>(
                      value: size,
                      child: Text('${getSizeLabel(size)} سانتی‌متر'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedSize = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF0F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'قیمت محصول',
                        style: TextStyle(
                          color: fidelBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        formatPrice(price),
                        style: const TextStyle(
                          color: fidelBlue,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: fidelBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: () {
                      final message =
                          'سلام، برای سفارش محصول فیدل راهنمایی می‌خواستم.\n'
                          'نام محصول: $name\n'
                          'سایز: ${getSizeLabel(selectedSize)}\n'
                          'لطفاً راهنمایی بفرمایید.';

                      openCompanyWhatsApp(context, message);
                    },
                    icon: const Icon(Icons.shopping_cart_outlined),
                    label: const Text(
                      'سفارش از طریق واتساپ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title: ',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

// --------------------------------------------------
// صفحه شعب و نمایندگی‌ها
// --------------------------------------------------

class BranchesPage extends StatelessWidget {
  const BranchesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db
          .collection('branches')
          .where('active', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: Text('دریافت اطلاعات شعب امکان‌پذیر نیست.'),
          );
        }

        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final branches = snapshot.data!.docs;

        if (branches.isEmpty) {
          return const Center(
            child: Text('در حال حاضر شعبه فعالی ثبت نشده است.'),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: branches.length,
          itemBuilder: (context, index) {
            final data = branches[index].data();

            final name = (data['name'] ?? 'شعبه فیدل').toString();
            final address = (data['address'] ?? '').toString();
            final phones = data['phones'] is List
                ? List<String>.from(data['phones'])
                : <String>[];

            return Card(
              color: Colors.white,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.store,
                          color: fidelBlue,
                          size: 27,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: fidelBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      address,
                      style: const TextStyle(height: 1.7),
                    ),
                    if (phones.isNotEmpty) ...[
                      const Divider(height: 24),
                      const Text(
                        'شماره‌های تماس:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...phones.map(
                        (phone) => Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: InkWell(
                            onTap: () async {
                              final uri = Uri(
                                scheme: 'tel',
                                path: phone,
                              );
                              await launchUrl(uri);
                            },
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.phone,
                                  color: fidelBlue,
                                  size: 19,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  toPersianDigits(phone),
                                  style: const TextStyle(
                                    color: fidelBlue,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// --------------------------------------------------
// صفحه ارتباط با ما
// --------------------------------------------------

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            const Icon(
              Icons.support_agent,
              size: 85,
              color: fidelBlue,
            ),
            const SizedBox(height: 18),
            const Text(
              'ارتباط با فیدل',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
                color: fidelBlue,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'برای دریافت مشاوره، راهنمایی انتخاب تشک و ثبت سفارش، '
              'از طریق واتساپ با کارشناسان فیدل در ارتباط باشید.',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.9),
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: fidelBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: () {
                  openCompanyWhatsApp(
                    context,
                    'سلام، برای دریافت مشاوره از کارشناسان تشک فیدل پیام می‌دهم.',
                  );
                },
                icon: const Icon(Icons.chat),
                label: const Text(
                  'مشاوره در واتساپ',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 25),
            const Text(
              'کیفیت رمز ماندگاریست',
              style: TextStyle(
                color: fidelBlue,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
