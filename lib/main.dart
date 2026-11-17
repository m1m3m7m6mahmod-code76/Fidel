
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
      title: 'فیدل | فروشگاه تشک',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: fidelBlue),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: AuthGate(),
      ),
    );
  }
}

// =====================================================
// ابزارهای عمومی
// =====================================================

String readText(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  return value.toString();
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

int? parseNumber(dynamic value) {
  if (value == null) return null;

  final text = normalizeDigits(value.toString())
      .replaceAll(',', '')
      .replaceAll('٬', '')
      .replaceAll(' ', '')
      .replaceAll('تومان', '')
      .trim();

  return int.tryParse(text);
}

String formatPrice(dynamic value) {
  final number = parseNumber(value);
  if (number == null) return 'استعلام';

  final raw = number.toString();
  final buffer = StringBuffer();

  for (int i = 0; i < raw.length; i++) {
    buffer.write(raw[i]);
    final remaining = raw.length - i - 1;
    if (remaining > 0 && remaining % 3 == 0) {
      buffer.write('٬');
    }
  }

  return normalizeDigits(buffer.toString());
}

String sizeLabel(int size) {
  return size == 70 ? '۷۰×۱۳۰' : '${normalizeDigits('$size')}×۲۰۰';
}

String normalizeCategory(dynamic value, String documentId) {
  final category = readText(value).toLowerCase();
  final id = documentId.toLowerCase();

  if (category.contains('plus') ||
      category.contains('پلاس') ||
      id.endsWith('_plus')) {
    return 'PLUS';
  }

  if (category.contains('economy') ||
      category.contains('اکونومی') ||
      category.contains('اقتصادی') ||
      id.endsWith('_economy')) {
    return 'ECONOMY';
  }

  return '';
}

dynamic findPrice(Map<String, dynamic> data, int size) {
  final priceValue = data['price'] ?? data['prices'] ?? data['قیمت'];

  if (priceValue is Map) {
    final value = priceValue[size.toString()] ??
        priceValue['${size}cm'] ??
        priceValue['${size}x200'] ??
        priceValue['${size}×200'] ??
        priceValue['قیمت_$size'] ??
        priceValue['قیمت$size'];

    if (value != null) return value;
  }

  final possibleKeys = [
    'price_$size',
    'price$size',
    '${size}_price',
    '${size}cm',
    '$size',
    'قیمت_$size',
    'قیمت$size',
    '${size}_قیمت',
  ];

  for (final key in possibleKeys) {
    if (data[key] != null) return data[key];
  }

  if (priceValue is num || priceValue is String) {
    return priceValue;
  }

  return null;
}

dynamic findQuantity(Map<String, dynamic> data, int size) {
  final quantityValue =
      data['quantity'] ?? data['quantities'] ?? data['تعداد'];

  if (quantityValue is Map) {
    final value = quantityValue[size.toString()] ??
        quantityValue['تعداد_$size'] ??
        quantityValue['تعداد$size'];

    if (value != null) return value;
  }

  final keys = [
    'quantity_$size',
    'quantity$size',
    'stock_$size',
    'stock$size',
    'تعداد_$size',
    'تعداد$size',
    'موجودی_$size',
    'موجودی$size',
  ];

  for (final key in keys) {
    if (data[key] != null) return data[key];
  }

  return null;
}

String productName(Map<String, dynamic> data, String documentId) {
  final name = readText(
    data['name'] ?? data['نام'] ?? data['نام_محصول'],
  ).trim();

  if (name.isNotEmpty) return name;

  return documentId
      .replaceAll('_plus', '')
      .replaceAll('_economy', '');
}

String productField(
  Map<String, dynamic> data,
  String englishKey,
  String persianKey, [
  String fallback = '',
]) {
  return readText(
    data[englishKey] ?? data[persianKey],
    fallback,
  );
}

// =====================================================
// ورود و ثبت نام
// =====================================================

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

        if (snapshot.hasData) return const HomePage();
        return const AuthPage();
      },
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final phoneController = TextEditingController();
  final codeController = TextEditingController();

  bool customerMode = true;
  bool loading = false;
  bool obscurePassword = true;
  bool codeSent = false;

  String verificationId = '';
  int? resendToken;

  void message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  String normalizePhone(String input) {
    String phone = normalizeDigits(input.trim());
    phone = phone.replaceAll(' ', '').replaceAll('-', '');

    if (phone.startsWith('09') && phone.length == 11) {
      return '+98${phone.substring(1)}';
    }

    if (phone.startsWith('9') && phone.length == 10) {
      return '+98$phone';
    }

    if (phone.startsWith('0098')) {
      return '+${phone.substring(2)}';
    }

    return phone;
  }

  String authError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'ایمیل معتبر نیست.';
      case 'user-not-found':
        return 'حساب کاربری پیدا نشد.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'اطلاعات ورود اشتباه است.';
      case 'too-many-requests':
        return 'تعداد تلاش‌ها زیاد است. کمی بعد امتحان کنید.';
      case 'network-request-failed':
        return 'اتصال اینترنت را بررسی کنید.';
      case 'invalid-phone-number':
        return 'شماره موبایل معتبر نیست.';
      case 'invalid-verification-code':
        return 'کد پیامکی اشتباه است.';
      case 'session-expired':
        return 'کد پیامکی منقضی شده است.';
      case 'quota-exceeded':
        return 'سهمیه ارسال پیامک تمام شده است.';
      case 'operation-not-allowed':
        return 'ورود پیامکی در فایربیس فعال نیست.';
      default:
        return 'خطا: ${e.message ?? e.code}';
    }
  }

  Future<void> adminLogin() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      message('ایمیل و رمز عبور را وارد کنید.');
      return;
    }

    setState(() => loading = true);

    try {
      final result = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user?.uid != adminUid) {
        await auth.signOut();
        message('این بخش فقط مخصوص مدیر فیدل است.');
      }
    } on FirebaseAuthException catch (e) {
      message(authError(e));
    } catch (_) {
      message('خطای غیرمنتظره رخ داد.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> sendSms() async {
    final phone = normalizePhone(phoneController.text);

    if (!phone.startsWith('+') || phone.length < 10) {
      message('شماره موبایل را صحیح وارد کنید.');
      return;
    }

    setState(() {
      loading = true;
      codeSent = false;
    });

    try {
      await auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        forceResendingToken: resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            await auth.signInWithCredential(credential);
          } on FirebaseAuthException catch (e) {
            message(authError(e));
          } finally {
            if (mounted) setState(() => loading = false);
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => loading = false);
          message(authError(e));
        },
        codeSent: (String id, int? token) {
          if (!mounted) return;
          setState(() {
            verificationId = id;
            resendToken = token;
            codeSent = true;
            loading = false;
          });
          message('کد تأیید ارسال شد.');
        },
        codeAutoRetrievalTimeout: (String id) {
          verificationId = id;
        },
      );
    } on FirebaseAuthException catch (e) {
      message(authError(e));
      if (mounted) setState(() => loading = false);
    } catch (_) {
      message('ارسال پیامک با خطا روبه‌رو شد.');
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> verifySmsCode() async {
    final code = normalizeDigits(codeController.text.trim());

    if (code.length != 6) {
      message('کد شش رقمی را وارد کنید.');
      return;
    }

    setState(() => loading = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: code,
      );

      await auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      message(authError(e));
    } catch (_) {
      message('بررسی کد با خطا روبه‌رو شد.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> resetPassword() async {
    final email = emailController.text.trim();

    if (email.isEmpty) {
      message('ابتدا ایمیل مدیر را وارد کنید.');
      return;
    }

    try {
      await auth.sendPasswordResetEmail(email: email);
      message('لینک بازیابی رمز به ایمیل ارسال شد.');
    } on FirebaseAuthException catch (e) {
      message(authError(e));
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    phoneController.dispose();
    codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    Image.asset(
                      'assets/logo.png',
                      height: 75,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.bed,
                        size: 65,
                        color: fidelBlue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'فروشگاه تشک فیدل',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                        color: fidelBlue,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: loading
                                ? null
                                : () => setState(() {
                                      customerMode = true;
                                      codeSent = false;
                                    }),
                            child: const Text('ورود مشتری'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: loading
                                ? null
                                : () => setState(() {
                                      customerMode = false;
                                    }),
                            child: const Text('ورود مدیر'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    if (customerMode) ...[
                      const Text(
                        'ورود با شماره موبایل',
                        style: TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'شماره موبایل',
                          hintText: '09123456789',
                          prefixIcon: Icon(Icons.phone_android),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (codeSent) ...[
                        const SizedBox(height: 14),
                        TextField(
                          controller: codeController,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: 'کد پیامکی',
                            prefixIcon: Icon(Icons.sms_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          onPressed: loading
                              ? null
                              : codeSent
                                  ? verifySmsCode
                                  : sendSms,
                          child: loading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : Text(
                                  codeSent
                                      ? 'تأیید کد و ورود'
                                      : 'ارسال کد پیامکی',
                                ),
                        ),
                      ),
                      if (codeSent)
                        TextButton(
                          onPressed: loading ? null : sendSms,
                          child: const Text('ارسال دوباره کد'),
                        ),
                    ] else ...[
                      const Text(
                        'ورود مدیر فیدل',
                        style: TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'ایمیل مدیر',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'رمز عبور',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                              () => obscurePassword = !obscurePassword,
                            ),
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          onPressed: loading ? null : adminLogin,
                          child: loading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text('ورود مدیر'),
                        ),
                      ),
                      TextButton(
                        onPressed: loading ? null : resetPassword,
                        child: const Text('فراموشی رمز عبور'),
                      ),
                    ],
                    const Divider(height: 28),
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

// =====================================================
// اطلاعات شعب
// =====================================================

final List<Map<String, dynamic>> defaultBranches = [
  {
    'id': 'branch1',
    'name': 'شعبه اول فیدل',
    'address':
        'تهران، شهرک صنعتی چهاردانگه، خیابان ۲۴، بلوار صنایع شمالی، پلاک ۲۳، تشک فیدل',
    'phones': [
      '09331109969',
      '55264000',
      '55261436',
      '55261437',
    ],
    'active': true,
  },
  {
    'id': 'branch2',
    'name': 'شعبه دوم فیدل',
    'address':
        'تهران، شهرک صنعتی چهاردانگه، خیابان رحیمی (خیابان اصلی شهرک)، بین خیابان اول و دوم، آلومینیوم‌کاران، پلاک ۷، تشک فیدل',
    'phones': [
      '09054206338',
      '55282990',
      '55282991',
    ],
    'active': true,
  },
  {
    'id': 'factory',
    'name': 'کارخانه فیدل',
    'address':
        'تهران، کمربندی دوم تهران، واوان به سمت کهریزک، بعد از میدان عشقی، پلاک ۷، تشک فیدل',
    'phones': ['55277905'],
    'active': true,
  },
];

// =====================================================
// صفحه اصلی
// =====================================================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;

  bool get isAdmin => auth.currentUser?.uid == adminUid;

  Future<void> signOut() async {
    await auth.signOut();
  }

  void showInfo() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('درباره فیدل'),
        content: const Text(
          'شرکت تشک فیدل\n'
          'تولیدکننده انواع تشک با سابقه فعالیت حدود ۲۸ سال\n\n'
          'کیفیت رمز ماندگاریست',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      BranchesPage(isAdmin: isAdmin),
      const CatalogPage(),
      const AssistantPage(),
      const OrdersPage(),
      if (isAdmin) const ProductManagementPage(),
    ];

    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.store_outlined),
        label: 'شعب و نمایندگی',
      ),
      const NavigationDestination(
        icon: Icon(Icons.bed_outlined),
        label: 'محصولات',
      ),
      const NavigationDestination(
        icon: Icon(Icons.chat_bubble_outline),
        label: 'مشاور هوشمند',
      ),
      const NavigationDestination(
        icon: Icon(Icons.receipt_long_outlined),
        label: 'سفارش‌ها',
      ),
      if (isAdmin)
        const NavigationDestination(
          icon: Icon(Icons.inventory_2_outlined),
          label: 'مدیریت کالا',
        ),
    ];

    if (tab >= pages.length) tab = 0;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/logo.png',
              height: 38,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.bed, size: 32),
            ),
            const SizedBox(width: 8),
            const Text(
              'فیدل',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: showInfo,
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            onPressed: signOut,
            tooltip: 'خروج',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          if (isAdmin)
            Container(
              width: double.infinity,
              color: const Color(0xFFE8EEF5),
              padding: const EdgeInsets.all(8),
              child: const Text(
                'حساب مدیر فیدل',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: fidelBlue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          Expanded(child: pages[tab]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: destinations,
      ),
    );
  }
}

// =====================================================
// کاتالوگ محصولات مشتری
// =====================================================

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  String tier = 'ECONOMY';
  int size = 160;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: fidelBlue,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'خواب راحت، انتخاب مطمئن',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'مدل مناسب خودتان را از میان تشک‌های فیدل پیدا کنید',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: tier,
                  decoration: const InputDecoration(
                    labelText: 'گروه محصول',
                    border: OutlineInputBorder(),
                  ),
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
                  onChanged: (v) {
                    if (v != null) setState(() => tier = v);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: size,
                  decoration: const InputDecoration(
                    labelText: 'ابعاد تشک',
                    border: OutlineInputBorder(),
                  ),
                  items: productSizes
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text('${sizeLabel(v)} سانتی‌متر'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => size = v);
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('products').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'دریافت محصولات با خطا روبه‌رو شد.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final docs = snapshot.data?.docs ?? [];

              final filtered = docs.where((doc) {
                final data = doc.data();
                final category = normalizeCategory(
                  data['category'] ?? data['دسته‌بندی'],
                  doc.id,
                );

                if (category != tier) return false;

                if (size == 70) {
                  final name = productName(data, doc.id);
                  if (!name.contains('آسوده')) return false;
                }

                return true;
              }).toList();

              if (filtered.isEmpty) {
                return const Center(
                  child: Text('محصولی در این گروه پیدا نشد.'),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final doc = filtered[index];
                  final data = doc.data();

                  final name = productName(data, doc.id);
                  final warranty = productField(
                    data,
                    'warranty',
                    'ضمانت',
                    'ثبت نشده',
                  );
                  final type = productField(
                    data,
                    'type',
                    'نوع',
                    productField(
                      data,
                      'features',
                      'ویژگی‌ها',
                      'تشک فیدل',
                    ),
                  );
                  final price = findPrice(data, size);

                  final height = productField(
                    data,
                    'height',
                    'ارتفاع',
                    productField(data, 'thickness', 'ضخامت'),
                  );

                  final description = productField(
                    data,
                    'description',
                    'توضیحات',
                  );

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ExpansionTile(
                      leading: ProductImageWidget(
                        productId: doc.id,
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text('$type\nضمانت: $warranty'),
                      trailing: Text(
                        price == null
                            ? 'استعلام'
                            : '${formatPrice(price)} تومان',
                        style: const TextStyle(
                          color: fidelBlue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Center(
                            child: ProductImageWidget(
                              productId: doc.id,
                              width: 220,
                              height: 160,
                              showPlaceholder: false,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('ابعاد انتخابی: ${sizeLabel(size)}'),
                              const SizedBox(height: 6),
                              if (height.isNotEmpty)
                                Text('ارتفاع: $height'),
                              if (description.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(description),
                              ],
                              const SizedBox(height: 8),
                              Text('نوع تشک: $type'),
                              Text('مدت ضمانت: $warranty'),
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

// =====================================================
// مدیریت محصولات - فقط مدیر
// =====================================================

class ProductManagementPage extends StatelessWidget {
  const ProductManagementPage({super.key});

  Future<void> openEditor(
    BuildContext context, {
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

  Future<void> deleteProduct(
    BuildContext context,
    String id,
    String name,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف محصول'),
        content: Text(
          'آیا از حذف محصول «$name» مطمئن هستید؟\n'
          'این کار قابل بازگشت نیست.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف محصول'),
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

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('محصول و عکس آن حذف شدند.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در حذف محصول: $e')),
        );
      }
    }
  }

  Future<void> openImageEditor(
    BuildContext context,
    String id,
    String name,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ProductImageEditorDialog(
        productId: id,
        productName: name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (auth.currentUser?.uid != adminUid) {
      return const Center(
        child: Text('دسترسی به این بخش مجاز نیست.'),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'مدیریت محصولات فیدل',
                  style: TextStyle(
                    color: fidelBlue,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => openEditor(context),
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
            child: Text(
              'قیمت و موجودی هر سایز را جداگانه مدیریت کنید.',
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('products').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text('خطا در دریافت محصولات: ${snapshot.error}'),
                );
              }

              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                return const Center(
                  child: Text('هنوز محصولی ثبت نشده است.'),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data();
                  final name = productName(data, doc.id);

                  final category = normalizeCategory(
                    data['category'] ?? data['دسته‌بندی'],
                    doc.id,
                  );

                  final categoryText =
                      category == 'PLUS' ? 'پلاس' : 'اکونومی';

                  final warranty = productField(
                    data,
                    'warranty',
                    'ضمانت',
                    'ثبت نشده',
                  );

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ExpansionTile(
                      leading: ProductImageWidget(
                        productId: doc.id,
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text('$categoryText | ضمانت: $warranty'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'قیمت و موجودی انبار',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: fidelBlue,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...productSizes.map((size) {
                                final price = findPrice(data, size);
                                final quantity = findQuantity(data, size);

                                if (price == null && quantity == null) {
                                  return const SizedBox.shrink();
                                }

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 5,
                                  ),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 75,
                                        child: Text(sizeLabel(size)),
                                      ),
                                      Expanded(
                                        child: Text(
                                          price == null
                                              ? 'قیمت ثبت نشده'
                                              : '${formatPrice(price)} تومان',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Text(
                                        'موجودی: ${quantity == null ? 'ثبت نشده' : readText(quantity)}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              const Divider(),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => openEditor(
                                      context,
                                      id: doc.id,
                                      data: data,
                                    ),
                                    icon: const Icon(Icons.edit),
                                    label: const Text('ویرایش'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => openImageEditor(
                                      context,
                                      doc.id,
                                      name,
                                    ),
                                    icon: const Icon(
                                      Icons.photo_camera_outlined,
                                    ),
                                    label: const Text('مدیریت عکس'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => deleteProduct(
                                      context,
                                      doc.id,
                                      name,
                                    ),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    label: const Text(
                                      'حذف',
                                      style: TextStyle(color: Colors.red),
                                    ),
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

// =====================================================
// فرم افزودن و ویرایش محصول
// =====================================================

class ProductEditorDialog extends StatefulWidget {
  final String? documentId;
  final Map<String, dynamic> initialData;

  const ProductEditorDialog({
    super.key,
    this.documentId,
    required this.initialData,
  });

  @override
  State<ProductEditorDialog> createState() =>
      _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<ProductEditorDialog> {
  final nameController = TextEditingController();
  final warrantyController = TextEditingController();
  final heightController = TextEditingController();
  final typeController = TextEditingController();
  final descriptionController = TextEditingController();

  final Map<int, TextEditingController> priceControllers = {};
  final Map<int, TextEditingController> quantityControllers = {};

  String category = 'ECONOMY';
  bool saving = false;

  @override
  void initState() {
    super.initState();

    final data = widget.initialData;

    nameController.text = productName(
      data,
      widget.documentId ?? '',
    );

    category = normalizeCategory(
      data['category'] ?? data['دسته‌بندی'],
      widget.documentId ?? '',
    );

    if (category.isEmpty) category = 'ECONOMY';

    warrantyController.text = productField(
      data,
      'warranty',
      'ضمانت',
    );

    heightController.text = productField(
      data,
      'height',
      'ارتفاع',
      productField(data, 'thickness', 'ضخامت'),
    );

    typeController.text = productField(
      data,
      'type',
      'نوع',
      productField(data, 'features', 'ویژگی‌ها'),
    );

    descriptionController.text = productField(
      data,
      'description',
      'توضیحات',
    );

    for (final size in productSizes) {
      final price = findPrice(data, size);
      final quantity = findQuantity(data, size);

      priceControllers[size] = TextEditingController(
        text: price == null ? '' : normalizeDigits(price.toString()),
      );

      quantityControllers[size] = TextEditingController(
        text: quantity == null
            ? ''
            : normalizeDigits(quantity.toString()),
      );
    }
  }

  void showMessage(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  Future<void> saveProduct() async {
    if (auth.currentUser?.uid != adminUid) {
      showMessage('دسترسی غیرمجاز است.');
      return;
    }

    final name = nameController.text.trim();

    if (name.isEmpty) {
      showMessage('نام محصول را وارد کنید.');
      return;
    }

    setState(() => saving = true);

    try {
      final Map<String, dynamic> updateData = {
        'name': name,
        'category': category.toLowerCase(),
        'warranty': warrantyController.text.trim(),
        'height': heightController.text.trim(),
        'type': typeController.text.trim(),
        'features': typeController.text.trim(),
        'description': descriptionController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      for (final size in productSizes) {
        final priceText = priceControllers[size]!.text.trim();
        final quantityText = quantityControllers[size]!.text.trim();

        if (priceText.isNotEmpty) {
          final price = parseNumber(priceText);
          if (price == null || price < 0) {
            showMessage('قیمت سایز ${sizeLabel(size)} معتبر نیست.');
            setState(() => saving = false);
            return;
          }
          updateData['price_$size'] = price;
        }

        if (quantityText.isNotEmpty) {
          final quantity = parseNumber(quantityText);
          if (quantity == null || quantity < 0) {
            showMessage('موجودی سایز ${sizeLabel(size)} معتبر نیست.');
            setState(() => saving = false);
            return;
          }
          updateData['quantity_$size'] = quantity;
        }
      }

      final collection = db.collection('products');

      if (widget.documentId == null) {
        updateData['createdAt'] = FieldValue.serverTimestamp();
        await collection.add(updateData);
      } else {
        await collection.doc(widget.documentId).set(
          updateData,
          SetOptions(merge: true),
        );
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              widget.documentId == null
                  ? 'محصول جدید ثبت شد.'
                  : 'اطلاعات محصول ویرایش شد.',
            ),
          ),
        );
      }
    } catch (e) {
      showMessage('ذخیره محصول با خطا روبه‌رو شد: $e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget buildTextField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    warrantyController.dispose();
    heightController.dispose();
    typeController.dispose();
    descriptionController.dispose();

    for (final controller in priceControllers.values) {
      controller.dispose();
    }

    for (final controller in quantityControllers.values) {
      controller.dispose();
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
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.documentId == null
                          ? 'افزودن محصول جدید'
                          : 'ویرایش محصول',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: fidelBlue,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: saving
                        ? null
                        : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  buildTextField(nameController, 'نام محصول'),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: const InputDecoration(
                      labelText: 'گروه محصول',
                      border: OutlineInputBorder(),
                    ),
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
                        : (value) {
                            if (value != null) {
                              setState(() => category = value);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  buildTextField(warrantyController, 'مدت ضمانت'),
                  buildTextField(heightController, 'ارتفاع تشک'),
                  buildTextField(
                    typeController,
                    'نوع ساخت و ویژگی‌ها',
                    maxLines: 2,
                  ),
                  buildTextField(
                    descriptionController,
                    'توضیحات محصول',
                    maxLines: 3,
                  ),
                  const Divider(height: 28),
                  const Text(
                    'قیمت و موجودی هر سایز',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                      color: fidelBlue,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'قیمت‌ها را به تومان وارد کنید. '
                    'موجودی فقط برای مدیر قابل مشاهده است.',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...productSizes.map((size) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'سایز ${sizeLabel(size)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: priceControllers[size],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'قیمت به تومان',
                                hintText: 'مثلاً 22950000',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: quantityControllers[size],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'تعداد موجودی انبار',
                                hintText: 'مثلاً 3',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: saving
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('انصراف'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: saving ? null : saveProduct,
                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save),
                      label: const Text('ذخیره محصول'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// مدیریت شعب و نمایندگی‌ها
// =====================================================

class BranchesPage extends StatelessWidget {
  final bool isAdmin;

  const BranchesPage({super.key, required this.isAdmin});

  Future<void> saveDefaultBranches(BuildContext context) async {
    try {
      for (final branch in defaultBranches) {
        final id = branch['id'] as String;
        final data = Map<String, dynamic>.from(branch);
        data.remove('id');

        await db.collection('branches').doc(id).set(
          data,
          SetOptions(merge: true),
        );
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('اطلاعات اولیه شعب ذخیره شد.'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در ذخیره شعب: $e')),
        );
      }
    }
  }

  Future<void> editBranch(
    BuildContext context, {
    String? id,
    Map<String, dynamic>? oldData,
  }) async {
    final nameController = TextEditingController(
      text: readText(oldData?['name']),
    );
    final addressController = TextEditingController(
      text: readText(oldData?['address']),
    );
    final phonesController = TextEditingController(
      text: (oldData?['phones'] as List? ?? []).join('\n'),
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          id == null ? 'افزودن شعبه یا نمایندگی' : 'ویرایش شعبه',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'نام شعبه یا نمایندگی',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: addressController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'آدرس'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phonesController,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'شماره تماس‌ها (هر شماره در یک خط)',
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

    if (result == true) {
      final name = nameController.text.trim();
      final address = addressController.text.trim();
      final phones = phonesController.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      if (name.isEmpty || address.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('نام و آدرس را وارد کنید.'),
          ),
        );
      } else {
        try {
          final doc = id == null
              ? db.collection('branches').doc()
              : db.collection('branches').doc(id);

          await doc.set({
            'name': name,
            'address': address,
            'phones': phones,
            'active': oldData?['active'] ?? true,
          }, SetOptions(merge: true));

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('اطلاعات ذخیره شد.')),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('خطا در ذخیره: $e')),
            );
          }
        }
      }
    }

    nameController.dispose();
    addressController.dispose();
    phonesController.dispose();
  }

  Future<void> toggleBranch(
    BuildContext context,
    String id,
    bool active,
  ) async {
    try {
      await db.collection('branches').doc(id).update({
        'active': !active,
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در تغییر وضعیت: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('branches').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('خطا در دریافت شعب: ${snapshot.error}'),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'شعب و کارخانه فیدل',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                  color: fidelBlue,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'اطلاعات اولیه شعب در برنامه آماده است. '
                'برای ذخیره و مدیریت آن‌ها در پایگاه داده، مدیر باید '
                'دکمه زیر را بزند.',
              ),
              const SizedBox(height: 14),
              if (isAdmin)
                FilledButton.icon(
                  onPressed: () => saveDefaultBranches(context),
                  icon: const Icon(Icons.save),
                  label: const Text('ثبت شعب اولیه در فایربیس'),
                ),
              const SizedBox(height: 16),
              ...defaultBranches.map(
                (branch) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.store, color: fidelBlue),
                    title: Text(readText(branch['name'])),
                    subtitle: Text(
                      '${branch['address']}\n'
                      '${(branch['phones'] as List).join(' - ')}',
                    ),
                    isThreeLine: true,
                  ),
                ),
              ),
            ],
          );
        }

        final visibleDocs = docs.where((doc) {
          final active = doc.data()['active'] == true;
          return isAdmin || active;
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'شعب و کارخانه فیدل',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: fidelBlue,
              ),
            ),
            if (isAdmin) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => editBranch(context),
                icon: const Icon(Icons.add),
                label: const Text('افزودن شعبه یا نمایندگی'),
              ),
            ],
            const SizedBox(height: 12),
            if (visibleDocs.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('در حال حاضر شعبه فعالی ثبت نشده است.'),
                ),
              ),
            ...visibleDocs.map((doc) {
              final data = doc.data();
              final active = data['active'] == true;
              final phones = (data['phones'] as List? ?? [])
                  .map((e) => e.toString())
                  .join(' - ');

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  leading: Icon(
                    Icons.store,
                    color: active ? fidelBlue : Colors.grey,
                  ),
                  title: Text(
                    readText(data['name']),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    active ? 'فعال' : 'غیرفعال',
                    style: TextStyle(
                      color: active ? Colors.green : Colors.red,
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(readText(data['address'])),
                          const SizedBox(height: 10),
                          Text('شماره تماس: $phones'),
                          if (isAdmin) ...[
                            const Divider(),
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton.icon(
                                  onPressed: () => editBranch(
                                    context,
                                    id: doc.id,
                                    oldData: data,
                                  ),
                                  icon: const Icon(Icons.edit),
                                  label: const Text('ویرایش'),
                                ),
                                TextButton.icon(
                                  onPressed: () => toggleBranch(
                                    context,
                                    doc.id,
                                    active,
                                  ),
                                  icon: Icon(
                                    active
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  label: Text(
                                    active ? 'غیرفعال کردن' : 'فعال کردن',
                                  ),
                                ),
                              ],
                            ),
                          ],
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

// =====================================================
// مشاور هوشمند
// =====================================================

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final controller = TextEditingController();
  final scrollController = ScrollController();

  final messages = <String>[
    'سلام، به مشاور فیدل خوش آمدید 🌹\n'
    'برای شروع، وزن تقریبی استفاده‌کنندگان و ابعاد تشک موردنظر را بگویید.\n'
    'مثلاً: وزن ۸۵ کیلوگرم، تشک ۱۶۰ در ۲۰۰',
  ];

  final answers = <String>[];

  int step = 0;
  int size = 160;
  bool loading = false;

  void addMessage(String value) {
    if (!mounted) return;

    setState(() => messages.add(value));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void detectSize(String value) {
    final text = normalizeDigits(value);

    if (text.contains('70') || text.contains('۷۰')) {
      size = 70;
    } else if (text.contains('80')) {
      size = 80;
    } else if (text.contains('90')) {
      size = 90;
    } else if (text.contains('120')) {
      size = 120;
    } else if (text.contains('140')) {
      size = 140;
    } else if (text.contains('180')) {
      size = 180;
    } else if (text.contains('160')) {
      size = 160;
    }
  }

  String normalizeName(String value) {
    return value
        .toLowerCase()
        .replaceAll('ي', 'ی')
        .replaceAll('ك', 'ک')
        .replaceAll('‌', '')
        .replaceAll(' ', '')
        .replaceAll('-', '')
        .replaceAll('_', '');
  }

  bool isFullMedical(String name) {
    final n = normalizeName(name);

    return n.contains('مدیکال') ||
        n.contains('medical') ||
        n.contains('پلیتاپ') ||
        n.contains('polytop');
  }

  bool isSevereDisc(String value) {
    final text = value.toLowerCase();

    return text.contains('حاد') ||
        text.contains('شدید') ||
        text.contains('فتق دیسک') ||
        text.contains('جراحی دیسک') ||
        text.contains('عمل دیسک') ||
        text.contains('عمل جراحی کمر') ||
        text.contains('بعد از عمل');
  }

  bool hasBackProblem(String value) {
    final text = value.toLowerCase();

    return text.contains('دیسک') ||
        text.contains('سیاتیک') ||
        text.contains('کمردرد') ||
        text.contains('کمر درد') ||
        text.contains('گودی کمر') ||
        text.contains('مهره');
  }

  void send() {
    final value = controller.text.trim();
    if (value.isEmpty || loading) return;

    controller.clear();
    addMessage('شما: $value');

    if (step == 0) {
      answers.add(value);
      detectSize(value);

      addMessage(
        'سؤال دوم: معمولاً به چه حالتی می‌خوابید؟ '
        'به پهلو، به پشت یا روی شکم؟',
      );
      step = 1;
    } else if (step == 1) {
      answers.add(value);
      addMessage('سؤال سوم: تشک را سفت، متوسط یا نرم می‌پسندید؟');
      step = 2;
    } else if (step == 2) {
      answers.add(value);
      addMessage(
        'سؤال چهارم: آیا کمردرد، دیسک کمر، سیاتیک یا مشکل پزشکی دارید؟ '
        'اگر دارید، شدت آن را توضیح دهید.',
      );
      step = 3;
    } else if (step == 3) {
      answers.add(value);
      step = 4;
      recommend();
    } else {
      addMessage('برای مشاوره جدید، صفحه مشاور را دوباره باز کنید.');
    }
  }

  int productScore(
    String name,
    String type,
    String position,
    String firmness,
    bool hasDisc,
  ) {
    int score = 0;

    final n = normalizeName(name);
    final t = normalizeName(type);

    if (n.contains('تاپ') || n.contains('top')) score += 10;
    if (n.contains('المپیک')) score += 10;
    if (n.contains('مدیکال') || n.contains('medical')) score += 12;
    if (n.contains('پلیتاپ') || n.contains('polytop')) score += 10;

    if (firmness.contains('سفت')) {
      if (t.contains('میکرو') || t.contains('بدونفنر')) score += 5;
      if (t.contains('پاکتی')) score -= 5;
    }

    if (firmness.contains('نرم') && t.contains('پاکتی')) {
      score += 5;
    }

    if (position.contains('پهلو')) {
      if (n.contains('آرامش') || n.contains('کلاسیک')) score += 3;
    }

    if (hasDisc && t.contains('پاکتی')) score -= 5;

    return score;
  }

  Future<void> recommend() async {
    if (answers.length < 4) return;

    final weight = answers[0];
    final position = answers[1];
    final firmness = answers[2];
    final health = answers[3];

    final severeDisc = isSevereDisc(health);
    final backProblem = hasBackProblem(health);

    setState(() => loading = true);
    addMessage('در حال بررسی محصولات فیدل و دریافت قیمت‌ها از پایگاه داده...');

    try {
      final snapshot = await db.collection('products').get();

      if (!mounted) return;

      final products = snapshot.docs.map((doc) {
        return {
          'id': doc.id,
          ...doc.data(),
        };
      }).toList();

      if (products.isEmpty) {
        addMessage('در حال حاضر محصولی در پایگاه داده فیدل ثبت نشده است.');
        return;
      }

      final fullMedical = products.where((p) {
        final name = productName(p, readText(p['id']));
        return isFullMedical(name);
      }).toList();

      products.sort((a, b) {
        final nameA = productName(a, readText(a['id']));
        final nameB = productName(b, readText(b['id']));

        final typeA = readText(a['type'], readText(a['features']));
        final typeB = readText(b['type'], readText(b['features']));

        final scoreA = productScore(
          nameA,
          typeA,
          position,
          firmness,
          backProblem,
        );

        final scoreB = productScore(
          nameB,
          typeB,
          position,
          firmness,
          backProblem,
        );

        return scoreB.compareTo(scoreA);
      });

      if (severeDisc && fullMedical.isNotEmpty) {
        products.removeWhere((p) {
          final name = productName(p, readText(p['id']));
          return isFullMedical(name);
        });

        products.insertAll(0, fullMedical);
      }

      final result = StringBuffer();

      result.writeln('نتیجه بررسی پاسخ‌های شما 🌹\n');
      result.writeln('وزن اعلام‌شده: $weight');
      result.writeln('حالت خواب: $position');
      result.writeln('میزان سفتی دلخواه: $firmness');
      result.writeln('وضعیت اعلام‌شده: $health');
      result.writeln('ابعاد انتخابی: ${sizeLabel(size)}\n');

      if (severeDisc) {
        result.writeln(
          'با توجه به اعلام دیسک شدید یا سابقه جراحی، '
          'مدل‌های طبی کامل فیدل در اولویت بررسی قرار می‌گیرند.\n',
        );

        if (fullMedical.isEmpty) {
          result.writeln(
            'در اطلاعات فعلی فایربیس، محصولی با نام مدیکال یا پلی‌تاپ پیدا نشد.\n',
          );
        }
      } else if (backProblem) {
        result.writeln(
          'با توجه به مشکل کمر اعلام‌شده، محصولات با سطح مناسب و '
          'ساختار پشتیبانی‌کننده برای بررسی در اولویت قرار گرفته‌اند.\n',
        );
      }

      result.writeln('محصولات پیشنهادی از کاتالوگ فیدل:\n');

      int shown = 0;

      for (final p in products) {
        if (shown >= 12) break;

        final id = readText(p['id']);
        final name = productName(p, id);
        final warranty = productField(
          p,
          'warranty',
          'ضمانت',
          'ثبت نشده',
        );
        final type = productField(
          p,
          'type',
          'نوع',
          productField(p, 'features', 'ویژگی‌ها', 'ثبت نشده'),
        );

        final price = findPrice(p, size);
        final height = productField(
          p,
          'height',
          'ارتفاع',
          productField(p, 'thickness', 'ضخامت'),
        );

        final description = productField(
          p,
          'description',
          'توضیحات',
        );

        result.writeln('مدل: $name');
        result.writeln('نوع ساخت: $type');
        result.writeln('ضمانت: $warranty');
        result.writeln(
          'قیمت سایز ${sizeLabel(size)}: '
          '${price == null ? 'استعلام' : '${formatPrice(price)} تومان'}',
        );

        if (height.isNotEmpty) result.writeln('ارتفاع: $height');
        if (description.isNotEmpty) {
          result.writeln('توضیحات: $description');
        }

        result.writeln('');
        shown++;
      }

      result.writeln(
        'قیمت‌ها از اطلاعات ثبت‌شده محصولات در فایربیس خوانده شده‌اند. '
        'اگر قیمت سایز انتخابی ثبت نشده باشد، عبارت استعلام نمایش داده می‌شود.\n\n'
        'نکته مهم پزشکی: این مشاوره تشخیص یا درمان پزشکی نیست و '
        'هیچ تشکی درمان دیسک یا کمردرد را تضمین نمی‌کند. '
        'در صورت دیسک شدید، جراحی یا درد منتشرشونده به پا، '
        'انتخاب تشک باید با نظر پزشک معالج انجام شود. '
        'بهتر است پیش از خرید، تشک را حضوری امتحان کنید.',
      );

      addMessage(result.toString());
    } catch (e) {
      addMessage(
        'دریافت اطلاعات محصولات با خطا روبه‌رو شد.\n'
        'لطفاً اتصال اینترنت و دسترسی فایربیس را بررسی کنید.\n$e',
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final isUser = messages[index].startsWith('شما:');

              return Align(
                alignment: isUser
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  constraints: const BoxConstraints(maxWidth: 340),
                  decoration: BoxDecoration(
                    color: isUser
                        ? fidelBlue
                        : const Color(0xFFE8EEF5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    messages[index],
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: !loading,
                    decoration: const InputDecoration(
                      hintText: 'پاسخ خود را بنویسید...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: loading ? null : send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// =====================================================
// سفارش‌ها
// =====================================================

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 65,
              color: fidelBlue,
            ),
            SizedBox(height: 16),
            Text(
              'سفارش‌های من',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'در حال حاضر سفارشی ثبت نشده است.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
