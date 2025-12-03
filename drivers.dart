import 'dart:convert';

import 'package:aborigba_control_panel/adddriver.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:aborigba_control_panel/rightmenu.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'DriverVerificationDetailPage.dart';

class DriversPage extends StatefulWidget {
  final int? initialTabIndex;
  const DriversPage({Key? key, this.initialTabIndex}) : super(key: key);

  @override
  State<DriversPage> createState() => _DriversPageState();
}


class _DriversPageState extends State<DriversPage> {
  int activeTabIndex = 0;
  String searchQuery = '';
  List<Map<String, dynamic>> allDrivers = [];
  List<Map<String, dynamic>> filteredDrivers = [];
  bool isLoading = true;
  final searchDateController = TextEditingController(text: 'أدخل التاريخ');
  DateTime? selectedDate;

  @override
  void initState() {
    super.initState();
    if (widget.initialTabIndex != null) {
      activeTabIndex = widget.initialTabIndex!;
    }
    fetchDrivers();
  }

  Future<void> fetchDrivers() async {
    setState(() => isLoading = true);
    final querySnapshot = await FirebaseFirestore.instance.collection('drivers').get();
    allDrivers = querySnapshot.docs.map((doc) {
      final data = doc.data();
      return {
        ...data,
        'id': doc.id,
      };
    }).toList();
    applyFilters();
    setState(() => isLoading = false);
  }

  void applyFilters() {
    setState(() {
      filteredDrivers = allDrivers.where((driver) {
        final name = driver['name']?.toString() ?? '';
        final phone = driver['phone']?.toString() ?? '';
        final decryptedPhone = decrypt(phone);
        final createdAt = driver['createdAt']?.toString() ?? '';
        final submissionDate = driver['submission_date']?.toString() ?? '';
        final searchDate = selectedDate != null ? DateFormat('dd/MM/yyyy').format(selectedDate!) : '';

        final matchesSearch =
            (searchQuery.isEmpty ||
                name.contains(searchQuery) ||
                decryptedPhone.contains(searchQuery)) &&
                (
                    searchDate.isEmpty ||
                        _formatDate(driver['createdAt']) == searchDate ||
                        submissionDate == searchDate
                );

        if (activeTabIndex == -1) return matchesSearch;

        final isActive = (driver['active'] ?? 0) == 1;
        final isCompleted = (driver['vehicle_type'] != null &&
            driver['seats'] != null &&
            driver.entries.where((e) => e.key.endsWith('_uploaded') && e.value == true).length == 5);
        final isPartial = !isCompleted &&
            driver.entries.any((e) => e.key.endsWith('_uploaded') && e.value == true);
        final isRejected = (driver['rejection'] ?? 0) == 1 && (driver['active'] ?? 0) == 0;
        final isKicked = isRejected && (driver['disable_note'] != null && driver['disable_note'].toString().isNotEmpty);

        bool matchesTab = false;
        if (activeTabIndex == 0) matchesTab = isActive;
        else if (activeTabIndex == 1) matchesTab = !isActive && !isRejected;
        else if (activeTabIndex == 2) matchesTab = isCompleted && !isActive && !isRejected;
        else if (activeTabIndex == 3) matchesTab = isPartial && !isCompleted && !isRejected;
        else if (activeTabIndex == 4) matchesTab = isRejected && !isKicked;
        else if (activeTabIndex == 5) matchesTab = isKicked;

        return matchesTab && matchesSearch;
      }).toList();
    });
  }

  void onSearch(String value) {
    searchQuery = value.trim();
    applyFilters();
  }

  String decrypt(String encoded) {
    try {
      final bytes = base64.decode(encoded);
      return utf8.decode(bytes);
    } catch (e) {
      return encoded;
    }
  }

  void onTabChange(int index) {
    activeTabIndex = index;
    applyFilters();
  }

