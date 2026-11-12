
        } else if (s.contains('۱۸۰') || s.contains('180')) {
          size = 180;
        } else if (s.contains('۱۶۰') || s.contains('160')) {
          size = 160;
        }

        messages.add(
          'سؤال دوم: معمولاً به چه حالتی می‌خوابید؟ '
          'به پهلو، به پشت یا روی شکم؟'
        );
        step++;
      } else if (step == 1) {
        answers.add(s);
        messages.add(
          'سؤال سوم: تشک را سفت، متوسط یا نرم می‌پسندید؟ '
          'آیا کمردرد یا ناراحتی خاصی دارید؟'
        );
        step++;
      } else if (step == 2) {
        answers.add(s);
        step++;
        recommend();
      } else {
        messages.add(
          'برای دریافت پیشنهاد جدید، لطفاً برنامه را دوباره باز کنید.'
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
      'با توجه به پاسخ‌ها، این مدل‌ها برای بررسی بیشتر پیشنهاد می‌شوند:\n\n'
    );

    for (final m in candidates.take(3)) {
      final economyPrice = m.price('ECONOMY', size);
      final plusPrice = m.price('PLUS', size);

      result.writeln(
        'مدل ${m.name}\n'
        'نوع ساخت: ${m.type}\n'
        'ضمانت: ${m.warranty}\n'
        'قیمت اکونومی: ${economyPrice ?? 'استعلام'} میلیون تومان\n'
        'قیمت پلاس: ${plusPrice ?? 'استعلام'} میلیون تومان\n'
      );
    }

    result.writeln(
      'این پیشنهاد صرفاً راهنمای اولیه برای انتخاب تشک است '
      'و تشخیص پزشکی محسوب نمی‌شود. بهتر است قبل از خرید، '
      'راحتی تشک را حضوری امتحان کنید.'
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
