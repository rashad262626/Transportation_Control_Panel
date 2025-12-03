import 'dart:convert';
import 'package:aborigba_control_panel/pay_det.dart';
import 'package:aborigba_control_panel/rec.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:aborigba_control_panel/rightmenu.dart';
import 'dart:html' as html; // Add at the top of your file if not imported

class ControlPanelPage extends StatefulWidget {
  const ControlPanelPage({super.key});

  @override
  State<ControlPanelPage> createState() => _ControlPanelPageState();
}

class _ControlPanelPageState extends State<ControlPanelPage> {
  int activeTabIndex = 0;
  bool isLoading = true;
  final TextEditingController searchController = TextEditingController();
  DateTime? startDate;
  DateTime? endDate;
  List<Map<String, dynamic>> allDrivers = [];
  List<Map<String, dynamic>> driversWithDebt = [];
  List<Map<String, dynamic>> driversWithoutDebt = [];

  Map<String, dynamic>? selectedDriver;
  Map<String, dynamic>? driverStats;

  final List<String> tabs = ['كل السائقين', 'السائقين الذين لم يدفعوا', 'السائقين الذين دفعوا'];

  @override
  void initState() {
    super.initState();
    fetchDrivers();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  String decrypt(String encoded) {
    try {
      final bytes = base64.decode(encoded);
      return utf8.decode(bytes);
    } catch (_) {
      return encoded;
    }
  }

  Future<void> fetchDrivers() async {
    setState(() {
      isLoading = true;
      allDrivers.clear();
      driversWithDebt.clear();
      driversWithoutDebt.clear();
    });

    final snapshot = await FirebaseFirestore.instance.collection('drivers').get();

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final decryptedPhone = decrypt(data['phone'] ?? '');
      final encodedPhone = base64.encode(utf8.encode(decryptedPhone));

      final safeSnap = await FirebaseFirestore.instance
          .collection('safe_lock')
          .where('driver_phone', isEqualTo: encodedPhone)
          .get();

      bool hasUnpaid = false;
      bool hasAnyTrip = safeSnap.docs.isNotEmpty;
      DateTime? lastPaymentDate;
      for (final trip in safeSnap.docs) {
        final d = trip.data();
        if (d['paid'] == true && d['date_payment'] != null) {
          final date = (d['date_payment'] as Timestamp).toDate();
          if (lastPaymentDate == null || date.isAfter(lastPaymentDate)) {
            lastPaymentDate = date;
          }
        }
      }

      final driverEntry = {
        'uid': data['uid'] ?? '',
        'name': data['full_name'] ?? '',
        'phone': decryptedPhone,
        'max': data['max'] ?? 0,
        'docId': doc.id,
        'lastPaymentDate': lastPaymentDate,  // 👈 store this for filtering
      };

      if (hasAnyTrip) {
        if (hasUnpaid) {
          driversWithDebt.add(driverEntry);
        } else {
          driversWithoutDebt.add(driverEntry);
        }
      }
      allDrivers.add(driverEntry);
    }

    setState(() {
      isLoading = false;
    });
  }

