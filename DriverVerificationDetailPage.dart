import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;  // ✅ Add this line
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http; // Make sure this import exists

class DriverVerificationDetailPage extends StatefulWidget {
  final String driverId;
  const DriverVerificationDetailPage({super.key, required this.driverId});

  @override
  State<DriverVerificationDetailPage> createState() => _DriverVerificationDetailPageState();
}

class _DriverVerificationDetailPageState extends State<DriverVerificationDetailPage> {
  Map<String, dynamic>? driverData;
  bool isLoading = true;
  final plateNumberController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchDriver();
  }

  String decrypt(String encoded) {
    try {
      final bytes = base64.decode(encoded);
      return utf8.decode(bytes);
    } catch (e) {
      return encoded;
    }
  }

  Future<void> fetchDriver() async {
    final doc = await FirebaseFirestore.instance.collection('drivers').doc(widget.driverId).get();
    if (doc.exists) {
      setState(() {
        driverData = doc.data();
        isLoading = false;
      });
    }
  }
  Future<void> sendFcmNotificationToDriver(String token) async {
    const String serverKey = 'AIzaSyDbrbZ-gaE0qurX1ytiUATTdn4U6q_DtKs';  // 🔥 Your Firebase Cloud Messaging Server key
    final url = Uri.parse('https://fcm.googleapis.com/fcm/send');

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'key=$serverKey',
    };

    final body = jsonEncode({
      'to': token,
      'notification': {
        'title': 'تم قبول الأوراق',
        'body': 'تم قبول الاوراق من قبل تطبيق ابو رقيبة',
        'sound': 'default'
      },
      'priority': 'high'
    });

    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode == 200) {
      debugPrint('✅ FCM sent successfully');
    } else {
      debugPrint('❌ Failed to send FCM: ${response.body}');
    }
  }


  Future<void> approveDriver() async {
    final admin = FirebaseAuth.instance.currentUser;

    await FirebaseFirestore.instance.collection('drivers').doc(widget.driverId).update({
      'active': 1,
      'approval_notification': true,  // 🔔 Triggers local notification on driver’s device
    });

    await FirebaseFirestore.instance.collection('logs').add({
      'action': 'موافقة على الاوراق',
      'driver_id': widget.driverId,
      'admin_uid': admin?.uid,
      'admin_email': admin?.email,
      'timestamp': FieldValue.serverTimestamp(),
    });

    Navigator.pop(context);
  }


  Future<void> rejectDriver() async {
    final controller = TextEditingController();

    // Arabic field labels
    final Map<String, String> fieldLabels = {
      'vehicle_preference': 'الصورة الشخصية',
      'driver_info': 'صورة شخصية',
      'driver_license': 'رخصة القيادة',
      'passport_photo': 'صورة جواز السفر',
      'vehicle_title': 'صورة كتيب السيارة',
      'seats': 'عدد مقاعد الركاب',
      'full_name': 'الاسم بالكامل',
      'vehicle_type': 'نوع السيارة',
      'plate_number': 'رقم الطارقة',
    };

    final Map<String, bool> selectedFields = {
      for (var key in fieldLabels.keys) key: false,
    };

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('رفض السائق'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('اختر الحقول أو الوثائق التي تم رفضها:'),
                ...selectedFields.keys.map((key) => CheckboxListTile(
                  title: Text(fieldLabels[key]!),
                  value: selectedFields[key],
                  onChanged: (value) => setState(() => selectedFields[key] = value ?? false),
                )),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'سبب الرفض'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                final rejected = selectedFields.entries
                    .where((e) => e.value)
                    .map((e) => e.key)
                    .toList();

                if (rejected.isNotEmpty) {
                  final now = DateFormat('dd/MM/yyyy').format(DateTime.now());
                  final admin = FirebaseAuth.instance.currentUser;

                  await FirebaseFirestore.instance.collection('drivers').doc(widget.driverId).update({
                    'rejection': 1,
                    'rejection_reason': controller.text,
                    'rejection_date': now,
                    'rejected_fields': rejected,
                    'active': 0,
                  });

                  await FirebaseFirestore.instance.collection('logs').add({
                    'action': 'رفض اوراق',
                    'driver_id': widget.driverId,
                    'admin_uid': admin?.uid,
                    'admin_email': admin?.email,
                    'timestamp': FieldValue.serverTimestamp(),
                  });

                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Go back
                }
              },
              child: const Text('رفض'),
            ),
          ],
        ),
      ),
    );
  }

  Widget imageRow(String label, String? url, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.blue),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        const SizedBox(height: 4),
        if (url != null && url.isNotEmpty)
          InkWell(
            onTap: () async {
              if (await canLaunchUrlString(url)) {
                await launchUrlString(url, mode: LaunchMode.externalApplication);
              }
            },
            child: Center(
              child: Text('رابط الملف',
                  style: TextStyle(color: Colors.blue, fontSize: 16, decoration: TextDecoration.underline)),
            ),
          )
        else
          const Center(child: Text('لم يتم تحميل الصورة', style: TextStyle(fontSize: 16))),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مراجعة طلب السائق')),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : driverData == null
          ? const Center(child: Text('لا توجد بيانات'))
          : Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Center(child: Text("الاسم: ${driverData!['name'] ?? '-'}", style: TextStyle(fontSize: 18))),
            Center(child: Text("الهاتف: ${decrypt(driverData!['phone'] ?? '')}", style: TextStyle(fontSize: 18))),
            Center(child: Text("كم عدد مقاعد الركاب لديك: ${driverData!['seats'] ?? '-'}", style: TextStyle(fontSize: 18))),
            Center(child: Text("نوع السيارة: ${driverData!['vehicle_type'] ?? '-'}", style: TextStyle(fontSize: 18))),
            Center(child: Text("رقم اللوحة: ${driverData!['plate_number'] ?? '-'}", style: TextStyle(fontSize: 18))),

            if (driverData!['rejection'] == 1) ...[
              const SizedBox(height: 8),
              Center(
                  child: Text("❌ تم رفض هذا السائق",
                      style: TextStyle(fontSize: 18, color: Colors.red))),
              if (driverData!['rejection_date'] != null)
                Center(
                    child: Text("تاريخ الرفض: ${driverData!['rejection_date']}",
                        style: TextStyle(fontSize: 16))),
              if (driverData!['rejection_reason'] != null)
                Center(
                    child: Text("السبب: ${driverData!['rejection_reason']}",
                        style: TextStyle(fontSize: 16))),
            ],
            const SizedBox(height: 20),
            if (driverData!['disabled_status'] == true) ...[
              Center(
                child: Column(
                  children: [
                    const Text("🚫 العضو تم إيقافه",
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red)),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await FirebaseFirestore.instance
                            .collection('drivers')
                            .doc(widget.driverId)
                            .update({'disabled_status': false});

                        await FirebaseFirestore.instance.collection('logs').add({
                          'action': 'اعادة تنشيط العضو',
                          'driver_id': widget.driverId,
                          'admin_uid': FirebaseAuth.instance.currentUser?.uid,
                          'admin_email': FirebaseAuth.instance.currentUser?.email,
                          'timestamp': FieldValue.serverTimestamp(),
                        });
                        await fetchDriver();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text("تنشيط العضو", style: TextStyle(fontSize: 18)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    ),
                  ],
                ),
              ),
            ] else ...[
              imageRow('صورة الرخصة', driverData!['driver_license_url'], Icons.credit_card),
              imageRow('صورة جواز السفر', driverData!['passport_photo_url'], Icons.travel_explore),
              imageRow('صورة ملكية السيارة', driverData!['vehicle_title_url'], Icons.car_rental),
              imageRow(' صورة شخصية', driverData!['driver_info_url'], Icons.person),
              imageRow('تفضيلات السيارة', driverData!['vehicle_preference_url'], Icons.directions_car),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: approveDriver,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text('قبول', style: TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: rejectDriver,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('رفض', style: TextStyle(fontSize: 18)),
                  ),
                ],
              )
            ]
          ],
        ),
      ),
    );
  }
}