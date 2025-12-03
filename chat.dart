// Full refactored AdminChatPage with requested logic

import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:intl/intl.dart';
import 'admin_chat.dart';
import 'rightmenu.dart';

class AdminChatPage extends StatefulWidget {
  const AdminChatPage({Key? key}) : super(key: key);

  @override
  State<AdminChatPage> createState() => _AdminChatPageState();
}

class _AdminChatPageState extends State<AdminChatPage> with SingleTickerProviderStateMixin {
  String searchQuery = '';
  late TabController tabController;
  DateTime? _selectedDate;

  final List<Tab> tabs = const [
    Tab(text: 'الكل'),
    Tab(text: 'جديدة'),
    Tab(text: 'مفتوحة'),
    Tab(text: 'مغلقة'),
    Tab(text: 'مهمة'),
  ];

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: tabs.length, vsync: this);
    timeago.setLocaleMessages('ar', timeago.ArMessages());
    _selectedDate = DateTime.now(); // default to today filter
  }

  @override
  void dispose() {
    tabController.dispose();
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
  Map<String, String> _extractUserData(Map<String, dynamic> data) {
    String roleLabel = 'مستخدم';
    String phone = 'غير معروف';

    if (data['driver'] == true) {
      roleLabel = 'سائق';
      if (data['driverPhone'] != null) {
        phone = decrypt(data['driverPhone']);
      }
    } else {
      // fallback for non-driver users
      if (data.containsKey('phone') && data['phone'] is List) {
        final phones = List<String>.from(data['phone']);
        final userPhone = phones.firstWhere((p) => p != 'admin', orElse: () => '');
        if (userPhone.isNotEmpty) {
          phone = decrypt(userPhone);
        }
      }
    }

    return {
      'roleLabel': roleLabel,
      'userPhone': phone,
    };
  }

  Query<Map<String, dynamic>> _baseQueryForTab(int tabIndex) {
    final chats = FirebaseFirestore.instance.collection('chat_chat');
    Query<Map<String, dynamic>> query;
    switch (tabIndex) {
      case 1:
        query = chats.where('status', isEqualTo: 'new');
        break;
      case 2:
        query = chats.where('status', isEqualTo: 'open');
        break;
      case 3:
        query = chats.where('status', isEqualTo: 'closed');
        break;
      case 4:
        query = chats.where('priority', isEqualTo: 'high');
        break;
      default:
        query = chats;
        break;
    }

    // 🔧 Disable date filter for testing:
    // if (tabIndex != 4 && _selectedDate != null) {
    //   final start = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
    //   final end = start.add(const Duration(days: 1)).subtract(const Duration(seconds: 1));
    //   query = query
    //       .where('lastMessageTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
    //       .where('lastMessageTime', isLessThanOrEqualTo: Timestamp.fromDate(end));
    // }

    return query;
  }

  Future<void> _updateTicketStatus(String id, {String? status, String? priority}) async {
    final update = <String, dynamic>{};
    if (status != null) update['status'] = status;
    if (priority != null) update['priority'] = priority;

    await FirebaseFirestore.instance.collection('chat_chat').doc(id).update(update);
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('ar', ''),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: Row(
        children: [
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  _buildSearchFilters(),
                  _buildTabs(),
                  _buildTabViews(),
                ],
              ),
            ),
          ),
          Container(width: 250, color: Colors.white, child: const RightMenu()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        children: const [
          Icon(Icons.message, color: Colors.blueAccent),
          SizedBox(width: 8),
          Text(
            'لوحة المحادثات - الادمن',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          Spacer(),
        ],
      ),
    );
  }

  Widget _buildSearchFilters() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          CupertinoSearchTextField(
            placeholder: 'بحث باسم المستخدم أو رقم الهاتف أو الرسالة الأخيرة',
            onChanged: (v) => setState(() => searchQuery = v.trim()),
          ),
          const SizedBox(height: 12),
          CupertinoButton.filled(
            onPressed: () => _selectDate(context),
            child: Text(
              _selectedDate == null
                  ? 'اختر تاريخ للبحث'
                  : 'تصفية حسب التاريخ: ${DateFormat('dd-MM-yyyy').format(_selectedDate!)}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return TabBar(
      controller: tabController,
      labelColor: Colors.blueAccent,
      unselectedLabelColor: Colors.grey,
      indicatorColor: Colors.blue,
      isScrollable: true,
      tabs: tabs,
    );
  }

  Widget _buildTabViews() {
    return Expanded(
      child: TabBarView(
        controller: tabController,
        children: List.generate(tabs.length, (tabIndex) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _baseQueryForTab(tabIndex)
                .orderBy('lastMessageTime', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(child: Text('لا يوجد بيانات'));
              }

              final chats = snapshot.data!.docs.map((doc) {
                final data = doc.data();
                data['id'] = doc.id;
                return data;
              }).where((data) {
                final lastMsg = (data['lastMessage'] ?? '').toString();
                return searchQuery.isEmpty || lastMsg.contains(searchQuery);
              }).toList();

              return ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: chats.length,
                itemBuilder: (context, i) {
                  final c = chats[i];
                  final date = (c['lastMessageTime'] as Timestamp?)?.toDate() ?? DateTime.now();

                  // 🔔 Determine role & phone by checking latest message driver=true
                  String role = 'مستخدم';
                  String phone = 'غير معروف';

                  if (c['driverPhone'] != null) {
                    phone = decrypt(c['driverPhone']);
                  } else if (c['phone'] != null && c['phone'] is List) {
                    final phones = List<String>.from(c['phone']);
                    final userPhone = phones.firstWhere((p) => p != 'admin', orElse: () => '');
                    if (userPhone.isNotEmpty) {
                      phone = decrypt(userPhone);
                    }
                  }

                  if (c['driver'] == true) {
                    role = 'سائق';
                  } else {
                    role = 'مستخدم';
                  }

                  return Card(
                    child: ListTile(
                      title: Text(c['name']?['admin'] ?? 'بدون اسم'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c['lastMessage'] ?? '-'),
                          Text('$role $phone'),
                          Text(timeago.format(date, locale: 'ar')),
                        ],
                      ),
                      trailing: Builder(
                        builder: (context) {
                          final maxWidth = MediaQuery.of(context).size.width * 0.6;
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildStatusBadge(c['status']),
                              if (['new', 'open', 'high'].contains(c['status']) || c['priority'] == 'high')
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(maxWidth: maxWidth),
                                    child: Wrap(
                                      alignment: WrapAlignment.end,
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: [
                                        TextButton.icon(
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            minimumSize: Size(0, 30),
                                          ),
                                          icon: const Icon(Icons.flag, size: 16, color: Colors.orange),
                                          label: const Text('جعل التدكرة مهمة', style: TextStyle(fontSize: 11)),
                                          onPressed: () => _updateTicketStatus(c['id'], priority: 'high'),
                                        ),
                                        TextButton.icon(
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            minimumSize: Size(0, 30),
                                          ),
                                          icon: const Icon(Icons.close, size: 16, color: Colors.red),
                                          label: const Text('إغلاق التدكرة', style: TextStyle(fontSize: 11)),
                                          onPressed: () => _updateTicketStatus(c['id'], status: 'closed'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminChatScreen(
                            chatId: c['id'],
                            userName: c['name']?['admin'] ?? 'مستخدم',
                            userPhone: phone,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        }),
      ),
    );
  }
  Widget _buildStatusBadge(String? status) {
    final text = _getStatusText(status ?? '');
    final color = _getStatusColor(status ?? '');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, color: Colors.white)),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'new': return Colors.orange;
      case 'open': return Colors.green;
      case 'closed': return Colors.grey;
      default: return Colors.blue;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'new': return 'جديدة';
      case 'open': return 'مفتوحة';
      case 'closed': return 'مغلقة';
      default: return status;
    }
  }
}