  Future<Map<String, dynamic>> calculateDebt(String plainPhone) async {
    final encodedPhone = base64.encode(utf8.encode(plainPhone));
    final snap = await FirebaseFirestore.instance
        .collection('safe_lock')
        .where('driver_phone', isEqualTo: encodedPhone)
        .get();

    int unpaidTrips = 0;
    double unpaidRevenue = 0, unpaidDriverFee = 0, unpaidPassengerFee = 0;
    double totalRevenue = 0, totalDriverFee = 0, totalPassengerFee = 0;
    double overallPaid = 0;

    for (var doc in snap.docs) {
      final d = doc.data();
      final revenue = (d['trip_revenue'] ?? 0).toDouble();
      final driverFee = (d['driver_fee'] ?? 0).toDouble();
      final passengerFee = (d['passenger_fee'] ?? 0).toDouble() * (d['passengers_reserved'] ?? 1);
      final paid = d['paid'] ?? false;

      totalRevenue += revenue;
      totalDriverFee += driverFee;
      totalPassengerFee += passengerFee;

      if (!paid) {
        unpaidTrips++;
        unpaidRevenue += revenue;
        unpaidDriverFee += driverFee;
        unpaidPassengerFee += passengerFee;
      } else {
        overallPaid += driverFee + passengerFee;
      }
    }

    double expectedTotal = unpaidDriverFee + unpaidPassengerFee;

    return {
      'unpaidTrips': unpaidTrips,
      'unpaidRevenue': unpaidRevenue,
      'unpaidDriverFee': unpaidDriverFee,
      'unpaidPassengerFee': unpaidPassengerFee,
      'totalRevenue': totalRevenue,
      'totalDriverFee': totalDriverFee,
      'totalPassengerFee': totalPassengerFee,
      'expectedTotal': expectedTotal,
      'overallPaid': overallPaid,
    };
  }

  void showDriverDetails(Map<String, dynamic> driver) async {
    final stats = await calculateDebt(driver['phone']);
    setState(() {
      selectedDriver = driver;
      driverStats = stats;
    });
    await fetchDriverStats(driver['phone']); // 👈 this loads wallet + gift card
  }

  Future<void> fetchDriverStats(String phone) async {
    final encodedPhone = base64.encode(utf8.encode(phone));

    // 1️⃣ Get driver document
    final driverSnap = await FirebaseFirestore.instance
        .collection('drivers')
        .where('phone', isEqualTo: encodedPhone)
        .limit(1)
        .get();

    double wallet = 0;
    if (driverSnap.docs.isNotEmpty) {
      wallet = (driverSnap.docs.first.data()['wallet'] ?? 0).toDouble();
    }

    // 2️⃣ Get total paid by gift cards
    final giftCardSnap = await FirebaseFirestore.instance
        .collection('safe_lock')
        .where('driver_phone', isEqualTo: encodedPhone)
        .where('payment_method', isEqualTo: 'gift_card')
        .get();

    double giftCardTotal = 0;
    for (final doc in giftCardSnap.docs) {
      final d = doc.data();
      final driverFee = (d['driver_fee'] ?? 0).toDouble();
      final passengerFee = ((d['passenger_fee'] ?? 0).toDouble()) *
          (d['passengers_reserved'] ?? 1);
      giftCardTotal += driverFee + passengerFee;
    }

    // 3️⃣ Add wallet & gift card totals to driverStats map
    driverStats = {
      ...driverStats ?? {},
      'wallet': wallet,
      'giftCardPaid': giftCardTotal,
    };

    setState(() {});
  }

