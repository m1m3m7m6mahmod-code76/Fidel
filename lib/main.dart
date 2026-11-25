
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'product_images.dart';

const String adminUid = 'mbYMqJC4fHUgf1Mf3IhzyEeOa982';
const Color fidelBlue = Color(0xFF12345A);
const Color fidelGold = Color(0xFFC5A66A);
final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;
const List<int> productSizes = [70, 80, 90, 120, 140, 160, 180];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const FidelAdminApp());
}

class FidelAdminApp extends StatelessWidget {
  const FidelAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'مدیریت فیدل',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: fidelBlue,
          primary: fidelBlue,
          secondary: fidelGold,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
        appBarTheme: const AppBarTheme(
          backgroundColor: fidelBlue,
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
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
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  for (int i = 0; i < 10; i++) {
    value = value.replaceAll(persian[i], '$i').replaceAll(arabic[i], '$i');
  }
  return value;
}

int? parseNumber(dynamic value) {
  if (value == null) return null;
  return int.tryParse(
    normalizeDigits(value.toString())
        .replaceAll(',', '')
        .replaceAll('٬', '')
        .replaceAll('تومان', '')
        .replaceAll(' ', '')
        .trim(),
  );
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

String productName(Map<String, dynamic> data, String id) {
  final value =
      readText(data['name'] ?? data['نام'] ?? data['نام_محصول']).trim();
  if (value.isNotEmpty) return value;
  return id.replaceAll('_plus', '').replaceAll('_economy', '');
}

String productCategory(Map<String, dynamic> data, String id) {
  final value =
      readText(data['category'] ?? data['دسته‌بندی']).toLowerCase();
  if (value.contains('plus') ||
      value.contains('پلاس') ||
      id.endsWith('_plus')) {
    return 'PLUS';
  }
  return 'ECONOMY';
}

dynamic findPrice(Map<String, dynamic> data, int size) {
  final prices = data['price'] ?? data['prices'] ?? data['قیمت'];
  if (prices is Map) {
    final value = prices[size.toString()] ??
        prices['${size}cm'] ??
        prices['${size}x200'] ??
        prices['${size}×200'];
    if (value != null) return value;
  }
  return data['price_$size'] ??
      data['price$size'] ??
      data['${size}_price'] ??
      data['$size'] ??
      (prices is num || prices is String ? prices : null);
}

dynamic findQuantity(Map<String, dynamic> data, int size) {
  final quantities =
      data['quantity'] ?? data['quantities'] ?? data['تعداد'];
  if (quantities is Map) {
    final value =
        quantities[size.toString()] ?? quantities['تعداد_$size'];
    if (value != null) return value;
  }
  return data['quantity_$size'] ??
      data['quantity$size'] ??
      data['stock_$size'] ??
      data['تعداد_$size'] ??
      data['موجودی_$size'];
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.data == null) return const LoginPage();
        if (snapshot.data!.uid == adminUid) return const AdminHomePage();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          auth.signOut();
        });
        return const Scaffold(
          body: Center(child: Text('این حساب اجازه ورود ندارد.')),
        );
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  bool obscure = true;

  Future<void> login() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      showMessage(context, 'ایمیل و رمز عبور را وارد کنید.');
      return;
    }
    setState(() => loading = true);
    try {
      final result = await auth.signInWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text,
      );
      if (result.user?.uid != adminUid) {
        await auth.signOut();
        if (mounted) showMessage(context, 'این حساب مدیر اصلی نیست.');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        showMessage(context, 'ورود ناموفق بود: ${e.message ?? e.code}');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> resetPassword() async {
    if (email.text.trim().isEmpty) {
      showMessage(context, 'ابتدا ایمیل را وارد کنید.');
      return;
    }
    try {
      await auth.sendPasswordResetEmail(email: email.text.trim());
      if (mounted) showMessage(context, 'لینک بازیابی رمز ارسال شد.');
    } catch (e) {
      if (mounted) showMessage(context, 'خطا: $e');
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
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/logo.png',
                      height: 76,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.bed, size: 64, color: fidelBlue),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'پنل مدیریت فیدل',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: fidelBlue,
                      ),
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'ایمیل مدیر'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: password,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: 'رمز عبور',
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => obscure = !obscure),
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
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('ورود به مدیریت'),
                      ),
                    ),
                    TextButton(
                      onPressed: resetPassword,
                      child: const Text('فراموشی رمز عبور'),
                    ),
                    const Text(
                      'کیفیت رمز ماندگاریست',
                      style: TextStyle(
                        color: fidelBlue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  int selectedIndex = 0;

  final pages = const [
    DashboardPage(),
    ProductManagementPage(),
    BestSellersPage(),
    BranchesPage(),
    ContactSettingsPage(),
  ];

  final titles = const [
    'داشبورد فیدل',
    'مدیریت محصولات',
    'پرفروش‌ترین محصولات',
    'شعب و نمایندگی‌ها',
    'راه‌های ارتباطی',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[selectedIndex]),
        actions: [
          IconButton(
            tooltip: 'خروج از حساب',
            onPressed: () => auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(index: selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (value) =>
            setState(() => selectedIndex = value),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'خانه',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'محصولات',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_border),
            selectedIcon: Icon(Icons.star),
            label: 'پرفروش‌ها',
          ),
          NavigationDestination(
            icon: Icon(Icons.store_outlined),
            selectedIcon: Icon(Icons.store),
            label: 'شعب',
          ),
          NavigationDestination(
            icon: Icon(Icons.contact_phone_outlined),
            selectedIcon: Icon(Icons.contact_phone),
            label: 'ارتباطات',
          ),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  Widget _stat(String title, IconData icon, Stream<int> stream) {
    return StreamBuilder<int>(
      stream: stream,
      builder: (context, snapshot) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: fidelBlue, size: 28),
                const SizedBox(height: 12),
                Text(
                  snapshot.hasData ? '${snapshot.data}' : '—',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: fidelBlue,
                  ),
                ),
                Text(title),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [fidelBlue, Color(0xFF294F73)],
            ),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('خوش آمدید', style: TextStyle(color: fidelGold)),
              SizedBox(height: 8),
              Text(
                'مدیریت مجموعه فیدل',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'کیفیت رمز ماندگاریست',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.5,
          children: [
            _stat(
              'تعداد محصولات',
              Icons.inventory_2,
              db.collection('products').snapshots().map((s) => s.size),
            ),
            _stat(
              'تعداد شعب',
              Icons.store,
              db.collection('branches').snapshots().map((s) => s.size),
            ),
            _stat(
              'پرفروش‌ها',
              Icons.star,
              db
                  .collection('products')
                  .where('isBestseller', isEqualTo: true)
                  .snapshots()
                  .map((s) => s.size),
            ),
            _stat(
              'راه‌های ارتباطی',
              Icons.link,
              db.collection('contact_settings').snapshots().map((s) => s.size),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          'امکانات پنل',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: fidelBlue,
          ),
        ),
        const SizedBox(height: 8),
        const Card(
          child: ListTile(
            leading: Icon(Icons.inventory_2, color: fidelBlue),
            title: Text('مدیریت محصولات'),
            subtitle: Text('ثبت، ویرایش، قیمت، موجودی و تصویر محصولات'),
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.star, color: fidelGold),
            title: Text('پرفروش‌ترین‌ها'),
            subtitle: Text('انتخاب و مرتب‌سازی مستقل محصولات پرفروش'),
          ),
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.store, color: fidelBlue),
            title: Text('مدیریت شعب'),
            subtitle: Text('ثبت و ویرایش اطلاعات شعب و نمایندگی‌ها'),
          ),
        ),
      ],
    );
  }
}

