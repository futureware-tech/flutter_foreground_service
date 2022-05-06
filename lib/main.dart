import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:foreground_service/fs/foreground_task.dart';
import 'package:foreground_service/model/beacon_log.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatefulWidget {
  const ExampleApp({Key? key}) : super(key: key);

  @override
  _ExampleAppState createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp>
    with RestorationMixin, TickerProviderStateMixin {
  TabController? _tabController;
  ReceivePort? _receivePort;
  List<String>? locationLog;
  List<String>? beaconMonitoringLog;
  List<String>? beaconRangingLog;

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
            locationLog = message;
          });
        } else if (message is BeaconMonitoringLog) {
          setState(() {
            beaconMonitoringLog = message.log;
          });
        } else if (message is BeaconRangingLog) {
          setState(() {
            beaconRangingLog = message.log;
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
    _initForegroundTask();
    _tabController = new TabController(length: 3, vsync: this);
    super.initState();
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
            bottom: TabBar(
              controller: _tabController,
              tabs: [
                Tab(
                  icon: Icon(Icons.directions_car),
                ),
                Tab(
                  icon: Icon(Icons.bluetooth),
                  text: 'M',
                ),
                Tab(
                  icon: Icon(Icons.bluetooth),
                  text: 'R',
                ),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildLocationContentView(),
              _buildBeaconMonitoringContentView(),
              _buildBeaconRangingContentView(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBeaconMonitoringContentView() => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('Updates in 5 min (${beaconMonitoringLog?.length} items)'),
          Expanded(child: _logsWidget(beaconMonitoringLog)),
        ],
      );

  Widget _buildBeaconRangingContentView() => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('Updates in 5 min (${beaconRangingLog?.length} items)'),
          Expanded(child: _logsWidget(beaconRangingLog)),
        ],
      );

  Widget _logsWidget(List<String>? historyData) {
    if (historyData == null) return SizedBox();
    var reversedList = historyData.reversed.toList();
    return ListView.builder(
      shrinkWrap: true,
      itemCount: reversedList.length,
      itemBuilder: (context, i) => Text(reversedList[i]),
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

  Widget _buildLocationContentView() => Column(
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
          Text('Tracking history every 5 min (${locationLog?.length} items)'),
          Expanded(child: _logsWidget(locationLog)),
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