  void closeAccount(Map<String, dynamic> driver) async {
    final now = DateTime.now();

    // 👇 Read admin_email from cookies
    String adminEmail = '';
    final cookies = html.document.cookie?.split(';') ?? [];
    for (var cookie in cookies) {
      cookie = cookie.trim();
      if (cookie.startsWith('parillo=')) {
        final encoded = cookie.substring('parillo='.length);
        try {
          adminEmail = utf8.decode(base64Url.decode(encoded));
        } catch (_) {}
        break;
      }
    }

    // 👇 Encode phone
    final encodedPhone = base64.encode(utf8.encode(driver['phone']));

    // 👇 Get driver's wallet
    final driverQuery = await FirebaseFirestore.instance
        .collection('drivers')
        .where('phone', isEqualTo: encodedPhone)
        .limit(1)
        .get();

    double wallet = 0;
    if (driverQuery.docs.isNotEmpty) {
      wallet = (driverQuery.docs.first.data()['wallet'] ?? 0).toDouble();
    }

    // 👇 Total money received = wallet (negative wallet treated as positive)
    double moneyReceived = wallet.abs();
    await FirebaseFirestore.instance.collection('cash').add({
      'uid': driver['uid'],
      'driver_name': driver['name'],
      'driver_phone': driver['phone'],
      'money_received': moneyReceived,
      'wallet_before_reset': wallet,
      'timestamp': FieldValue.serverTimestamp(),
      'admin_email': adminEmail,
      'action': 'تصكير حساب',
    });

    // 👇 Log account closure
    await FirebaseFirestore.instance.collection('logs').add({
      'uid': driver['uid'],
      'email': driver['phone'],
      'action': 'تصكير حساب',
      'timestamp': FieldValue.serverTimestamp(),
      'admin_email': adminEmail,
      'money_recived': moneyReceived,
      'wallet_before_reset': wallet,
    });

    // 👇 Update safe_lock records (mark as paid, only using wallet for moneyReceived)
    final snap = await FirebaseFirestore.instance
        .collection('safe_lock')
        .where('driver_phone', isEqualTo: encodedPhone)
        .get();

    for (final doc in snap.docs) {
      final d = doc.data();
      if (!(d['paid'] ?? false)) {
        await doc.reference.update({
          'paid_company': true,
          'paid': true,
          'date_payment': Timestamp.fromDate(now),
          'admin_email': adminEmail,
          'money_recived': moneyReceived,
        });
      }
    }

    // 👇 Reset wallet to 0
    if (driverQuery.docs.isNotEmpty) {
      final driverDoc = driverQuery.docs.first.reference;
      await driverDoc.update({'wallet': 0});
    }

    // 👇 UI updates
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم تصكير الحساب')),
    );

    setState(() {
      selectedDriver = null;
      driverStats = null;
    });

    await fetchDrivers();

    // 👇 Show receipt
    if (driverStats != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReceiptPage(
            driver: driver,
            stats: driverStats!,
            paymentDate: now,
          ),
        ),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    final query = searchController.text.trim().toLowerCase();

    final displayedDrivers = (activeTabIndex == 0)
        ? allDrivers
        : (activeTabIndex == 1)
        ? driversWithDebt
        : driversWithoutDebt;

