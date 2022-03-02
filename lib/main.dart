import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

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

  late StreamSubscription<Position> _positionSubscription;

  late Position latestPosition;

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    print('init hive');
    await initHive();
    // You can use the getData function to get the data you saved.
    // TODO: failing
    // final customData =
    //     await FlutterForegroundTask.getData<String>(key: 'customData');
    // print('customData: $customData');

    _addEvent('-- Service (re)started --', sendPort);
    // Get the first value
    latestPosition = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );

    _updateLocation(sendPort, latestPosition);

    final LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.best,
    );
    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((position) {
      latestPosition = position;
    });

    periodicTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _updateLocation(sendPort, latestPosition);
    });
  }

  Future<void> initHive() async {
    try {
      final path = (await getApplicationDocumentsDirectory()).path.toString();
      Hive.init(path);
      historyBox = await Hive.openBox<List<String>>(boxName);
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> _updateLocation(SendPort? sendPort, Position location) async {
    _addEvent(
        '${DateFormat(DateFormat.HOUR24_MINUTE_SECOND).format(DateTime.now())} - lat ${location.latitude} lon = ${location.longitude}',
        sendPort);

    print('Location lat ${location.latitude} lon = ${location.longitude}');
  }

  void _addEvent(String event, SendPort? sendPort) {
    List<String> list = historyBox.get('history') ?? <String>[];
    list.add(event);

    historyBox.put('history', list);
    sendPort?.send(list);
  }

  @override
  Future<void> onEvent(DateTime timestamp, SendPort? sendPort) async {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    _addEvent('-- Service stopped at $timestamp --', null);
    // You can use the clearAllData function to clear all the stored data.
    await FlutterForegroundTask.clearAllData();
    periodicTimer.cancel();
    _positionSubscription.cancel();
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
    bool isPermissionGranted;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled don't continue
      // accessing the position and request users of the
      // App to enable the location services.
      return Future.error('Location services are disabled.');
    }

    // TODO: Handle Permissions
    if (Platform.isAndroid) {
      isPermissionGranted =
          await Permission.locationWhenInUse.request().isGranted;
      final isPermissionAlwaysGranted =
          await Permission.locationAlways.request().isGranted;

      if (isPermissionGranted == true && isPermissionAlwaysGranted == true) {
        return true;
      }
    } else {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return Future.error('Location permissions on iOS are denied');
        } else {
          return true;
        }
      } else {
        return true;
      }
    }
    // Permissions are denied forever, handle appropriately.
    return Future.error('Location permissions denied');
  }

  Future<bool> _startForegroundTask() async {
    try {
      await _checkPermissions();
    } catch (e) {
      print(e.toString());
      print('Permissions are denied');
      return false;
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

  Future<bool> _stopForegroundTask() => FlutterForegroundTask.stopService();

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

  Widget _batteryOptimizationWidget() {
    return FutureBuilder(
        future: FlutterForegroundTask.isIgnoringBatteryOptimizations,
        builder: (context, snapshot) {
          if (snapshot.data == false) {
            return Container(
              color: Colors.red,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text('Battery optimized! Disable optimization!'),
                  TextButton(
                    onPressed: () async {
                      await FlutterForegroundTask
                          .openIgnoreBatteryOptimizationSettings();
                    },
                    child: Text('Open Settings'),
                  ),
                ],
              ),
            );
          } else {
            return SizedBox();
          }
        });
  }

  Widget _buildContentView() => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _batteryOptimizationWidget(),
          FutureBuilder(
              future: FlutterForegroundTask.isRunningService,
              builder: (context, snapshot) {
                if (snapshot.data == true) {
                  return Text('Service is running');
                }
                return _buildTestButton('start',
                    onPressed: _startForegroundTask);
              }),
          _buildTestButton('stop', onPressed: () async {
            await _stopForegroundTask();
            // Rebuild UI after service stopped
            setState(() {});
          }),
          Divider(),
          Text('Tracking history every 5 min (${history?.length} items)'),
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
