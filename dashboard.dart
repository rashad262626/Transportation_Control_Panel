import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import 'login.dart';
import 'package:aborigba_control_panel/rightmenu.dart';
import 'drivers.dart';
import 'trips.dart';
import 'users.dart';
import 'money.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({Key? key}) : super(key: key);

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int citiesCount = 0;
  int driversCount = 0;
  int totalTrips = 0;
  int completedTrips = 0;
  int canceledTrips = 0;
  int searchingTrips = 0;
  int totalProductivity = 0;
  int usersCount = 0;
  double totalPaidAmount = 0;
  double totalUnpaidAmount = 0;
  int pendingApprovalCount = 0;
  int partialDriversCount = 0;
  DateTime? fromDate;
  DateTime? toDate;
  bool isLoading = false;
  StreamSubscription? driversSub;
  StreamSubscription? tripsSub;
  StreamSubscription? usersSub;
  StreamSubscription? safeLockSub;
  StreamSubscription? citiesSub;
  List<Map<String, dynamic>> flaggedUsers = [];

  @override
  void initState() {
    super.initState();
    _checkCookieAndProceed();
  }
  void dispose() {
    driversSub?.cancel();
    tripsSub?.cancel();
    usersSub?.cancel();
    safeLockSub?.cancel();
    citiesSub?.cancel();
    super.dispose();
  }
  void _checkCookieAndProceed() {
    if (!kIsWeb) {
      setupListeners();
      return;
    }

    final cookies = html.document.cookie?.split(';') ?? [];
    bool hasParillo = cookies.any((c) => c.trim().startsWith('parillo='));

    if (hasParillo) {
      setupListeners();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      });

  }
  }
  String getEmailFromCookie() {
    final cookies = html.document.cookie?.split('; ') ?? [];
    final emailCookie = cookies.firstWhere(
          (c) => c.startsWith('parillo='),
      orElse: () => '',
    ).replaceFirst('parillo=', '');
    return emailCookie;
  }





  void _showFlaggedUsersDialog(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("المستخدمين المحظورين / المحاولات المتكررة"),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isSmallScreen ? screenWidth * 0.95 : 1100,
          ),
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('booking_attempts')
                .where('blockStage', isGreaterThan: 0) // فقط المحظورين
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final users = snapshot.data!.docs;

              if (users.isEmpty) {
                return const Text("لا يوجد مستخدمين محظورين حالياً ✅");
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text("رقم الهاتف")),
                    DataColumn(label: Text("عدد المحاولات")),
                    DataColumn(label: Text("من مدينة")),
                    DataColumn(label: Text("إلى مدينة")),
                    DataColumn(label: Text("مدة الحظر (ثواني)")),
                    DataColumn(label: Text("سبب الحظر")),
                    DataColumn(label: Text("الإجراءات")),
                  ],
                  rows: users.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final phone = data['phone'] ?? doc.id;
                    final tries = data['tries_count'] ?? 0;
                    final fromCity = data['fromCity'] ?? 'غير معروف';
                    final toCity = data['toCity'] ?? 'غير معروف';
                    final duration = data['last_block_duration']?.toString() ?? "0";
                    final reason = data['last_block_reason'] ?? "غير محدد";

                    final email = getEmailFromCookie();
                    String decodedEmail = '';
                    try {
                      decodedEmail = utf8.decode(base64Url.decode(email));
                    } catch (_) {
                      decodedEmail = 'خطأ في قراءة البريد';
                    }

                    return DataRow(cells: [
                      DataCell(Text(phone.toString())),
                      DataCell(Text(tries.toString())),
                      DataCell(Text(fromCity.toString())),
                      DataCell(Text(toCity.toString())),
                      DataCell(Text(duration)),
                      DataCell(Text(reason)),
                      DataCell(Row(
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: () async {
                              await FirebaseFirestore.instance
                                  .collection('booking_attempts')
                                  .doc(doc.id)
                                  .delete();

                              await FirebaseFirestore.instance.collection('logs').add({
                                'action': 'إلغاء الحظر (حذف الوثيقة)',
                                'admin_email': decodedEmail,
                                'driver_id': phone,
                                'timestamp': FieldValue.serverTimestamp(),
                              });
                            },
                            child: const Text("إلغاء الحظر"),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                            onPressed: () async {
                              await FirebaseFirestore.instance
                                  .collection('booking_attempts')
                                  .doc(doc.id)
                                  .delete();

                              await FirebaseFirestore.instance.collection('logs').add({
                                'action': 'تم التعامل معه (حذف الوثيقة)',
                                'admin_email': decodedEmail,
                                'driver_id': phone,
                                'timestamp': FieldValue.serverTimestamp(),
                              });
                            },
                            child: const Text("تم التعامل معه"),
                          ),
                        ],
                      )),
                    ]);
                  }).toList(),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("إغلاق"),
          ),
        ],
      ),
    );
  }

  void setupListeners() {
    final firestore = FirebaseFirestore.instance;
    firestore.collection('booking_attempts')
        .where('flagged', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      setState(() {
        flaggedUsers = snap.docs.map((d) => d.data()).toList();
      });
    });

    // Cities
    citiesSub = firestore.collection('city_coordinates').doc('city_coordinates').snapshots().listen((doc) {
      final cities = (doc.data()?['cities'] as List<dynamic>?) ?? [];
      setState(() => citiesCount = cities.length);
    });

    // Drivers
    driversSub = firestore.collection('drivers').snapshots().listen((snap) {
      final allDrivers = snap.docs.map((d) => d.data()).toList();
      setState(() {
        driversCount = allDrivers.length;

        pendingApprovalCount = 0;
        partialDriversCount = 0;
        for (var driver in allDrivers) {
          final isCompleted = (driver['vehicle_type'] != null &&
              driver['seats'] != null &&
              driver.entries.where((e) => e.key.endsWith('_uploaded') && e.value == true).length == 5);
          final isPartial = !isCompleted &&
              driver.entries.any((e) => e.key.endsWith('_uploaded') && e.value == true);
          final isRejected = (driver['rejection'] ?? 0) == 1;

          if (isCompleted && !(driver['active'] == 1) && !isRejected) {
            pendingApprovalCount++;
          }
          if (isPartial && !isCompleted && !isRejected) {
            partialDriversCount++;
          }
        }
      });
    });

    // Users
    usersSub = firestore.collection('users_users').snapshots().listen((snap) {
      setState(() => usersCount = snap.size);
    });

    // Trips
    tripsSub = firestore.collection('Trip_alerts').snapshots().listen((snap) {
      int total = 0, completed = 0, canceled = 0, searching = 0, productivity = 0;

      for (var doc in snap.docs) {
        final data = doc.data();
        total++;
        final status = data['status'] ?? '';
        final tripCanceled = data['trip_canceled'] ?? false;
        final driverAttached = data['driver_attached'] ?? false;
        final price = int.tryParse('${data['price'] ?? '0'}') ?? 0;

        if (status == 'searching' && !tripCanceled) searching++;
        if (tripCanceled) canceled++;
        if (driverAttached && status != 'canceled') {
          completed++;
          productivity += price;
        }
      }

      setState(() {
        totalTrips = total;
        completedTrips = completed;
        canceledTrips = canceled;
        searchingTrips = searching;
        totalProductivity = productivity;
      });
    });

    // SafeLock
    safeLockSub = firestore.collection('safe_lock').snapshots().listen((snap) {
      double paid = 0, unpaid = 0;
      for (var doc in snap.docs) {
        final d = doc.data();
        final paidField = d['paid'] ?? false;
        final paidCompany = d['paid_company'] ?? false;
        double driverFee = ((d['driver_fee'] ?? 0) as num).toDouble();
        double passengerFee = ((d['passenger_fee'] ?? 0) as num).toDouble() * (d['passengers_reserved'] ?? 1);

        if (paidField && paidCompany) {
          paid += driverFee + passengerFee;
        } else {
          unpaid += driverFee + passengerFee;
        }
      }

      setState(() {
        totalPaidAmount = paid;
        totalUnpaidAmount = unpaid;
      });
    });
  }

  Future<void> fetchAllStatistics() async {

    setState(() => isLoading = true);
    final firestore = FirebaseFirestore.instance;

    try {
      final cityDoc = await firestore.collection('city_coordinates').doc('city_coordinates').get();
      citiesCount = (cityDoc.data()?['cities'] as List<dynamic>?)?.length ?? 0;
    } catch (_) { citiesCount = 0; }

    try {
      final driverQuery = await firestore.collection('drivers').get();
      driversCount = driverQuery.size;
    } catch (_) { driversCount = 0; }

    try {
      final userQuery = await firestore.collection('users_users').get();
      usersCount = userQuery.size;
    } catch (_) { usersCount = 0; }

    totalTrips = 0; completedTrips = 0; canceledTrips = 0; searchingTrips = 0; totalProductivity = 0;
    totalPaidAmount = 0; totalUnpaidAmount = 0;

    try {
      Query tripQuery = firestore.collection('Trip_alerts');
      if (fromDate != null && toDate != null) {
        tripQuery = tripQuery
            .where('createdAt', isGreaterThanOrEqualTo: fromDate)
            .where('createdAt', isLessThanOrEqualTo: toDate!.add(const Duration(days: 1)));
      }
      final tripSnapshot = await tripQuery.get();
      totalTrips = tripSnapshot.size;

      for (var doc in tripSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        final status = data['status'] ?? '';
        final tripCanceled = data['trip_canceled'] ?? false;
        final driverAttached = data['driver_attached'] ?? false;
        final price = int.tryParse('${data['price'] ?? '0'}') ?? 0;

        if (status == 'searching' && !tripCanceled) searchingTrips++;
        if (tripCanceled) canceledTrips++;
        if (driverAttached && status != 'canceled') {
          completedTrips++;
          totalProductivity += price;
        }
      }
    } catch (_) {}

    try {
      final paidSnap = await firestore.collection('safe_lock')
          .where('paid', isEqualTo: true)
          .where('paid_company', isEqualTo: true)
          .get();

      for (var doc in paidSnap.docs) {
        final d = doc.data();
        totalPaidAmount += ((d['driver_fee'] ?? 0) as num).toDouble();
        totalPaidAmount += ((d['passenger_fee'] ?? 0) as num).toDouble() * (d['passengers_reserved'] ?? 1);
      }
    } catch (_) {}

    try {
      final unpaidSnap = await firestore.collection('safe_lock').get();
      for (var doc in unpaidSnap.docs) {
        final d = doc.data();
        final paid = d['paid'] ?? false;
        final paidCompany = d['paid_company'] ?? false;
        if (!paid && !paidCompany) {
          totalUnpaidAmount += ((d['driver_fee'] ?? 0) as num).toDouble();
          totalUnpaidAmount += ((d['passenger_fee'] ?? 0) as num).toDouble() * (d['passengers_reserved'] ?? 1);
        }
      }
    } catch (_) {}

    try{
      int pendingApprovalCount = 0;
      int partialDriversCount = 0;

      final driversSnapshot = await firestore.collection('drivers').get();

      for (var doc in driversSnapshot.docs) {
        final driver = doc.data();

        final isCompleted = (driver['vehicle_type'] != null &&
            driver['seats'] != null &&
            driver.entries.where((e) => e.key.endsWith('_uploaded') && e.value == true).length == 5);
        final isPartial = !isCompleted &&
            driver.entries.any((e) => e.key.endsWith('_uploaded') && e.value == true);
        final isRejected = (driver['rejection'] ?? 0) == 1;

        if (isCompleted && !(driver['active'] == 1) && !isRejected) {
          pendingApprovalCount++;
        }

        if (isPartial && !isCompleted && !isRejected) {
          partialDriversCount++;
        }
      }

    } catch (_) {}
    setState(() => isLoading = false);
  }

  Future<void> pickFromDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: fromDate ?? DateTime.now().subtract(const Duration(days: 7)),
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now(),
      locale: const Locale('ar', ''),
    );
    if (picked != null) setState(() => fromDate = picked);
  }

  Future<void> pickToDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: toDate ?? DateTime.now(),
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('ar', ''),
    );
    if (picked != null) setState(() => toDate = picked);
  }

  void onFilter() async => await fetchAllStatistics();
  void onClearFilter() async {
    setState(() { fromDate = null; toDate = null; });
    await fetchAllStatistics();
  }

  Widget _linkStatCard({required String title, required String value, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: StatCard(title: title, value: value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  Card(
                    elevation: 1.5,
                    child: Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.calendar_today, size: 20, color: Colors.blue),
                              SizedBox(width: 8),
                              Text('فلترة بين تاريخين', style: TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.date_range),
                                label: Text(fromDate != null ? DateFormat('yyyy-MM-dd').format(fromDate!) : "من تاريخ"),
                                onPressed: () => pickFromDate(context),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                icon: const Icon(Icons.date_range),
                                label: Text(toDate != null ? DateFormat('yyyy-MM-dd').format(toDate!) : "إلى تاريخ"),
                                onPressed: () => pickToDate(context),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(onPressed: isLoading ? null : onFilter, child: const Text("بحث")),
                              if (fromDate != null || toDate != null)
                                TextButton(onPressed: isLoading ? null : onClearFilter, child: const Text("مسح")),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 18, runSpacing: 18,
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DriversPage()));
                        },
                        child: StatCard(title: "عدد السائقين", value: "$driversCount"),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const UsersPage()));
                        },
                        child: StatCard(title: "عدد الزبائن", value: "$usersCount"),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TripsManagementPage()));
                        },
                        child: StatCard(title: "عدد الرحلات الكلي", value: "$totalTrips"),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TripsManagementPage()));
                        },
                        child: StatCard(title: "الرحلات المكتملة", value: "$completedTrips"),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const TripsManagementPage(initialTabIndex: 4), // 4 = index for "ملغية"
                            ),
                          );
                        },
                        child: StatCard(title: "الرحلات الملغية", value: "$canceledTrips"),
                      ),

                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const TripsManagementPage()));
                        },
                        child: StatCard(title: "رحلات قيد البحث", value: "$searchingTrips"),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ControlPanelPage()));
                        },
                        child: StatCard(title: "إجمالي الإنتاجية", value: "$totalProductivity د.ل"),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ControlPanelPage()));
                        },
                        child: StatCard(title: "إجمالي المال المدفوع", value: "${totalPaidAmount.toStringAsFixed(2)} د.ل"),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ControlPanelPage()));
                        },
                        child: StatCard(title: "إجمالي المال غير المدفوع", value: "${totalUnpaidAmount.toStringAsFixed(2)} د.ل"),
                      ),GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => DriversPage(initialTabIndex: 2)), // مكتملون في انتظار الموافقة
                          );
                        },
                        child: StatCard(title: " في انتظار قبول الاوراق", value: "$pendingApprovalCount"),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => DriversPage(initialTabIndex: 3)), // بدأوا ولم يكملوا
                          );
                        },
                        child: StatCard(title: "بدأوا ولم يكملوا", value: "$partialDriversCount"),
                      ),
                      GestureDetector(
                        onTap: () {
                          _showFlaggedUsersDialog(context);
                        },
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('booking_attempts')
                              .where('blockStage', isGreaterThan: 0) // فقط المحظورين
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const StatCard(title: "اكثر من خمس مرات", value: "0");
                            }

                            final blockedUsers = snapshot.data!.docs;
                            final count = blockedUsers.length;

                            return StatCard(
                              title: "اكثر من خمس مرات",
                              value: "$count",
                            );
                          },
                        ),
                      ),


                    ],
                  ),
                  if (isLoading) const Padding(padding: EdgeInsets.all(18), child: CircularProgressIndicator()),
                ],
              ),
            ),
          ),
          Container(width: 250, color: Colors.white, padding: const EdgeInsets.symmetric(vertical: 20), child: const RightMenu()),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  const StatCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210, height: 110, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 7),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

}
