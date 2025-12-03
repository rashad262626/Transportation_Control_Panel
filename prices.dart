import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'rightmenu.dart';

class CityPricesPage extends StatefulWidget {
  const CityPricesPage({super.key});

  @override
  State<CityPricesPage> createState() => _CityPricesPageState();
}

class _CityPricesPageState extends State<CityPricesPage> {
  List<dynamic> allCities = [];
  List<dynamic> filteredCities = [];
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    _checkCookieAndFetch();
  }

  void _checkCookieAndFetch() {
    if (!kIsWeb) {
      fetchCities();
      return;
    }

    fetchCities();
  }

  Future<void> fetchCities() async {
    final doc = await FirebaseFirestore.instance.collection('city').doc('city_coordinates').get();
    final cities = doc.data()?['cities'] ?? [];
    setState(() {
      allCities = cities;
      filteredCities = cities;
    });
  }

  void _filterCities(String query) {
    setState(() {
      searchQuery = query;
      if (query.isEmpty) {
        filteredCities = allCities;
      } else {
        filteredCities = allCities
            .where((c) => (c['arabic'] ?? '').toString().contains(query))
            .toList();
      }
    });
  }

  Future<void> _showEditDialog(int index) async {
    final city = filteredCities[index];
    final cityIndex = allCities.indexWhere((c) => c['arabic'] == city['arabic']);
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
    final privateTaxiCtrl = TextEditingController(text: city['private_taxi']?.toString() ?? '0');
    final privateTrajCtrl = TextEditingController(text: city['private_traj']?.toString() ?? '0');
    final sharedTaxiCtrl = TextEditingController(text: city['shared_taxi']?.toString() ?? '0');
    final sharedTrajCtrl = TextEditingController(text: city['shared_traj']?.toString() ?? '0');

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تعديل أسعار ${city['arabic']}'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              _buildPriceField("مخصوص تاكسي", privateTaxiCtrl),
              _buildPriceField("مخصوص تراجيت", privateTrajCtrl),
              _buildPriceField("مشتركة تاكسي", sharedTaxiCtrl),
              _buildPriceField("مشتركة تراجيت", sharedTrajCtrl),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {

              final oldPrivateTaxi = city['private_taxi'] ?? 0;
              final oldPrivateTraj = city['private_traj'] ?? 0;
              final oldSharedTaxi = city['shared_taxi'] ?? 0;
              final oldSharedTraj = city['shared_traj'] ?? 0;

              final newPrivateTaxi = int.tryParse(privateTaxiCtrl.text) ?? 0;
              final newPrivateTraj = int.tryParse(privateTrajCtrl.text) ?? 0;
              final newSharedTaxi = int.tryParse(sharedTaxiCtrl.text) ?? 0;
              final newSharedTraj = int.tryParse(sharedTrajCtrl.text) ?? 0;

              final updatedCity = {
                ...city,
                'private_taxi': newPrivateTaxi,
                'private_traj': newPrivateTraj,
                'shared_taxi': newSharedTaxi,
                'shared_traj': newSharedTraj,
              };

              allCities[cityIndex] = updatedCity;

              await FirebaseFirestore.instance
                  .collection('city')
                  .doc('city_coordinates')
                  .update({'cities': allCities});

              await FirebaseFirestore.instance.collection('logs').add({
                'action': 'تحديث أسعار مدينة',
                'admin_email': adminEmail ?? 'unknown',
                'city_name': city['arabic'],
                'private_taxi': '$oldPrivateTaxi → $newPrivateTaxi',
                'private_traj': '$oldPrivateTraj → $newPrivateTraj',
                'shared_taxi': '$oldSharedTaxi → $newSharedTaxi',
                'shared_traj': '$oldSharedTraj → $newSharedTraj',
                'timestamp': FieldValue.serverTimestamp(),
              });

              if (mounted) {
                Navigator.of(context).pop();
                fetchCities();
              }
            },
            child: const Text('حفظ'),
          ),        ],
      ),
    );
  }

  Widget _buildPriceField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildTable() {
    return Table(
      border: TableBorder.all(color: Colors.grey.shade300),
      columnWidths: const {
        0: FlexColumnWidth(3),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(2),
        3: FlexColumnWidth(2),
        4: FlexColumnWidth(2),
      },
      children: [
        const TableRow(
          decoration: BoxDecoration(color: Colors.grey),
          children: [
            Padding(padding: EdgeInsets.all(8), child: Text('المدينة', style: TextStyle(fontWeight: FontWeight.bold))),
            Padding(padding: EdgeInsets.all(8), child: Text('مخصوص تاكسي', style: TextStyle(fontWeight: FontWeight.bold))),
            Padding(padding: EdgeInsets.all(8), child: Text('مخصوص تراجيت', style: TextStyle(fontWeight: FontWeight.bold))),
            Padding(padding: EdgeInsets.all(8), child: Text('مشتركة تاكسي', style: TextStyle(fontWeight: FontWeight.bold))),
            Padding(padding: EdgeInsets.all(8), child: Text('مشتركة تراجيت', style: TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        ...List.generate(filteredCities.length, (i) {
          final c = filteredCities[i];
          return TableRow(
            children: [
              InkWell(
                onTap: () => _showEditDialog(i),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(c['arabic'] ?? '-'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('${c['private_taxi'] ?? 0} د.ل'),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('${c['private_traj'] ?? 0} د.ل'),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('${c['shared_taxi'] ?? 0} د.ل'),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('${c['shared_traj'] ?? 0} د.ل'),
              ),
            ],
          );
        }),
      ],
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 24),
                  const Text("إدارة أسعار المدن", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: '🔍 ابحث باسم المدينة',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: _filterCities,
                  ),
                  const SizedBox(height: 20),
                  _buildTable(),
                ],
              ),
            ),
          ),
          Container(width: 250, color: Colors.white, child: const RightMenu()),
        ],
      ),
    );
  }
}