class ProductManagementPage extends StatefulWidget {
  const ProductManagementPage({super.key});

  @override
  State<ProductManagementPage> createState() =>
      _ProductManagementPageState();
}

class _ProductManagementPageState extends State<ProductManagementPage> {
  String categoryFilter = 'ALL';
  String searchText = '';

  Future<void> _editProduct({
    String? id,
    Map<String, dynamic>? data,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProductEditorDialog(
        documentId: id,
        initialData: data ?? {},
      ),
    );
  }

  Future<void> _moveProduct(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int index,
    int direction,
  ) async {
    final target = index + direction;
    if (target < 0 || target >= docs.length) return;
    final batch = db.batch();
    batch.set(
      docs[index].reference,
      {'sortOrder': target},
      SetOptions(merge: true),
    );
    batch.set(
      docs[target].reference,
      {'sortOrder': index},
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> _toggleBestSeller(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final enabled = doc.data()['isBestseller'] == true;
    await doc.reference.set({
      'isBestseller': !enabled,
      'bestsellerOrder': enabled
          ? FieldValue.delete()
          : DateTime.now().microsecondsSinceEpoch,
    }, SetOptions(merge: true));
  }

  Future<void> _deleteProduct(String id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف محصول'),
        content: Text('محصول «$name» حذف شود؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final batch = db.batch();
      batch.delete(db.collection('products').doc(id));
      batch.delete(db.collection('product_images').doc(id));
      await batch.commit();
      if (mounted) showMessage(context, 'محصول حذف شد.');
    } catch (e) {
      if (mounted) showMessage(context, 'خطا در حذف: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'فهرست محصولات',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: fidelBlue,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _editProduct(),
                icon: const Icon(Icons.add),
                label: const Text('محصول جدید'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: TextField(
            onChanged: (value) =>
                setState(() => searchText = value.trim().toLowerCase()),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'جستجوی نام محصول',
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              _filterChip('همه', 'ALL'),
              const SizedBox(width: 8),
              _filterChip('اکونومی', 'ECONOMY'),
              const SizedBox(width: 8),
              _filterChip('پلاس', 'PLUS'),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('products').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('خطا: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs.where((doc) {
                final data = doc.data();
                final category = productCategory(data, doc.id);
                return (categoryFilter == 'ALL' ||
                        category == categoryFilter) &&
                    productName(data, doc.id)
                        .toLowerCase()
                        .contains(searchText);
              }).toList();
              docs.sort((a, b) {
                final x = a.data()['sortOrder'];
                final y = b.data()['sortOrder'];
                if (x is num && y is num) return x.compareTo(y);
                if (x is num) return -1;
                if (y is num) return 1;
                return productName(a.data(), a.id)
                    .compareTo(productName(b.data(), b.id));
              });
              if (docs.isEmpty) {
                return const Center(child: Text('محصولی پیدا نشد.'));
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data();
                  final name = productName(data, doc.id);
                  final category = productCategory(data, doc.id);
                  final best = data['isBestseller'] == true;
                  return Card(
                    child: ExpansionTile(
                      leading: ProductImageWidget(productId: doc.id),
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${category == 'PLUS' ? 'پلاس' : 'اکونومی'}'
                        '${best ? '  ★ پرفروش' : ''}',
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Wrap(
                                spacing: 8,
                                children: [
                                  Chip(
                                    label: Text(
                                      'ضمانت: ${readText(data['warranty'], '—')}',
                                    ),
                                  ),
                                  Chip(
                                    label: Text(
                                      'ارتفاع: ${readText(data['height'], '—')}',
                                    ),
                                  ),
                                ],
                              ),
                              ...productSizes.map((size) {
                                final price = findPrice(data, size);
                                final quantity = findQuantity(data, size);
                                if (price == null && quantity == null) {
                                  return const SizedBox.shrink();
                                }
                                return ListTile(
                                  dense: true,
                                  title: Text('سایز ${sizeLabel(size)}'),
                                  subtitle: Text(
                                    price == null
                                        ? 'قیمت ثبت نشده'
                                        : 'قیمت: ${formatPrice(price)} تومان',
                                  ),
                                  trailing: Text('موجودی: ${quantity ?? '—'}'),
                                );
                              }),
                              const Divider(),
                              Wrap(
                                alignment: WrapAlignment.center,
                                children: [
                                  IconButton(
                                    tooltip: 'انتقال به بالا',
                                    onPressed: index == 0
                                        ? null
                                        : () => _moveProduct(docs, index, -1),
                                    icon: const Icon(Icons.arrow_upward),
                                  ),
                                  IconButton(
                                    tooltip: 'انتقال به پایین',
                                    onPressed: index == docs.length - 1
                                        ? null
                                        : () => _moveProduct(docs, index, 1),
                                    icon: const Icon(Icons.arrow_downward),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _toggleBestSeller(doc),
                                    icon: Icon(
                                      best ? Icons.star : Icons.star_border,
                                    ),
                                    label: Text(
                                      best
                                          ? 'حذف از پرفروش‌ها'
                                          : 'افزودن به پرفروش‌ها',
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _editProduct(
                                      id: doc.id,
                                      data: data,
                                    ),
                                    icon: const Icon(Icons.edit),
                                    label: const Text('ویرایش'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => showDialog(
                                      context: context,
                                      builder: (_) => ProductImageEditorDialog(
                                        productId: doc.id,
                                        productName: name,
                                      ),
                                    ),
                                    icon: const Icon(Icons.photo),
                                    label: const Text('مدیریت عکس'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () =>
                                        _deleteProduct(doc.id, name),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
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

  Widget _filterChip(String label, String value) {
    return ChoiceChip(
      label: Text(label),
      selected: categoryFilter == value,
      onSelected: (_) => setState(() => categoryFilter = value),
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
  late final TextEditingController name;
  late final TextEditingController warranty;
  late final TextEditingController height;
  late final TextEditingController type;
  late final TextEditingController description;
  final Map<int, TextEditingController> prices = {};
  final Map<int, TextEditingController> quantities = {};
  String category = 'ECONOMY';
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData;
    name = TextEditingController(
      text: productName(data, widget.documentId ?? ''),
    );
    warranty = TextEditingController(text: readText(data['warranty']));
    height = TextEditingController(text: readText(data['height']));
    type = TextEditingController(text: readText(data['type']));
    description = TextEditingController(text: readText(data['description']));
    category = productCategory(data, widget.documentId ?? '');
    for (final size in productSizes) {
      prices[size] =
          TextEditingController(text: readText(findPrice(data, size)));
      quantities[size] =
          TextEditingController(text: readText(findQuantity(data, size)));
    }
  }

  Future<void> saveProduct() async {
    if (name.text.trim().isEmpty) {
      showMessage(context, 'نام محصول را وارد کنید.');
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
        final priceText = prices[size]!.text.trim();
        final quantityText = quantities[size]!.text.trim();
        if (priceText.isNotEmpty) {
          data['price_$size'] = parseNumber(priceText) ?? priceText;
        } else if (widget.initialData.containsKey('price_$size')) {
          data['price_$size'] = FieldValue.delete();
        }
        if (quantityText.isNotEmpty) {
          data['quantity_$size'] =
              parseNumber(quantityText) ?? quantityText;
        } else if (widget.initialData.containsKey('quantity_$size')) {
          data['quantity_$size'] = FieldValue.delete();
        }
      }
      await ref.set(data, SetOptions(merge: true));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showMessage(context, 'خطا در ذخیره محصول: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int lines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: lines,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label),
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
    for (final controller in prices.values) {
      controller.dispose();
    }
    for (final controller in quantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 620,
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
                        color: fidelBlue,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _field(name, 'نام محصول'),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(labelText: 'گروه محصول'),
                    items: const [
                      DropdownMenuItem(
                        value: 'ECONOMY',
                        child: Text('اکونومی'),
                      ),
                      DropdownMenuItem(
                        value: 'PLUS',
                        child: Text('پلاس'),
                      ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) =>
                            setState(() => category = value ?? 'ECONOMY'),
                  ),
                  const SizedBox(height: 10),
                  _field(warranty, 'مدت ضمانت'),
                  _field(height, 'ارتفاع تشک'),
                  _field(type, 'نوع ساخت و ویژگی‌ها', lines: 2),
                  _field(description, 'توضیحات محصول', lines: 3),
                  const SizedBox(height: 8),
                  const Text(
                    'قیمت و موجودی هر سایز',
                    style: TextStyle(
                      color: fidelBlue,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...productSizes.map(
                    (size) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'سایز ${sizeLabel(size)}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            _field(
                              prices[size]!,
                              'قیمت به تومان',
                              keyboardType: TextInputType.number,
                            ),
                            _field(
                              quantities[size]!,
                              'موجودی انبار',
                              keyboardType: TextInputType.number,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving ? null : saveProduct,
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('ذخیره محصول'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BestSellersPage extends StatelessWidget {
  const BestSellersPage({super.key});

  Future<void> _move(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    int index,
    int direction,
  ) async {
    final target = index + direction;
    if (target < 0 || target >= docs.length) return;
    final batch = db.batch();
    batch.set(
      docs[index].reference,
      {'bestsellerOrder': target},
      SetOptions(merge: true),
    );
    batch.set(
      docs[target].reference,
      {'bestsellerOrder': index},
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerRight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'پرفروش‌ترین محصولات',
                  style: TextStyle(
                    color: fidelBlue,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text('انتخاب و مرتب‌سازی این بخش از قسمت محصولات انجام می‌شود.'),
              ],
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db
                .collection('products')
                .where('isBestseller', isEqualTo: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('خطا: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs.toList();
              docs.sort((a, b) {
                final x = a.data()['bestsellerOrder'];
                final y = b.data()['bestsellerOrder'];
                if (x is num && y is num) return x.compareTo(y);
                if (x is num) return -1;
                if (y is num) return 1;
                return 0;
              });
              if (docs.isEmpty) {
                return const Center(
                  child: Text('هنوز محصولی به پرفروش‌ها اضافه نشده است.'),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data();
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFF3EBDD),
                        child: Text('${index + 1}'),
                      ),
                      title: Text(
                        productName(data, doc.id),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        productCategory(data, doc.id) == 'PLUS'
                            ? 'پلاس'
                            : 'اکونومی',
                      ),
                      trailing: Wrap(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: index == 0
                                ? null
                                : () => _move(docs, index, -1),
                            icon: const Icon(Icons.keyboard_arrow_up),
                          ),
                          IconButton(
                            onPressed: index == docs.length - 1
                                ? null
                                : () => _move(docs, index, 1),
                            icon: const Icon(Icons.keyboard_arrow_down),
                          ),
                          IconButton(
                            tooltip: 'حذف از پرفروش‌ها',
                            onPressed: () => doc.reference.set({
                              'isBestseller': false,
                              'bestsellerOrder': FieldValue.delete(),
                            }, SetOptions(merge: true)),
                            icon: const Icon(Icons.star, color: fidelGold),
                          ),
                        ],
                      ),
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

class BranchesPage extends StatelessWidget {
  const BranchesPage({super.key});

  Future<void> _saveDefaults(BuildContext context) async {
    try {
      final batch = db.batch();
      for (final branch in defaultBranches) {
        final data = Map<String, dynamic>.from(branch);
        final id = data.remove('id') as String;
        batch.set(
          db.collection('branches').doc(id),
          data,
          SetOptions(merge: true),
        );
      }
      await batch.commit();
      if (context.mounted) showMessage(context, 'شعب اولیه ثبت شدند.');
    } catch (e) {
      if (context.mounted) showMessage(context, 'خطا: $e');
    }
  }

  Future<void> _editBranch(
    BuildContext context, {
    String? id,
    Map<String, dynamic>? old,
  }) async {
    final name = TextEditingController(text: readText(old?['name']));
    final address = TextEditingController(text: readText(old?['address']));
    final phones = TextEditingController(
      text: (old?['phones'] as List? ?? []).join('\n'),
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(id == null ? 'افزودن شعبه' : 'ویرایش شعبه'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'نام شعبه'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: address,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'آدرس'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phones,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'شماره‌ها؛ هر شماره در یک خط',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    if (result == true &&
        name.text.trim().isNotEmpty &&
        address.text.trim().isNotEmpty) {
      final ref = id == null
          ? db.collection('branches').doc()
          : db.collection('branches').doc(id);
      await ref.set({
        'name': name.text.trim(),
        'address': address.text.trim(),
        'phones': phones.text
            .split('\n')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
        'active': old?['active'] ?? true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    name.dispose();
    address.dispose();
    phones.dispose();
  }

  Future<void> _deleteBranch(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف شعبه'),
        content: Text('«${readText(doc.data()['name'])}» حذف شود؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) await doc.reference.delete();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('branches').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('خطا: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'شعب و کارخانه فیدل',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: fidelBlue,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _editBranch(context),
                  icon: const Icon(Icons.add),
                  label: const Text('افزودن'),
                ),
              ],
            ),
            if (docs.isEmpty) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _saveDefaults(context),
                icon: const Icon(Icons.download),
                label: const Text('ثبت شعب اولیه فیدل'),
              ),
            ],
            const SizedBox(height: 8),
            ...docs.map((doc) {
              final data = doc.data();
              final active = data['active'] != false;
              final phones = (data['phones'] as List? ?? []).join(' - ');
              return Card(
                child: ExpansionTile(
                  leading: Icon(
                    Icons.store,
                    color: active ? fidelBlue : Colors.grey,
                  ),
                  title: Text(
                    readText(data['name']),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(active ? 'فعال' : 'غیرفعال'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(readText(data['address'])),
                          const SizedBox(height: 8),
                          Text('تماس: $phones'),
                          Wrap(
                            children: [
                              TextButton.icon(
                                onPressed: () => _editBranch(
                                  context,
                                  id: doc.id,
                                  old: data,
                                ),
                                icon: const Icon(Icons.edit),
                                label: const Text('ویرایش'),
                              ),
                              TextButton.icon(
                                onPressed: () => doc.reference.set({
                                  'active': !active,
                                }, SetOptions(merge: true)),
                                icon: Icon(
                                  active
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                label: Text(
                                  active ? 'غیرفعال کردن' : 'فعال کردن',
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => _deleteBranch(context, doc),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
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
            }),
          ],
        );
      },
    );
  }
}

class ContactSettingsPage extends StatefulWidget {
  const ContactSettingsPage({super.key});

  @override
  State<ContactSettingsPage> createState() => _ContactSettingsPageState();
}

class _ContactSettingsPageState extends State<ContactSettingsPage> {
  static const Map<String, String> fields = {
    'whatsapp': 'شماره یا لینک واتساپ',
    'eitaa': 'لینک ایتا',
    'rubika': 'لینک روبیکا',
    'bale': 'لینک بله',
    'telegram': 'لینک تلگرام',
    'website': 'آدرس وب‌سایت',
    'instagram': 'آدرس اینستاگرام',
  };

  Future<void> _edit(Map<String, dynamic> old) async {
    final controllers = <String, TextEditingController>{
      for (final entry in fields.entries)
        entry.key: TextEditingController(text: readText(old[entry.key])),
    };
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ویرایش راه‌های ارتباطی'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: fields.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: controllers[entry.key],
                    decoration: InputDecoration(labelText: entry.value),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    if (result == true) {
      final data = <String, dynamic>{
        for (final entry in controllers.entries)
          entry.key: entry.value.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await db
          .collection('contact_settings')
          .doc('main')
          .set(data, SetOptions(merge: true));
      if (mounted) showMessage(context, 'اطلاعات ارتباطی ذخیره شد.');
    }
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('contact_settings').doc('main').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('خطا: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!.data() ?? {};
        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'راه‌های ارتباطی فیدل',
                    style: TextStyle(
                      color: fidelBlue,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _edit(data),
                  icon: const Icon(Icons.edit),
                  label: const Text('ویرایش'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...fields.entries.map((entry) {
              final value = readText(data[entry.key]);
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.link, color: fidelBlue),
                  title: Text(entry.value),
                  subtitle: Text(
                    value.isEmpty ? 'ثبت نشده' : value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }),
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'این اطلاعات در مسیر contact_settings/main ذخیره می‌شود. برای نمایش تغییرات در اپ مشتری، اپ مشتری نیز باید همین مسیر را بخواند.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          ],
        );
      },
    );
  }
}