    final filteredDrivers = displayedDrivers.where((driver) {
      final name = driver['name'].toString().toLowerCase();
      final phone = driver['phone'].toString();
      final query = searchController.text.trim().toLowerCase();

      bool matchesSearch = query.isEmpty || name.contains(query) || phone.contains(query);

      if (!matchesSearch) return false;

      bool matchesDate = true;
      if (startDate != null && endDate != null) {
        if (driver['lastPaymentDate'] == null) return false;
        final d = driver['lastPaymentDate'] as DateTime;
        matchesDate = d.isAfter(startDate!.subtract(const Duration(days: 1))) &&
            d.isBefore(endDate!.add(const Duration(days: 1)));
      } else if (startDate != null) {
        if (driver['lastPaymentDate'] == null) return false;
        final d = driver['lastPaymentDate'] as DateTime;
        matchesDate = d.year == startDate!.year &&
            d.month == startDate!.month &&
            d.day == startDate!.day;
      }

      return matchesSearch && matchesDate;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setState(() => startDate = picked);
                          }
                        },
                        icon: const Icon(Icons.date_range),
                        label: Text(startDate != null
                            ? 'من: ${startDate!.toLocal().toString().split(' ')[0]}'
                            : 'اختر تاريخ من'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setState(() => endDate = picked);
                          }
                        },
                        icon: const Icon(Icons.date_range),
                        label: Text(endDate != null
                            ? 'إلى: ${endDate!.toLocal().toString().split(' ')[0]}'
                            : 'اختر تاريخ إلى'),
                      ),
                      const SizedBox(width: 8),
                      if (startDate != null || endDate != null)
                        IconButton(
                          onPressed: () {
                            setState(() {
                              startDate = null;
                              endDate = null;
                            });
                          },
                          icon: const Icon(Icons.clear),
                          tooltip: 'مسح التواريخ',
                        ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  Row(
                    children: List.generate(
                      tabs.length,
                          (i) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: TabButton(
                          selected: activeTabIndex == i,
                          text: tabs[i],
                          onTap: () => setState(() => activeTabIndex = i),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'بحث بالاسم أو رقم الهاتف',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                      itemCount: filteredDrivers.length,
                      itemBuilder: (context, i) {
                        final d = filteredDrivers[i];
                        return Card(
                          child: ListTile(
                            title: Text('${d['name']} - ${d['phone']}'),
                            subtitle: Text('حد أقصى: ${d['max']} د.ل'),
                            onTap: () => showDriverDetails(d),
                          ),
                        );
                      },
                    ),

                  ),

                ],
              ),
            ),
          ),
          if (selectedDriver != null && driverStats != null)
            Container(
              width: 350,
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatCard(
                      title: 'عدد الرحلات غير المدفوعة',
                      value: '${driverStats!['unpaidTrips'] ?? 0}',
                    ),
                    StatCard(
                      title: 'الدخل',
                      value: '${(driverStats!['unpaidRevenue'] ?? 0).toStringAsFixed(2)} د.ل',
                    ),
                    StatCard(
                      title: 'رسوم السائق غير المدفوعة',
                      value: '${(driverStats!['unpaidDriverFee'] ?? 0).toStringAsFixed(2)} د.ل',
                    ),
                    StatCard(
                      title: 'رسوم الركاب غير المدفوعة',
                      value: '${(driverStats!['unpaidPassengerFee'] ?? 0).toStringAsFixed(2)} د.ل',
                    ),StatCard(
                      title: 'المبلغ المفترض دفعه للشركة',
                      value: () {
                        final wallet = (driverStats!['wallet'] ?? 0).toDouble();
                        // expectedTotal should match wallet if negative, or be 0 if positive
                        final expected = wallet < 0 ? wallet : 0;
                        return '${expected.toStringAsFixed(2)} د.ل';
                      }(),
                    ),

                    const Divider(),

                    // 🧾 Total stats section
                    StatCard(
                      title: 'إجمالي الدخل الكلي',
                      value: '${(driverStats!['totalRevenue'] ?? 0).toStringAsFixed(2)} د.ل',
                    ),
                    StatCard(
                      title: 'إجمالي رسوم السائق',
                      value: '${(driverStats!['totalDriverFee'] ?? 0).toStringAsFixed(2)} د.ل',
                    ),
                    StatCard(
                      title: 'إجمالي رسوم الركاب',
                      value: '${(driverStats!['totalPassengerFee'] ?? 0).toStringAsFixed(2)} د.ل',
                    ),

                    // 🪙 Wallet + Gift Card info
                    StatCard(
                      title: 'رصيد المحفظة الحالي',
                      value: '${(driverStats!['wallet'] ?? 0).toStringAsFixed(2)} د.ل',
                    ),
                    StatCard(
                      title: 'المدفوع عبر بطاقات الهدايا',
                      value: '${(driverStats!['giftCardPaid'] ?? 0).toStringAsFixed(2)} د.ل',
                    ),

                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: StatCard(
                            title: 'إجمالي ما دفعه السائق',
                            value: '${(driverStats!['overallPaid'] ?? 0).toStringAsFixed(2)} د.ل',
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DriverPaymentsPage(
                                driverPhone: selectedDriver!['phone'],
                              ),
                            ),
                          ),
                          child: const Text('الدفعات', style: TextStyle(color: Colors.blue)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    ElevatedButton(
                      onPressed: () => closeAccount(selectedDriver!),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text(
                        'تصكير حساب',
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Container(
            width: 250,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: const RightMenu(),
          ),
        ],
      ),
    );
  }
}

class TabButton extends StatelessWidget {
  final bool selected;
  final String text;
  final VoidCallback onTap;
  const TabButton({
    super.key,
    required this.selected,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? Colors.blue : Colors.grey[200],
        foregroundColor: selected ? Colors.white : Colors.black,
      ),
      onPressed: onTap,
      child: Text(text),
    );
  }
}

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  const StatCard({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 14)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
