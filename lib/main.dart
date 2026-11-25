import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'product_images.dart';

const String adminUid = 'mbYMqJC4fHUgf1Mf3IhzyEeOa982';
const Color fidelBlue = Color(0xFF12345A);
final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;
const List<int> productSizes = [70, 80, 90, 120, 140, 160, 180];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const FidelApp());
}

class FidelApp extends StatelessWidget {
  const FidelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مدیریت فیدل',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: fidelBlue),
        useMaterial3: true,
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: AuthGate(),
      ),
    );
  }
}

String readText(dynamic value, [String fallback = '']) =>
    value == null ? fallback : value.toString();

String normalizeDigits(String value) {
  const p = '۰۱۲۳۴۵۶۷۸۹';
  const a = '٠١٢٣٤٥٦٧٨٩';
  for (int i = 0; i < 10; i++) {
    value = value.replaceAll(p[i], '$i').replaceAll(a[i], '$i');
  }
  return value;
}

int? parseNumber(dynamic value) {
  if (value == null) return null;
  return int.tryParse(normalizeDigits(value.toString())
      .replaceAll(',', '')
      .replaceAll('٬', '')
      .replaceAll(' ', '')
      .replaceAll('تومان', '')
      .trim());
}

String formatPrice(dynamic value) {
  final n = parseNumber(value);
  if (n == null) return 'استعلام';
  final s = n.toString();
  final out = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    out.write(s[i]);
    if (i < s.length - 1 && (s.length - i - 1) % 3 == 0) {
      out.write('٬');
    }
  }
  return normalizeDigits(out.toString());
}

String sizeLabel(int size) =>
    size == 70 ? '۷۰×۱۳۰' : '${normalizeDigits('$size')}×۲۰۰';

String normalizeCategory(dynamic value, String id) {
  final v = readText(value).toLowerCase();
  if (v.contains('plus') || v.contains('پلاس') || id.endsWith('_plus')) {
    return 'PLUS';
  }
  if (v.contains('economy') ||
      v.contains('اکونومی') ||
      v.contains('اقتصادی') ||
      id.endsWith('_economy')) {
    return 'ECONOMY';
  }
  return '';
}

dynamic findPrice(Map<String, dynamic> d, int size) {
  final p = d['price'] ?? d['prices'] ?? d['قیمت'];
  if (p is Map) {
    final v = p[size.toString()] ??
        p['${size}cm'] ??
        p['${size}x200'] ??
        p['${size}×200'] ??
        p['قیمت_$size'];
    if (v != null) return v;
  }
  for (final k in [
    'price_$size',
    'price$size',
    '${size}_price',
    '${size}cm',
    '$size',
    'قیمت_$size',
    'قیمت$size',
    '${size}_قیمت',
  ]) {
    if (d[k] != null) return d[k];
  }
  return p is num || p is String ? p : null;
}

dynamic findQuantity(Map<String, dynamic> d, int size) {
  final q = d['quantity'] ?? d['quantities'] ?? d['تعداد'];
  if (q is Map) {
    final v = q[size.toString()] ?? q['تعداد_$size'];
    if (v != null) return v;
  }
  for (final k in [
    'quantity_$size',
    'quantity$size',
    'stock_$size',
    'تعداد_$size',
    'موجودی_$size',
  ]) {
    if (d[k] != null) return d[k];
  }
  return null;
}

String productName(Map<String, dynamic> d, String id) {
  final n = readText(d['name'] ?? d['نام'] ?? d['نام_محصول']).trim();
  return n.isNotEmpty
      ? n
      : id.replaceAll('_plus', '').replaceAll('_economy', '');
}

String productField(
  Map<String, dynamic> d,
  String english,
  String persian, [
  String fallback = '',
]) =>
    readText(d[english] ?? d[persian], fallback);

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (s.data == null) return const AuthPage();
        if (s.data!.uid == adminUid) return const HomePage();
        return const RejectNonAdminPage();
      },
    );
  }
}

class RejectNonAdminPage extends StatefulWidget {
  const RejectNonAdminPage({super.key});

