import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const ExampleApp());

// The callback function should always be a top-level function.
void startCallback() {
  // The setTaskHandler function must be called to handle the task in the background.
  FlutterForegroundTask.setTaskHandler(FirstTaskHandler());
}

class FirstTaskHandler extends TaskHandler {
  late Timer periodicTimer;
  late Box historyBox;
  final boxName = 'history';

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    await initHive();
    // You can use the getData function to get the data you saved.
    final customData =
        await FlutterForegroundTask.getData<String>(key: 'customData');
    print('customData: $customData');

    _updateLocation(sendPort);
    periodicTimer = Timer.periodic(const Duration(minutes: 5), (tick) async {
      await _updateLocation(sendPort);
    });
  }

  Future<void> initHive() async {
    final path = (await getApplicationDocumentsDirectory()).path.toString();
    Hive.init(path);
    historyBox = await Hive.openBox<List<String>>(boxName);
  }

  Future<void> _updateLocation(SendPort? sendPort) async {
    final location = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    List<String> list = historyBox.get('history') ?? <String>[];
    list.add(
        '${DateFormat(DateFormat.HOUR24_MINUTE_SECOND).format(DateTime.now())} - lat ${location.latitude} lon = ${location.longitude}');

    historyBox.put('history', list);
    sendPort?.send(list);
    print('Location lat ${location.latitude} lon = ${location.longitude}');
  }

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // You can use the clearAllData function to clear all the stored data.
    await FlutterForegroundTask.clearAllData();
    periodicTimer.cancel();
    historyBox.clear();
  }

  @override
  void onButtonPressed(String id) {
    // Called when the notification button on the Android platform is pressed.
    print('onButtonPressed >> $id');
  }
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({Key? key}) : super(key: key);

  @override
  _ExampleAppState createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> with RestorationMixin {
  ReceivePort? _receivePort;
  List<String>? history;

  Future<void> _initForegroundTask() async {
    await FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'notification_channel_id',
        channelName: 'Foreground Notification',
        channelDescription:
            'This notification appears when the foreground service is running.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        autoRunOnBoot: true,
        allowWifiLock: true,
      ),
      printDevLog: true,
    );
  }

  Future<bool> _checkPermissions() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied, next time you could try
        // requesting permissions again (this is also where
        // Android's shouldShowRequestPermissionRationale
        // returned true. According to Android guidelines
        // your App should show an explanatory UI now.
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are denied forever, handle appropriately.
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }
    return true;
  }

  Future<bool> _startForegroundTask() async {
    try {
      await _checkPermissions();
    } catch (e) {
      print(e.toString());
    }
    // You can save data using the saveData function.
    await FlutterForegroundTask.saveData(key: 'customData', value: 'hello');

    ReceivePort? receivePort;
    if (await FlutterForegroundTask.isRunningService) {
      receivePort = await FlutterForegroundTask.restartService();
    } else {
      receivePort = await FlutterForegroundTask.startService(
        notificationTitle: 'Foreground Service is running',
        notificationText: 'Tap to return to the app',
        callback: startCallback,
      );
    }

    if (receivePort != null) {
      _receivePort = receivePort;
      _receivePort?.listen((message) {
        if (message is List<String>) {
          setState(() {
            history = message;
          });
        }
      });

      return true;
    }
    return false;
  }

  Future<bool> _stopForegroundTask() async {
    return await FlutterForegroundTask.stopService();
  }

  @override
  void initState() {
    super.initState();
    _initForegroundTask();
  }

  @override
  void dispose() {
    _receivePort?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // A widget that prevents the app from closing when the foreground service is running.
      // This widget must be declared above the [Scaffold] widget.
      home: WithForegroundTask(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Flutter Foreground Task'),
            centerTitle: true,
          ),
          body: _buildContentView(),
        ),
      ),
    );
  }

  Widget _historyInfoWidget() {
    if (history == null) return SizedBox();
    return ListView.builder(
      shrinkWrap: true,
      itemCount: history?.length,
      itemBuilder: (context, i) => Text(history![i]),
    );
  }

  Widget _buildContentView() => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildTestButton('start', onPressed: _startForegroundTask),
          _buildTestButton('stop', onPressed: _stopForegroundTask),
          Divider(),
          Text('Tracking history every 5 min'),
          Expanded(child: _historyInfoWidget()),
        ],
      );

  Widget _buildTestButton(String text, {VoidCallback? onPressed}) =>
      ElevatedButton(
        child: Text(text),
        onPressed: onPressed,
      );

  @override
  String? get restorationId => '1';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) async {
    if (await FlutterForegroundTask.isRunningService) {
      await _startForegroundTask();
    }
  }
}
