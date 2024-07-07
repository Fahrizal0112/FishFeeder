import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Fish Feeder App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: FishFeederPage(),
    );
  }
}

class FishFeederPage extends StatefulWidget {
  @override
  _FishFeederPageState createState() => _FishFeederPageState();
}

class _FishFeederPageState extends State<FishFeederPage> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  bool _isLoading = false;
  String _result = '';
  List<Map<String, dynamic>> _schedule = [];
  late MqttServerClient _client;
  late Timer _timer;
  String _waterStatus = '';
  String _feedingAdvice = '';

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _setupMqtt();
    _getLocalSchedule();
    _timer = Timer.periodic(Duration(seconds: 30), (timer) {
      _refreshSchedule();
      _subscribeToWaterStatus();
      _refreshfeed();
      print('Merefresh');
    });
    _timer = Timer.periodic(Duration(seconds: 5), (timer) {
      _subscribeToWaterStatus();
      _refreshfeed();
      print('Merefresh!');
    });
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    final firstCamera = cameras.first;
    _controller = CameraController(
      firstCamera,
      ResolutionPreset.medium,
    );
    _initializeControllerFuture = _controller.initialize();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.getImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      _captureAndSend(File(pickedFile.path));
    }
  }

  Future<void> _captureAndSend(File imageFile) async {
    setState(() {
      _isLoading = true;
      _result = '';
    });
    try {
      final bytes = await imageFile.readAsBytes();

      // Ambil nama file dari path lengkap
      String fileName = imageFile.path.split('/').last;

      var request = http.MultipartRequest(
        'POST', 
        Uri.parse('https://fishfeeder-424613.et.r.appspot.com/predict')
      );
      request.files.add(
        http.MultipartFile(
          'image',
          http.ByteStream.fromBytes(bytes),
          bytes.length,
          filename: fileName, // Gunakan nama file dari path lengkap
        ),
      );

      final predictResponse = await request.send();
      final response = await http.Response.fromStream(predictResponse);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final String prediction = data['prediction'];
        setState(() {
          _result = prediction;
        });
      } else {
        setState(() {
          _result = 'Error: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _result = 'Error: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  Future<void> _getLocalSchedule() async {
    List<Map<String, dynamic>> localSchedule = await _getSchedule();
    setState(() {
      _schedule = localSchedule;
    });
  }

  Future<void> _addSchedule(String title, String hour) async {
    try {
      final newScheduleItem = {'title': title, 'hour': hour};
      List<Map<String, dynamic>> updatedSchedule = [..._schedule, newScheduleItem];
      await _saveSchedule(updatedSchedule);
      setState(() {
        _schedule = updatedSchedule;
      });
    } catch (e) {
      print('Error adding schedule: $e');
    }
  }

  Future<void> _saveSchedule(List<Map<String, dynamic>> schedule) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('schedule', jsonEncode(schedule));
  }

  Future<List<Map<String, dynamic>>> _getSchedule() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString('schedule');
    if (jsonString != null) {
      List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((item) => Map<String, dynamic>.from(item)).toList();
    } else {
      return [];
    }
  }

  Future<void> _showAddScheduleDialog() async {
    String title = '';
    String hour = '';

    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Add Schedule'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                onChanged: (value) => title = value,
                decoration: InputDecoration(labelText: 'Title'),
              ),
              TextField(
                onChanged: (value) => hour = value,
                decoration: InputDecoration(labelText: 'Hour (HH:mm)'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _addSchedule(title, hour);
                Navigator.of(context).pop();
              },
              child: Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _setupMqtt() {
    _client = MqttServerClient('mqtt-dashboard.com', '');
    _client.port = 1883;
    _client.logging(on: true);

    _client.onConnected = _onConnected;
    _client.onDisconnected = _onDisconnected;

    final MqttConnectMessage connectMessage = MqttConnectMessage()
        .withClientIdentifier('Fish_Feeder_Client')
        .keepAliveFor(60)
        .withWillQos(MqttQos.atMostOnce);
    _client.connectionMessage = connectMessage;

    _connect();
  }

  void _onConnected() {
    print('Connected to MQTT server');
  }

  void _onDisconnected() {
    print('Disconnected from MQTT server');
  }

  void _subscribeToWaterStatus() {
    _client.subscribe('water/status', MqttQos.atMostOnce);
    _client.updates?.listen((List<MqttReceivedMessage<MqttMessage>>? event) {
      if (event != null && event.isNotEmpty) {
        final MqttPublishMessage receivedMessage = event[0].payload as MqttPublishMessage;
        final String message = MqttPublishPayload.bytesToStringAsString(receivedMessage.payload.message);
        setState(() {
          _waterStatus = message;
        });
        
        // Cek apakah status air keruh
        if (_waterStatus.toLowerCase().contains('Keruh')) {
          _showAlertDialog('Warning', 'Air harus diganti!');
        }
      }
    });
  }

  void _showAlertDialog(String title, String message) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            child: Text('OK'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}
  Future<void> _connect() async {
    try {
      await _client.connect();
      print('MQTT client connected');
      _showAlertDialog('Success', 'MQTT client connected successfully');
    } catch (e) {
      print('MQTT client connection failed - $e');
      _showAlertDialog('Error', 'MQTT client connection failed: $e');
    }
  }

  Future<void> _disconnect() async {
    try {
      print('MQTT client disconnected');
    } catch (e) {
      print('MQTT client disconnection failed - $e');
    }
  }

  void _publishMessage() {
    final builder = MqttClientPayloadBuilder();
    builder.addString('1');
    _client.publishMessage('servo/publish', MqttQos.exactlyOnce, builder.payload!);
    _showAlertDialog('Success', 'Makanan Berhasil Di Keluarkan');
  }

  Future<void> _refreshSchedule() async {
    await _getLocalSchedule();
    
    // Pengecekan jadwal dengan waktu saat ini
    _schedule.forEach((scheduleItem) {
      String hour = scheduleItem['hour'];
      List<String> parts = hour.split(':');
      int scheduledHour = -1; // Nilai default jika parsing gagal
      int scheduledMinute = -1; // Nilai default jika parsing gagal
      try {
        scheduledHour = int.parse(parts[0]);
        scheduledMinute = int.parse(parts[1]);
      } catch (e) {
        print('Error parsing hour or minute: $e');
        return; // Keluar dari iterasi saat terjadi kesalahan parsing
      }

      DateTime now = DateTime.now();
      if (scheduledHour == -1 || scheduledMinute == -1) {
        print('Invalid hour or minute');
        return; // Keluar dari iterasi jika nilai tidak valid
      }

      if (now.hour == scheduledHour && now.minute == scheduledMinute) {
        // Jika waktu saat ini sama dengan jadwal, kirim sinyal ke servo
        _publishMessage();
        print('Servo Bergerak');
      }
    });
  }

  Future<void> _refreshfeed() async {
    bool isFightingFishDetected = _result.toLowerCase().contains('fighting');
    bool isGoldFishDetected = _result.toLowerCase().contains('gold');
    bool isGuppyDetected = _result.toLowerCase().contains('guppy');
    bool isKoiDetected = _result.toLowerCase().contains('koi');

    if (isFightingFishDetected) {
      _feedingAdvice = 'Ikan Fighting sebaiknya diberi makan 1-2 kali sehari.';
    } else if (isGoldFishDetected) {
      _feedingAdvice = 'Ikan Gold sebaiknya diberi makan 2-3 kali sehari.';
    } else if (isGuppyDetected) {
      _feedingAdvice = 'Ikan Guppy sebaiknya diberi makan 2 kali sehari.';
    } else if (isKoiDetected) {
      _feedingAdvice = 'Ikan Koi sebaiknya diberi makan 1-2 kali sehari.';
    } else {
      _feedingAdvice = '';
    }
  }

  Future<void> _deleteSchedule(Map<String, dynamic> scheduleItem) async {
    try {
      List<Map<String, dynamic>> updatedSchedule = List.from(_schedule);
      updatedSchedule.remove(scheduleItem);
      await _saveSchedule(updatedSchedule);
      setState(() {
        _schedule = updatedSchedule;
      });
    } catch (e) {
      print('Error deleting schedule: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer.cancel();
    _disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Fish Feeder App'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: _showAddScheduleDialog,
          ),
          IconButton(
            icon: Icon(Icons.pets),
            onPressed: _publishMessage,
          ),
          IconButton(
            icon: Icon(Icons.connect_without_contact),
            onPressed: _connect,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshSchedule,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _isLoading
                  ? CircularProgressIndicator()
                  : Column(
                      children: [
                        ElevatedButton(
                          onPressed: _pickImage,
                          child: Text('Pick Image from Gallery'),
                        ),
                        SizedBox(height: 10),
                      ],
                    ),
              SizedBox(height: 20),
              Text(
                'Detected Fish: $_result\n',
                style: TextStyle(fontSize: 18),
              ),
              Text(
                'Feeding Advice: $_feedingAdvice\n',
                style: TextStyle(fontSize: 18),
              ),
              Text(
                'Clarity: $_waterStatus\n',
                style: TextStyle(fontSize: 18),
              ),
              SizedBox(height: 20),
              Expanded(
                child: _schedule.isEmpty
                    ? Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        itemCount: _schedule.length,
                        itemBuilder: (context, index) {
                          final scheduleItem = _schedule[index];
                          return ListTile(
                            title: Text(scheduleItem['title']),
                            subtitle: Text('${scheduleItem['hour']}'),
                            trailing: IconButton(
                              icon: Icon(Icons.delete),
                              onPressed: () => _deleteSchedule(scheduleItem),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