  @override
  State<RejectNonAdminPage> createState() => _RejectNonAdminPageState();
}

class _RejectNonAdminPageState extends State<RejectNonAdminPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => auth.signOut());
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('این حساب اجازه ورود ندارد.')),
      );
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  bool obscure = true;

  void message(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> login() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      message('ایمیل و رمز عبور را وارد کنید.');
      return;
    }
    setState(() => loading = true);
    try {
      final r = await auth.signInWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text,
      );
      if (r.user?.uid != adminUid) {
        await auth.signOut();
        message('این حساب اجازه ورود ندارد.');
      }
    } on FirebaseAuthException catch (e) {
      message(e.code == 'invalid-credential'
          ? 'ایمیل یا رمز عبور اشتباه است.'
          : 'خطا در ورود: ${e.message ?? e.code}');
    } catch (e) {
      message('خطا: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> resetPassword() async {
    if (email.text.trim().isEmpty) {
      message('ابتدا ایمیل را وارد کنید.');
      return;
    }
    try {
      await auth.sendPasswordResetEmail(email: email.text.trim());
      message('لینک بازیابی رمز ارسال شد.');
    } catch (e) {
      message('خطا: $e');
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  Image.asset('assets/logo.png', height: 75,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.bed, size: 60)),
                  const SizedBox(height: 12),
                  const Text('مدیریت فیدل',
                      style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.bold,
                          color: fidelBlue)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'ایمیل مدیر',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'رمز عبور',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(obscure
                            ? Icons.visibility
                            : Icons.visibility_off),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: loading ? null : login,
                      child: loading
                          ? const CircularProgressIndicator()
                          : const Text('ورود به مدیریت'),
                    ),
                  ),
                  TextButton(
                    onPressed: resetPassword,
                    child: const Text('فراموشی رمز عبور'),
                  ),
                  const Text('کیفیت رمز ماندگاریست',
                      style: TextStyle(
                          color: fidelBlue, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final List<Map<String, dynamic>> defaultBranches = [
  {
    'id': 'branch1',
    'name': 'شعبه اول فیدل',
    'address':
        'تهران، شهرک صنعتی چهاردانگه، خیابان ۲۴، بلوار صنایع شمالی، پلاک ۲۳، تشک فیدل',
    'phones': ['09331109969', '55264000', '55261436', '55261437'],
    'active': true,
  },
  {
    'id': 'branch2',
    'name': 'شعبه دوم فیدل',
    'address':
        'تهران، شهرک صنعتی چهاردانگه، خیابان رحیمی، بین خیابان اول و دوم، آلومینیوم‌کاران، پلاک ۷',
    'phones': ['09054206338', '55282990', '55282991'],
    'active': true,
  },
  {
    'id': 'factory',
    'name': 'کارخانه فیدل',
    'address':
        'تهران، کمربندی دوم تهران، واوان به سمت کهریزک، بعد از میدان عشقی، پلاک ۷',
    'phones': ['55277905'],
    'active': true,
  },
];

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    if (auth.currentUser?.uid != adminUid) return const AuthPage();
    return Scaffold(
      appBar: AppBar(
        title: const Text('مدیریت فیدل'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(
        index: tab,
        children: const [BranchesPage(), ProductManagementPage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.store_outlined), label: 'مدیریت شعب'),
          NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined), label: 'مدیریت کالا'),
        ],
      ),
    );
  }
}

class ProductManagementPage extends StatelessWidget {
  const ProductManagementPage({super.key});

  Future<void> moveProduct(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      int index,
      int direction) async {
    final target = index + direction;
    if (target < 0 || target >= docs.length) return;
    final batch = db.batch();
    final first = docs[index];
    final second = docs[target];
    batch.set(first.reference, {'sortOrder': target}, SetOptions(merge: true));
    batch.set(second.reference, {'sortOrder': index}, SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> toggleBestSeller(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final d = doc.data();
    final enabled = d['isBestseller'] == true;
    await doc.reference.set({
      'isBestseller': !enabled,
      'bestsellerOrder': enabled ? FieldValue.delete() : DateTime.now().microsecondsSinceEpoch,
    }, SetOptions(merge: true));
  }

  Future<void> editProduct(BuildContext context,
      {String? id, Map<String, dynamic>? data}) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProductEditorDialog(documentId: id, initialData: data ?? {}),
    );
  }

