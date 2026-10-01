import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (notificationResponse.payload != null) {
    final prefs = await SharedPreferences.getInstance();
    final String actionId = notificationResponse.actionId ?? '';
    final String payload = notificationResponse.payload!;
    
    if (actionId == 'taken') {
      List<String> remediosJson = prefs.getStringList('remedios') ?? [];
      for (int i = 0; i < remediosJson.length; i++) {
        Map<String, dynamic> r = jsonDecode(remediosJson[i]);
        if (r['id'] == payload) {
          if (r['inventory'] != null && r['inventory'] > 0) {
            r['inventory'] -= 1;
            remediosJson[i] = jsonEncode(r);
            await prefs.setStringList('remedios', remediosJson);
          }
          break;
        }
      }
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  runApp(const RemediosRingApp());
}

class RemediosRingApp extends StatelessWidget {
  const RemediosRingApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RemediosRing',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00796B), brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00796B), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> remedios = [];
  late SharedPreferences prefs;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _loadData();
  }

  Future<void> _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        _loadData(); 
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }
  }

  Future<void> _loadData() async {
    prefs = await SharedPreferences.getInstance();
    List<String> remediosJson = prefs.getStringList('remedios') ?? [];
    setState(() {
      remedios = remediosJson.map((r) => jsonDecode(r) as Map<String, dynamic>).toList();
    });
  }

  Future<void> _saveData() async {
    List<String> remediosJson = remedios.map((r) => jsonEncode(r)).toList();
    await prefs.setStringList('remedios', remediosJson);
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'Pastilla': return Icons.medication;
      case 'Jarabe': return Icons.local_drink;
      case 'Gotas': return Icons.water_drop;
      case 'Inyección': return Icons.vaccines;
      default: return Icons.medical_services;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'Pastilla': return Colors.blue;
      case 'Jarabe': return Colors.orange;
      case 'Gotas': return Colors.teal;
      case 'Inyección': return Colors.red;
      default: return Colors.grey;
    }
  }

  Future<void> _scheduleNotifications(Map<String, dynamic> remedio) async {
    int interval = remedio['interval'] ?? 0;
    int duration = remedio['duration'] ?? 1;
    String id = remedio['id'];
    
    DateTime now = DateTime.now();
    List<String> timeParts = remedio['time'].split(':');
    DateTime scheduledDate = DateTime(now.year, now.month, now.day, int.parse(timeParts[0]), int.parse(timeParts[1]));
    
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'remedios_channel', 'Remedios',
      channelDescription: 'Notificaciones de Remedios',
      importance: Importance.max,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('taken', 'Ya lo tomé'),
        AndroidNotificationAction('snooze', 'Posponer 10 min'),
      ],
    );
    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

    int maxSchedules = interval > 0 ? (24 ~/ interval) * duration : 1;
    
    for (int i = 0; i < maxSchedules; i++) {
      DateTime targetDate = scheduledDate.add(Duration(hours: interval * i));
      DateTime beforeDate = targetDate.subtract(const Duration(minutes: 2));
      DateTime afterDate = targetDate.add(const Duration(minutes: 2));
      
      int baseHash = (id + i.toString()).hashCode;
      
      if (beforeDate.isAfter(now)) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          baseHash,
          'Prepárate: ${remedio['name']}',
          'En 2 minutos toma ${remedio['dosis']}',
          tz.TZDateTime.from(beforeDate, tz.local),
          platformDetails,
          payload: id,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
      
      if (afterDate.isAfter(now)) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          baseHash + 1,
          'Recordatorio: ${remedio['name']}',
          '¿Ya tomaste ${remedio['dosis']}?',
          tz.TZDateTime.from(afterDate, tz.local),
          platformDetails,
          payload: id,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
  }

  void _showAddDialog() {
    final nameController = TextEditingController();
    final dosisController = TextEditingController();
    final inventoryController = TextEditingController();
    TimeOfDay selectedTime = TimeOfDay.now();
    String selectedType = 'Pastilla';
    int interval = 0;
    int duration = 1;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Nuevo Remedio'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      items: ['Pastilla', 'Jarabe', 'Gotas', 'Inyección']
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedType = v!),
                      decoration: const InputDecoration(labelText: 'Tipo', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dosisController,
                      decoration: const InputDecoration(labelText: 'Dosis', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: inventoryController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cantidad Total (Opcional)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Frecuencia: '),
                        DropdownButton<int>(
                          value: interval,
                          items: [0, 4, 6, 8, 12, 24]
                              .map((i) => DropdownMenuItem(value: i, child: Text(i == 0 ? 'Una vez' : 'Cada $i hs')))
                              .toList(),
                          onChanged: (v) => setDialogState(() => interval = v!),
                        ),
                      ],
                    ),
                    if (interval > 0)
                      Row(
                        children: [
                          const Text('Duración: '),
                          DropdownButton<int>(
                            value: duration,
                            items: [1, 2, 3, 5, 7, 10, 30]
                                .map((d) => DropdownMenuItem(value: d, child: Text('$d días')))
                                .toList(),
                            onChanged: (v) => setDialogState(() => duration = v!),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.access_time),
                      label: Text('Hora Inicial: ${selectedTime.format(context)}'),
                      onPressed: () async {
                        final time = await showTimePicker(context: context, initialTime: selectedTime);
                        if (time != null) setDialogState(() => selectedTime = time);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                FilledButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty) {
                      final newRemedio = {
                        'id': const Uuid().v4(),
                        'name': nameController.text,
                        'type': selectedType,
                        'dosis': dosisController.text,
                        'inventory': int.tryParse(inventoryController.text) ?? 0,
                        'time': '${selectedTime.hour}:${selectedTime.minute}',
                        'interval': interval,
                        'duration': duration,
                      };
                      setState(() => remedios.add(newRemedio));
                      _saveData();
                      _scheduleNotifications(newRemedio);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RemediosRing', style: TextStyle(fontWeight: FontWeight.bold))),
      body: remedios.isEmpty
          ? const Center(child: Text('No tienes remedios programados', style: TextStyle(color: Colors.grey, fontSize: 18)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: remedios.length,
              itemBuilder: (context, index) {
                final r = remedios[index];
                bool lowStock = (r['inventory'] != null && r['inventory'] > 0 && r['inventory'] <= 3);
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _getColorForType(r['type']).withOpacity(0.2),
                      child: Icon(_getIconForType(r['type']), color: _getColorForType(r['type'])),
                    ),
                    title: Text(r['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${r['dosis']} - ${r['type']}'),
                        if (r['interval'] > 0)
                          Text('Cada ${r['interval']}hs por ${r['duration']} días', style: const TextStyle(fontSize: 12, color: Colors.blue)),
                        if (r['inventory'] > 0)
                          Text(
                            'Quedan: ${r['inventory']}',
                            style: TextStyle(fontSize: 13, color: lowStock ? Colors.red : Colors.green, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.check_circle_outline, color: Colors.green, size: 30),
                      onPressed: () {
                        setState(() {
                          if (r['inventory'] > 0) r['inventory'] -= 1;
                        });
                        _saveData();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Remedio marcado como tomado')));
                      },
                      tooltip: 'Marcar como tomado',
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo Remedio'),
      ),
    );
  }
}