  void showAddDriverDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('إضافة سائق جديد'),
          content: const AddDriverPage(),
          actions: [
            TextButton(child: const Text('إلغاء'), onPressed: () => Navigator.pop(context)),
            ElevatedButton(child: const Text('إضافة'), onPressed: () => Navigator.pop(context)),
          ],
        );
      },
    );
  }

  void deactivateDriver(String docId) async {
    final controller = TextEditingController();
    await showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('تعطيل - طرد العضو'),
        content: CupertinoTextField(
          controller: controller,
          placeholder: 'أدخل ملاحظة التعطيل',
          maxLines: 3,
        ),
        actions: [
          CupertinoDialogAction(child: const Text('إلغاء'), onPressed: () => Navigator.pop(context)),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('تأكيد'),
            onPressed: () async {
              await FirebaseFirestore.instance.collection('drivers').doc(docId).update({
                'active': 0,
                'rejection': 1,
                'disable_note': controller.text,
                'disabled_status': true, // 👈 تم الإضافة هنا
              });
              final admin = FirebaseAuth.instance.currentUser;
              final docSnap = await FirebaseFirestore.instance.collection('drivers').doc(docId).get();
              final data = docSnap.data();
              final decryptedPhone = decrypt(data?['phone'] ?? '');
              final before = data?['before'];
              final after = data?['after'];
              final max = data?['max'];

              await FirebaseFirestore.instance.collection('logs').add({
                'action': 'disable',
                'driver_id': docId,
                'admin_uid': admin?.uid,
                'admin_email': admin?.email,
                'note': controller.text,
                'phone': decryptedPhone,
                'before': before,
                'after': after,
                'max': max,
                'timestamp': FieldValue.serverTimestamp(),
              });


              Navigator.pop(context);
              fetchDrivers();
            },
          ),
        ],
      ),
    );
  }

  void openDriverDetailPage(String driverId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DriverVerificationDetailPage(driverId: driverId),
      ),
    ).then((_) => fetchDrivers());
  }
  String _formatDate(dynamic date) {
    try {
      if (date is Timestamp) {
        return DateFormat('dd/MM/yyyy').format(date.toDate());
      } else if (date is String) {
        final parsed = DateTime.tryParse(date);
        if (parsed != null) {
          return DateFormat('dd/MM/yyyy').format(parsed);
        }
      }
    } catch (e) {}
    return '-';
  }

  void editMax(Map<String, dynamic> driver) async {
    final controller = TextEditingController(text: '${driver['max'] ?? ''}');
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تغيير الحد الاقصى'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'أدخل الحد الأقصى الجديد'),
          ),
          actions: [
            TextButton(
              child: const Text('إلغاء'),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              child: const Text('حفظ'),
              onPressed: () async {
                final newMax = int.tryParse(controller.text.trim());
                if (newMax != null) {
                  final docRef = FirebaseFirestore.instance.collection('drivers').doc(driver['id']);
                  final snapshot = await docRef.get();
                  final oldMax = snapshot.data()?['max'];
                  final admin = FirebaseAuth.instance.currentUser;

                  await docRef.update({'max': newMax});
                  await FirebaseFirestore.instance.collection('logs').add({
                    'action': 'تغيير الحد الاقصى',
                    'driver_id': driver['id'],
                    'admin_uid': admin?.uid,
                    'admin_email': admin?.email,
                    'old_max': oldMax,
                    'new_max': newMax,
                    'timestamp': FieldValue.serverTimestamp(),
                  });

                  Navigator.pop(context);
                  fetchDrivers();
                }
              },
            ),
          ],
        );
      },
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
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'بحث بالاسم أو الهاتف  ',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: onSearch,
                        ),
                      ),const SizedBox(width: 16),
                      SizedBox(
                        width: 180,
                        child: GestureDetector(
                          onTap: () async {
                            DateTime now = DateTime.now();
                            final DateTime? picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate ?? now,
                              firstDate: DateTime(2023),
                              lastDate: DateTime(now.year + 1),
                              locale: const Locale("ar", "LY"),
                            );
                            if (picked != null) {
                              setState(() {
                                selectedDate = picked;
                                searchDateController.text = DateFormat('dd/MM/yyyy').format(picked);
                                applyFilters();
                              });
                            }
                          },
                          child: AbsorbPointer(
                            child: TextField(
                              controller: searchDateController,
                              decoration: const InputDecoration(
                                hintText: 'أدخل التاريخ',
                                prefixIcon: Icon(Icons.date_range),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ),
                      ),const SizedBox(width: 8),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.clear),
                        label: const Text('إلغاء البحث'),
                        onPressed: () {
                          setState(() {
                            searchQuery = '';
                            selectedDate = null;
                            searchDateController.text = 'أدخل التاريخ';
                          });
                          applyFilters();
                        },
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة سائق'),
                        onPressed: showAddDriverDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    children: [
                      TabButton(
                        selected: activeTabIndex == -1,
                        text: 'الكل (${allDrivers.length})',
                        onTap: () => onTabChange(-1),
                      ),
                      TabButton(
                        selected: activeTabIndex == 0,
                        text: 'النشطين (${allDrivers.where((d) => d['active'] == 1).length})',
                        onTap: () => onTabChange(0),
                      ),
                      TabButton(
                        selected: activeTabIndex == 1,
                        text: 'غير النشطين (${allDrivers.where((d) => d['active'] != 1 && (d['rejection'] ?? 0) != 1).length})',
                        onTap: () => onTabChange(1),
                      ),
                      TabButton(
                        selected: activeTabIndex == 2,
                        text: 'مكتملون في انتظار الموافقة (${allDrivers.where((d) => (d['vehicle_type'] != null && d['seats'] != null && d.entries.where((e) => e.key.endsWith('_uploaded') && e.value == true).length == 5) && d['active'] != 1 && (d['rejection'] ?? 0) != 1).length})',
                        onTap: () => onTabChange(2),
                      ),
                      TabButton(
                        selected: activeTabIndex == 3,
                        text: 'بدأوا ولم يكملوا (${allDrivers.where((d) => d.entries.any((e) => e.key.endsWith('_uploaded') && e.value == true) && (d['vehicle_type'] == null || d['seats'] == null || d.entries.where((e) => e.key.endsWith('_uploaded') && e.value == true).length < 5) && (d['rejection'] ?? 0) != 1).length})',
                        onTap: () => onTabChange(3),
                      ),
                      TabButton(
                        selected: activeTabIndex == 4,
                        text: 'المرفوضين (${allDrivers.where((d) => (d['rejection'] == 1 && d['active'] == 0 && (d['disable_note'] == null || d['disable_note'].toString().isEmpty))).length})',
                        onTap: () => onTabChange(4),
                      ),
                      TabButton(
                        selected: activeTabIndex == 5,
                        text: 'الأعضاء المطرودين (${allDrivers.where((d) => (d['rejection'] == 1 && d['active'] == 0 && (d['disable_note'] != null && d['disable_note'].toString().isNotEmpty))).length})',
                        onTap: () => onTabChange(5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : filteredDrivers.isEmpty
                        ? const Center(child: Text("لا يوجد سائقين حسب البحث أو الفلتر"))
                        : ListView.builder(
                      itemCount: filteredDrivers.length,
                      itemBuilder: (context, i) {
                        final driver = filteredDrivers[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            onTap: () => openDriverDetailPage(driver['id']), // 👈
                            title: Text(driver['name'] ?? 'بدون اسم'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (driver['full_name'] != null)
                                  Row(
                                    children: [
                                      const Icon(Icons.person, size: 16, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text("الاسم الكامل: ${driver['full_name']}", style: TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.phone, size: 16, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text("هاتف: ${decrypt(driver['phone'] ?? '')}", style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text("تاريخ التسجيل: ${_formatDate(driver['createdAt'])}", style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                                if (driver['submission_date'] != null) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.task_alt, size: 16, color: Colors.green),
                                      const SizedBox(width: 4),
                                      Text("تاريخ تسجيل الأوراق: ${driver['submission_date']}", style: TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                ],
                                // 👇 ADD HERE:
                                if (driver['max'] != null) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.speed, size: 16, color: Colors.purple),
                                      const SizedBox(width: 4),
                                      Text("الحد الاقصى: ${driver['max']}", style: TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                ],
                              ],
                            ),

                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if ((driver['active'] ?? 0) == 1)
                                  CupertinoButton.filled(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),

                                    onPressed: () => editMax(driver),
                                    child: const Text('تغيير الحد الاقصى'),
                                  ),
                                if ((driver['active'] ?? 0) == 1)

                                const SizedBox(width: 15,),
                                CupertinoButton.filled(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  onPressed: () => deactivateDriver(driver['id']),
                                  child: const Text('تعطيل - طرد العضو'),
                                ),
                              ],
                            ),

                          ),
                        );
                      },
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
  const TabButton({required this.selected, required this.text, required this.onTap});

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