  Future<void> deleteProduct(BuildContext context, String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف محصول'),
        content: Text('محصول «$name» حذف شود؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final b = db.batch();
      b.delete(db.collection('products').doc(id));
      b.delete(db.collection('product_images').doc(id));
      await b.commit();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('محصول حذف شد.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطا: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (auth.currentUser?.uid != adminUid) {
      return const Center(child: Text('دسترسی مجاز نیست.'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Expanded(
                  child: Text('مدیریت محصولات',
                      style: TextStyle(
                          fontSize: 20,
                          color: fidelBlue,
                          fontWeight: FontWeight.bold))),
              FilledButton.icon(
                onPressed: () => editProduct(context),
                icon: const Icon(Icons.add),
                label: const Text('محصول جدید'),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Align(
              alignment: Alignment.centerRight,
              child: Text('ترتیب نمایش و پرفروش‌ها را از همین صفحه تنظیم کنید.')),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('products').snapshots(),
            builder: (context, s) {
              if (s.hasError) return Center(child: Text('خطا: ${s.error}'));
              if (!s.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = [...s.data!.docs];
              docs.sort((a, b) {
                final ao = a.data()['sortOrder'];
                final bo = b.data()['sortOrder'];
                if (ao is num && bo is num) return ao.compareTo(bo);
                if (ao is num) return -1;
                if (bo is num) return 1;
                return productName(a.data(), a.id)
                    .compareTo(productName(b.data(), b.id));
              });
              if (docs.isEmpty) {
                return const Center(child: Text('هنوز محصولی ثبت نشده است.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final d = doc.data();
                  final name = productName(d, doc.id);
                  final category =
                      normalizeCategory(d['category'] ?? d['دسته‌بندی'], doc.id);
                  final best = d['isBestseller'] == true;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ExpansionTile(
                      leading: ProductImageWidget(productId: doc.id),
                      title: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          '${category == 'PLUS' ? 'پلاس' : 'اکونومی'}'
                          '${best ? '  ⭐ پرفروش' : ''}'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              ...productSizes.map((size) {
                                final p = findPrice(d, size);
                                final q = findQuantity(d, size);
                                if (p == null && q == null) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                          width: 80,
                                          child: Text(sizeLabel(size))),
                                      Expanded(
                                          child: Text(p == null
                                              ? 'قیمت ثبت نشده'
                                              : '${formatPrice(p)} تومان')),
                                      Text('موجودی: ${q ?? '—'}'),
                                    ],
                                  ),
                                );
                              }),
                              const Divider(),
                              Wrap(
                                spacing: 5,
                                children: [
                                  IconButton(
                                    tooltip: 'انتقال به بالا',
                                    onPressed: i == 0
                                        ? null
                                        : () => moveProduct(docs, i, -1),
                                    icon: const Icon(Icons.arrow_upward),
                                  ),
                                  IconButton(
                                    tooltip: 'انتقال به پایین',
                                    onPressed: i == docs.length - 1
                                        ? null
                                        : () => moveProduct(docs, i, 1),
                                    icon: const Icon(Icons.arrow_downward),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => toggleBestSeller(doc),
                                    icon: Icon(best
                                        ? Icons.star
                                        : Icons.star_border),
                                    label: Text(best
                                        ? 'حذف از پرفروش‌ها'
                                        : 'افزودن به پرفروش‌ها'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => editProduct(context,
                                        id: doc.id, data: d),
                                    icon: const Icon(Icons.edit),
                                    label: const Text('ویرایش'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => showDialog(
                                      context: context,
                                      builder: (_) => ProductImageEditorDialog(
                                          productId: doc.id,
                                          productName: name),
                                    ),
                                    icon: const Icon(Icons.photo),
                                    label: const Text('مدیریت عکس'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () =>
                                        deleteProduct(context, doc.id, name),
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    label: const Text('حذف'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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

class ProductEditorDialog extends StatefulWidget {
  final String? documentId;
  final Map<String, dynamic> initialData;

  const ProductEditorDialog({
    super.key,
    this.documentId,
    required this.initialData,
  });

  @override
  State<ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<ProductEditorDialog> {
  final name = TextEditingController();
  final warranty = TextEditingController();
  final height = TextEditingController();
  final type = TextEditingController();
  final description = TextEditingController();
  final prices = <int, TextEditingController>{};
  final quantities = <int, TextEditingController>{};
  String category = 'ECONOMY';
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    name.text = productName(d, widget.documentId ?? '');
    warranty.text = productField(d, 'warranty', 'ضمانت');
    height.text = productField(d, 'height', 'ارتفاع');
    type.text = productField(d, 'type', 'نوع');
    description.text = productField(d, 'description', 'توضیحات');
    category = normalizeCategory(d['category'] ?? d['دسته‌بندی'],
        widget.documentId ?? '') == 'PLUS' ? 'PLUS' : 'ECONOMY';
    for (final size in productSizes) {
      prices[size] = TextEditingController(
          text: readText(findPrice(d, size)));
      quantities[size] = TextEditingController(
          text: readText(findQuantity(d, size)));
    }
  }

  Future<void> saveProduct() async {
    if (auth.currentUser?.uid != adminUid) return;
    if (name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('نام محصول را وارد کنید.')));
      return;
    }
    setState(() => saving = true);
    try {
      final ref = widget.documentId == null
          ? db.collection('products').doc()
          : db.collection('products').doc(widget.documentId);
      final data = <String, dynamic>{
        'name': name.text.trim(),
        'category': category,
        'warranty': warranty.text.trim(),
        'height': height.text.trim(),
        'type': type.text.trim(),
        'description': description.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (widget.documentId == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        data['sortOrder'] = DateTime.now().millisecondsSinceEpoch;
        data['isBestseller'] = false;
      }
      for (final size in productSizes) {
        final p = parseNumber(prices[size]!.text);
        final q = parseNumber(quantities[size]!.text);
        if (prices[size]!.text.trim().isNotEmpty) {
          data['price_$size'] = p ?? prices[size]!.text.trim();
        }
        if (quantities[size]!.text.trim().isNotEmpty) {
          data['quantity_$size'] = q ?? quantities[size]!.text.trim();
        }
      }
      await ref.set(data, SetOptions(merge: true));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطا در ذخیره: $e')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget field(TextEditingController c, String label, {int lines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: lines,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }

  @override
  void dispose() {
    name.dispose();
    warranty.dispose();
    height.dispose();
    type.dispose();
    description.dispose();
    for (final c in prices.values) {
      c.dispose();
    }
    for (final c in quantities.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 600,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                      child: Text(
                          widget.documentId == null
                              ? 'افزودن محصول'
                              : 'ویرایش محصول',
                          style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: fidelBlue))),
                  IconButton(
                      onPressed:
                          saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  field(name, 'نام محصول'),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(
                        labelText: 'گروه محصول',
                        border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(
                          value: 'ECONOMY', child: Text('اکونومی')),
                      DropdownMenuItem(value: 'PLUS', child: Text('پلاس')),
                    ],
                    onChanged: saving
                        ? null
                        : (v) {
                            if (v != null) setState(() => category = v);
                          },
                  ),
                  const SizedBox(height: 10),
                  field(warranty, 'مدت ضمانت'),
                  field(height, 'ارتفاع تشک'),
                  field(type, 'نوع ساخت و ویژگی‌ها', lines: 2),
                  field(description, 'توضیحات محصول', lines: 3),
                  const Divider(height: 28),
                  const Text('قیمت و موجودی هر سایز',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: fidelBlue,
                          fontSize: 17)),
                  const SizedBox(height: 10),
                  ...productSizes.map((size) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('سایز ${sizeLabel(size)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              TextField(
                                controller: prices[size],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'قیمت به تومان',
                                    border: OutlineInputBorder(),
                                    isDense: true),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: quantities[size],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'موجودی انبار',
                                    border: OutlineInputBorder(),
                                    isDense: true),
                              ),
                            ],
                          ),
                        ),
                      )),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: saving ? null : saveProduct,
                  icon: saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: const Text('ذخیره محصول'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BranchesPage extends StatelessWidget {
  const BranchesPage({super.key});

  Future<void> saveDefaults(BuildContext context) async {
    try {
      for (final b in defaultBranches) {
        final data = Map<String, dynamic>.from(b);
        final id = data.remove('id');
        await db.collection('branches').doc(id as String).set(
              data,
              SetOptions(merge: true),
            );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('شعب اولیه ذخیره شدند.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('خطا: $e')));
      }
    }
  }

  Future<void> editBranch(BuildContext context,
      {String? id, Map<String, dynamic>? old}) async {
    final n = TextEditingController(text: readText(old?['name']));
    final a = TextEditingController(text: readText(old?['address']));
    final p = TextEditingController(
        text: (old?['phones'] as List? ?? []).join('\n'));
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(id == null ? 'افزودن شعبه' : 'ویرایش شعبه'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: n,
                  decoration: const InputDecoration(labelText: 'نام شعبه')),
              TextField(
                  controller: a,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'آدرس')),
              TextField(
                  controller: p,
                  maxLines: 4,
                  decoration: const InputDecoration(
                      labelText: 'شماره‌ها؛ هر شماره در یک خط')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('ذخیره')),
        ],
      ),
    );
    if (result == true && n.text.trim().isNotEmpty && a.text.trim().isNotEmpty) {
      final ref = id == null ? db.collection('branches').doc() : db.collection('branches').doc(id);
      await ref.set({
        'name': n.text.trim(),
        'address': a.text.trim(),
        'phones': p.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        'active': old?['active'] ?? true,
      }, SetOptions(merge: true));
    }
    n.dispose();
    a.dispose();
    p.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (auth.currentUser?.uid != adminUid) {
      return const Center(child: Text('دسترسی مجاز نیست.'));
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('branches').snapshots(),
      builder: (context, s) {
        if (s.hasError) return Center(child: Text('خطا: ${s.error}'));
        if (!s.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = s.data!.docs;
        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            const Text('شعب و کارخانه فیدل',
                style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                    color: fidelBlue)),
            const SizedBox(height: 10),
            if (docs.isEmpty)
              FilledButton.icon(
                onPressed: () => saveDefaults(context),
                icon: const Icon(Icons.save),
                label: const Text('ثبت شعب اولیه در فایربیس'),
              ),
            FilledButton.icon(
              onPressed: () => editBranch(context),
              icon: const Icon(Icons.add),
              label: const Text('افزودن شعبه یا نمایندگی'),
            ),
            const SizedBox(height: 10),
            ...docs.map((doc) {
              final d = doc.data();
              final active = d['active'] == true;
              final phones = (d['phones'] as List? ?? []).join(' - ');
              return Card(
                child: ExpansionTile(
                  leading: Icon(Icons.store,
                      color: active ? fidelBlue : Colors.grey),
                  title: Text(readText(d['name'])),
                  subtitle: Text(active ? 'فعال' : 'غیرفعال'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(readText(d['address'])),
                          const SizedBox(height: 8),
                          Text('تماس: $phones'),
                          Wrap(
                            children: [
                              TextButton.icon(
                                onPressed: () =>
                                    editBranch(context, id: doc.id, old: d),
                                icon: const Icon(Icons.edit),
                                label: const Text('ویرایش'),
                              ),
                              TextButton.icon(
                                onPressed: () => doc.reference
                                    .update({'active': !active}),
                                icon: Icon(active
                                    ? Icons.visibility_off
                                    : Icons.visibility),
                                label: Text(active ? 'غیرفعال کردن' : 'فعال کردن'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
