// The callback function should always be a top-level function.
import 'dart:async';
import 'dart:isolate';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:foreground_service/fs/beacon_example.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

void startCallback() {
  // The setTaskHandler function must be called to handle the task in the background.
  FlutterForegroundTask.setTaskHandler(FirstTaskHandler());
}

class FirstTaskHandler extends TaskHandler {
  late Timer periodicTimer;
  late Timer beaconPeriodicTimer;
  late Box historyBox;
  final boxName = 'history';

  late StreamSubscription<Position> _positionSubscription;

  late Position latestPosition;

  final beaconExample = BeaconExample();

  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    try {
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

      beaconExample.start();

      beaconPeriodicTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        beaconExample.sendData(sendPort);
      });
    } catch (e) {
      print(e.toString());
    }
  }

  Future<void> initHive() async {
    try {
      final path = (await getApplicationDocumentsDirectory()).path.toString();
      Hive.init(path);

      historyBox = await Hive.openBox<List<String>>(boxName);
      beaconExample.beaconMonitoringBox = await Hive.openBox<List<String>>(
          beaconExample.beaconMonitoringBoxName);
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
    beaconPeriodicTimer.cancel();
    _positionSubscription.cancel();
    beaconExample.stop();
  }

  @override
  void onButtonPressed(String id) {
    // Called when the notification button on the Android platform is pressed.
    print('onButtonPressed >> $id');
  }
}
