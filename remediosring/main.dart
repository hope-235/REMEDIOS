import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00796B),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Color(0xFF00796B),
          foregroundColor: Colors.white,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00796B),
          brightness: Brightness.dark,
        ),
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
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  
  List<Map<String, dynamic>> remedios = [];

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _requestPermissions();
  }

  Future<void> _initNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> _requestPermissions() async {
    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }
  }

  Future<void> _scheduleNotifications(String name, String dosis, TimeOfDay time) async {
    final now = DateTime.now();
    var scheduledDate = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    final beforeDate = scheduledDate.subtract(const Duration(minutes: 2));
    final afterDate = scheduledDate.add(const Duration(minutes: 2));

    const androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'remedios_channel',
      'Remedios Notifications',
      channelDescription: 'Notificaciones para tomar remedios',
      importance: Importance.max,
      priority: Priority.high,
    );
    const platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);

    // Notificación 2 minutos antes
    if (beforeDate.isAfter(now)) {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        name.hashCode ^ beforeDate.hashCode,
        'Prepárate: $name',
        'En 2 minutos debes tomar $dosis',
        tz.TZDateTime.from(beforeDate, tz.local),
        platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }

    // Notificación 2 minutos después
    await flutterLocalNotificationsPlugin.zonedSchedule(
      name.hashCode ^ afterDate.hashCode,
      'Recordatorio: $name',
      '¿Ya tomaste tu dosis de $dosis? Pasaron 2 minutos de la hora.',
      tz.TZDateTime.from(afterDate, tz.local),
      platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  void _addRemedio(String name, String dosis, TimeOfDay time) {
    setState(() {
      remedios.add({
        'name': name,
        'dosis': dosis,
        'time': time,
      });
    });
    _scheduleNotifications(name, dosis, time);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Remedio "$name" programado con éxito.')),
    );
  }

  void _showAddDialog() {
    final nameController = TextEditingController();
    final dosisController = TextEditingController();
    TimeOfDay selectedTime = TimeOfDay.now();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Agregar Remedio'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del remedio',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.medical_services),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: dosisController,
                      decoration: const InputDecoration(
                        labelText: 'Dosis (ej. 1 pastilla, 10ml)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.vaccines),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.access_time, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          'Hora: ${selectedTime.format(context)}',
                          style: const TextStyle(fontSize: 16),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () async {
                            final TimeOfDay? time = await showTimePicker(
                              context: context,
                              initialTime: selectedTime,
                            );
                            if (time != null) {
                              setDialogState(() {
                                selectedTime = time;
                              });
                            }
                          },
                          child: const Text('Cambiar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    if (nameController.text.isNotEmpty && dosisController.text.isNotEmpty) {
                      _addRemedio(nameController.text, dosisController.text, selectedTime);
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
      appBar: AppBar(
        title: const Text('RemediosRing', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: remedios.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.health_and_safety, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No tienes remedios programados',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: remedios.length,
              itemBuilder: (context, index) {
                final r = remedios[index];
                final time = r['time'] as TimeOfDay;
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(Icons.medication, color: Theme.of(context).colorScheme.primary),
                    ),
                    title: Text(
                      r['name'],
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text('Dosis: ${r['dosis']}'),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        time.format(context),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('Agregar Remedio'),
      ),
    );
  }
}
