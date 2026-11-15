
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

const String adminUid = 'mbYMqJC4fHUgf1Mf3IhzyEeOa982';

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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF12345A),
        ),
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

// ---------------- ورود و ثبت نام ----------------

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
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
  final confirmController = TextEditingController();

  bool isRegister = false;
  bool loading = false;
  bool obscurePassword = true;

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String authError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'آدرس ایمیل معتبر نیست.';
      case 'user-not-found':
        return 'حساب کاربری با این ایمیل پیدا نشد.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'ایمیل یا رمز عبور اشتباه است.';
      case 'email-already-in-use':
        return 'این ایمیل قبلاً ثبت نام شده است.';
      case 'weak-password':
        return 'رمز عبور باید حداقل ۶ کاراکتر باشد.';
      case 'too-many-requests':
        return 'تعداد تلاش‌ها زیاد است. کمی بعد دوباره امتحان کنید.';
      case 'network-request-failed':
        return 'اتصال اینترنت را بررسی کنید.';
      default:
        return 'خطا: ${e.message ?? e.code}';
    }
  }

  Future<void> submit() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      showMessage('لطفاً ایمیل و رمز عبور را وارد کنید.');
      return;
    }

    if (isRegister && password != confirmController.text) {
      showMessage('تکرار رمز عبور با رمز اصلی یکسان نیست.');
      return;
    }

    if (password.length < 6) {
      showMessage('رمز عبور باید حداقل ۶ کاراکتر باشد.');
      return;
    }

    setState(() => loading = true);

    try {
      if (isRegister) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) showMessage(authError(e));
    } catch (_) {
      if (mounted) showMessage('خطای غیرمنتظره رخ داد.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> resetPassword() async {
    final email = emailController.text.trim();

    if (email.isEmpty) {
      showMessage('ابتدا ایمیل خود را وارد کنید.');
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        showMessage('لینک بازیابی رمز عبور به ایمیل شما ارسال شد.');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) showMessage(authError(e));
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    confirmController.dispose();
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
                        color: Color(0xFF12345A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'فروشگاه تشک فیدل',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF12345A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isRegister ? 'ساخت حساب کاربری' : 'ورود به حساب کاربری',
                      style: const TextStyle(fontSize: 17),
                    ),
                    const SizedBox(height: 25),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'ایمیل',
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
                          onPressed: () {
                            setState(() {
                              obscurePassword = !obscurePassword;
                            });
                          },
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                    ),
                    if (isRegister) ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: confirmController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'تکرار رمز عبور',
                          prefixIcon: Icon(Icons.lock_outline),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: loading ? null : submit,
                        child: loading
                            ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            : Text(isRegister ? 'ثبت نام' : 'ورود'),
                      ),
                    ),
                    if (!isRegister)
                      TextButton(
                        onPressed: resetPassword,
                        child: const Text('فراموشی رمز عبور'),
                      ),
                    const Divider(height: 28),
                    TextButton(
                      onPressed: loading
                          ? null
                          : () {
                              setState(() {
                                isRegister = !isRegister;
                              });
                            },
                      child: Text(
                        isRegister
                            ? 'قبلاً حساب ساخته‌اید؟ ورود'
                            : 'حساب ندارید؟ ثبت نام کنید',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'کیفیت رمز ماندگاریست',
                      style: TextStyle(
                        color: Color(0xFF12345A),
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

// ---------------- اطلاعات مدل‌های تشک برای مشاور ----------------

class Mattress {
  final String name;
  final String warranty;
  final String type;
  final Map<int, double> economy;
  final Map<int, double> plus;

  const Mattress(
    this.name,
    this.warranty,
    this.type,
    this.economy,
    this.plus,
  );

  double? price(String tier, int size) =>
      (tier == 'PLUS' ? plus : economy)[size];
}

const mattresses = <Mattress>[
  Mattress('آسوده', '۲ سال', 'فنر متصل بونل',
      {90:13.95,120:18.3,140:20.7,160:23.2,180:25.5},
      {90:17.8,120:23.1,140:26.8,160:29.5,180:32.3}),
  Mattress('آسایش', '۳ سال', 'فنر متصل بونل',
      {90:17.36,120:23.2,140:27,160:29.26,180:32},
      {90:23.7,120:30.8,140:36.5,160:38.7,180:41.6}),
  Mattress('آرامش', '۴ سال', 'فنر میکرو + پد',
      {90:26.25,120:33.9,140:40.5,160:43.95,180:48.3},
      {90:36.5,120:47.1,140:57.5,160:60.8,180:66.5}),
  Mattress('تاپ', '۵ سال', 'فنر میکرو',
      {90:26.7,120:34.2,140:41,160:44.2,180:48.9},
      {90:36.8,120:48.9,140:54.5,160:63,180:69}),
  Mattress('کلاسیک', '۶ سال', 'فنر میکرو + پد',
      {90:29,120:36.98,140:43.47,160:47.38,180:51.84},
      {90:40.5,120:51.3,140:63.6,160:70,180:74.5}),
  Mattress('المپیک', '۷ سال', 'فنر میکرو',
      {90:29.29,120:39.42,140:45.36,160:49.4,180:54.27},
      {90:43,120:51.9,140:66.5,160:71.5,180:79.9}),
  Mattress('ریلکس', '۸ سال', 'فنر میکرو + پد',
      {90:35.8,120:48.14,140:55.39,160:60,180:65.68},
      {90:46.5,120:61.8,140:73.2,160:79.7,180:87.5}),
  Mattress('آسمان', '۱۰ سال', 'فنر پاکتی + پد',
      {90:52.2,120:64.67,140:74.38,160:84.68,180:93.67},
      {90:69.6,120:84.5,140:99.5,160:113.4,180:124}),
  Mattress('پلی‌تاپ', '۹ سال', 'بدون فنر + پد',
      {90:41,120:51,140:61,160:66.3,180:70.98},
      {90:53.8,120:71.2,140:83.5,160:90.5,180:98.5}),
  Mattress('مدیکال', '۱۵ سال', 'تمام‌اسفنجی + پد',
      {90:58.48,120:71.74,140:87,160:94,180:110.7},
      {90:91.7,120:114,140:133,160:154.7,180:174}),
];

// ---------------- ابزار خواندن اطلاعات Firebase ----------------

String readText(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  if (value is String) return value;
  return value.toString();
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
      id.endsWith('_economy')) {
    return 'ECONOMY';
  }

  return '';
}

dynamic findPrice(Map<String, dynamic> data, int size) {
  final priceValue = data['price'];

  // حالت اول: price به صورت نقشه‌ای از سایزها
  if (priceValue is Map) {
    final value = priceValue[size.toString()] ??
        priceValue['$size'] ??
        priceValue['${size}cm'];
    if (value != null) return value;
  }

  // حالت دوم: قیمت به صورت فیلدهای جداگانه
  final possibleKeys = [
    'price_$size',
    'price$size',
    '${size}_price',
    '${size}cm',
    '$size',
  ];

  for (final key in possibleKeys) {
    if (data[key] != null) return data[key];
  }

  // حالت سوم: قیمت عددی ثابت برای سند
  if (priceValue is num || priceValue is String) {
    return priceValue;
  }

  return null;
}

String formatPrice(dynamic value) {
  if (value == null) return 'استعلام';

  if (value is num) {
    return value.toString();
  }

  return value.toString();
}

String productName(
  Map<String, dynamic> data,
  String documentId,
) {
  final name = readText(data['name']).trim();
  if (name.isNotEmpty) return name;

  return documentId
      .replaceAll('_plus', '')
      .replaceAll('_economy', '');
}

// ---------------- صفحه اصلی ----------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  String tier = 'ECONOMY';
  int size = 160;

  bool get isAdmin =>
      FirebaseAuth.instance.currentUser?.uid == adminUid;

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
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
    final pages = [
      catalog(),
      const AssistantPage(),
      const OrdersPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/logo.png',
              height: 38,
              fit: BoxFit.contain,
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
            tooltip: 'خروج از حساب',
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
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 7,
              ),
              child: const Text(
                'حساب مدیر فیدل',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF12345A),
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
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bed_outlined),
            label: 'محصولات',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: 'مشاور هوشمند',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'سفارش‌ها',
          ),
        ],
      ),
    );
  }

  // کاتالوگ متصل به Firestore
  Widget catalog() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF12345A),
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
                    labelText: 'عرض تشک',
                    border: OutlineInputBorder(),
                  ),
                  items: [90, 120, 140, 160, 180]
                      .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text('$v سانتی‌متر'),
                          ))
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
            stream: FirebaseFirestore.instance
                .collection('products')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'دریافت محصولات با خطا روبه‌رو شد.\n'
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final docs = snapshot.data?.docs ?? [];

              final filtered = docs.where((doc) {
                final data = doc.data();
                return normalizeCategory(
                      data['category'],
                      doc.id,
                    ) ==
                    tier;
              }).toList();

              if (filtered.isEmpty) {
                return const Center(
                  child: Text(
                    'محصولی در این گروه پیدا نشد.',
                    style: TextStyle(fontSize: 16),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final doc = filtered[index];
                  final data = doc.data();

                  final name = productName(data, doc.id);
                  final warranty = readText(
                    data['warranty'],
                    'ثبت نشده',
                  );
                  final type = readText(
                    data['type'],
                    readText(data['features'], 'تشک فیدل'),
                  );
                  final price = findPrice(data, size);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE8EEF5),
                        child: Icon(
                          Icons.bed,
                          color: Color(0xFF12345A),
                        ),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        '$type\nضمانت: $warranty',
                      ),
                      isThreeLine: true,
                      trailing: Text(
                        price == null
                            ? 'استعلام'
                            : '${formatPrice(price)} میلیون',
                        style: const TextStyle(
                          color: Color(0xFF12345A),
                          fontWeight: FontWeight.bold,
                        ),
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

// ---------------- مشاور هوشمند ----------------

class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final controller = TextEditingController();

  final messages = <String>[
    'سلام، به مشاور فیدل خوش آمدید 🌹\n'
    'سؤال اول: تشک را برای یک نفر می‌خواهید یا دونفره؟ وزن تقریبی استفاده‌کنندگان چقدر است؟'
  ];

  final answers = <String>[];
  int step = 0;
  int size = 160;

  void send() {
    final s = controller.text.trim();
    if (s.isEmpty) return;

    setState(() {
      messages.add('شما: $s');
      controller.clear();

      if (step == 0) {
        answers.add(s);

        if (s.contains('۹۰') ||
            s.contains('90') ||
            s.contains('یک نفر') ||
            s.contains('یک‌نفر')) {
          size = 90;
        } else if (s.contains('۱۲۰') || s.contains('120')) {
          size = 120;
        } else if (s.contains('۱۴۰') || s.contains('140')) {
          size = 140;
        } else if (s.contains('۱۸۰') || s.contains('180')) {
          size = 180;
        } else if (s.contains('۱۶۰') || s.contains('160')) {
          size = 160;
        }

        messages.add(
          'سؤال دوم: معمولاً به چه حالتی می‌خوابید؟ '
          'به پهلو، به پشت یا روی شکم؟',
        );
        step++;
      } else if (step == 1) {
        answers.add(s);
        messages.add(
          'سؤال سوم: تشک را سفت، متوسط یا نرم می‌پسندید؟ '
          'آیا کمردرد یا ناراحتی خاصی دارید؟',
        );
        step++;
      } else if (step == 2) {
        answers.add(s);
        step++;
        recommend();
      } else {
        messages.add(
          'برای دریافت پیشنهاد جدید، لطفاً برنامه را دوباره باز کنید.',
        );
      }
    });
  }

  void recommend() {
    final preference = answers[2];
    final soft = preference.contains('نرم');
    final firm = preference.contains('سفت');
    final pain = preference.contains('درد');
    final position = answers[1];

    final candidates = mattresses.where((m) {
      if (soft) {
        return m.name == 'آسمان' ||
            m.name == 'ریلکس' ||
            m.name == 'آرامش';
      }
      if (firm) {
        return m.name == 'المپیک' ||
            m.name == 'تاپ' ||
            m.name == 'آسایش';
      }
      if (pain) {
        return m.name == 'تاپ' ||
            m.name == 'المپیک' ||
            m.name == 'کلاسیک';
      }
      return m.name == 'تاپ' ||
          m.name == 'کلاسیک' ||
          m.name == 'آرامش';
    }).toList();

    final result = StringBuffer(
      'ممنون از پاسخ‌هایتان 🌹\n\n'
      'حالت خواب شما: $position\n'
      'ابعاد انتخاب‌شده: ${size}×200\n\n'
      'با توجه به پاسخ‌ها، این مدل‌ها برای بررسی بیشتر پیشنهاد می‌شوند:\n\n',
    );

    for (final m in candidates.take(3)) {
      final economyPrice = m.price('ECONOMY', size);
      final plusPrice = m.price('PLUS', size);

      result.writeln(
        'مدل ${m.name}\n'
        'نوع ساخت: ${m.type}\n'
        'ضمانت: ${m.warranty}\n'
        'قیمت اکونومی: ${economyPrice ?? 'استعلام'} میلیون تومان\n'
        'قیمت پلاس: ${plusPrice ?? 'استعلام'} میلیون تومان\n',
      );
    }

    result.writeln(
      'این پیشنهاد صرفاً راهنمای اولیه برای انتخاب تشک است '
      'و تشخیص پزشکی محسوب نمی‌شود. بهتر است قبل از خرید، '
      'راحتی تشک را حضوری امتحان کنید.',
    );

    messages.add(result.toString());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, i) {
              final isUser = messages[i].startsWith('شما:');

              return Align(
                alignment: isUser
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  constraints: const BoxConstraints(maxWidth: 320),
                  decoration: BoxDecoration(
                    color: isUser
                        ? const Color(0xFF12345A)
                        : const Color(0xFFE8EEF5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    messages[i],
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: 'پاسخ خود را بنویسید...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: send,
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

// ---------------- سفارش‌ها ----------------

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
              color: Color(0xFF12345A),
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
