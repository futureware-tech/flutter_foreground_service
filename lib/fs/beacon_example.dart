// import 'package:flutter_beacon/flutter_beacon.dart';

import 'dart:async';
import 'dart:isolate';

import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:foreground_service/model/beacon_log.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

class BeaconExample {
  late Box? beaconMonitoringBox;
  final beaconMonitoringBoxName = 'beacon';

  late Box? beaconRangingBox;
  final beaconRangingBoxName = 'beaconRanging';

  final regions = <Region>[
    Region(
      identifier: '001B44113AB7',
      proximityUUID: 'fffeeedd-4cd2-4a98-8024-fe5b71e0893c',
    ),
    Region(
      identifier: '001B44113AB8',
      proximityUUID: '881a1071-713a-4a07-99c9-e62f25c158b4',
    ),
    Region(
      identifier: 'CB7F8A77F84B',
      proximityUUID: '7cd12d31-95e8-4316-9039-d4cd4226e949',
    ),
    Region(
      identifier: 'D74921B74704',
      proximityUUID: '2565ddd7-d537-41a6-912d-c8ac94e2bcbe',
    ),
    Region(
      identifier: 'DB05A57306C8',
      proximityUUID: '4a4cd244-6b6a-4f5d-98d5-d9ae3cf17fb4',
    ),
    Region(
      identifier: 'DE79BE81F66C',
      proximityUUID: 'e7826bc6-4cd2-4a98-8024-fe5b71e0893c',
    ),
    Region(
      identifier: 'E14110D18068',
      proximityUUID: 'bfaad412-ef7f-4915-9f1f-28f80635b4a1',
    ),
    Region(
      identifier: 'EAE9DB82883B',
      proximityUUID: '521122ac-9d2f-45de-ae4b-5308850f3327',
    ),
    Region(
      identifier: 'EC53A9DEDFA3',
      proximityUUID: 'b0b14acd-9270-432d-9486-e4ead5b7843b',
    ),
    Region(
      identifier: 'F46793EEE4A1',
      proximityUUID: '196b1ac0-84c2-484c-91a9-d5111e2d7385',
    ),
    Region(
      identifier: 'F586267B1A4C',
      proximityUUID: 'f7826da6-4fa2-4e98-8024-bc5b71e08931',
    ),
    Region(
      identifier: 'F97691161417',
      proximityUUID: 'fa45a2ff-e3ca-48f4-8acf-85d2a2d82139',
    ),
  ];

  Stream<RangingResult> rangingResult(List<Region> regions) =>
      flutterBeacon.ranging(regions);
  Stream<MonitoringResult> monitoringResult(List<Region> regions) =>
      flutterBeacon.monitoring(regions);

  Future<void> start() async {
    print('Start beacon service');
    try {
      await flutterBeacon.initializeAndCheckScanning;
      rangingResult(regions).listen((RangingResult rangingResult) {
        addRangingBeaconLog(
            'Beacon with  idendifier: ${rangingResult.region.identifier} in range');
      });
      monitoringResult(regions).listen((MonitoringResult monitoringResult) {
        addMonitoringBeaconLog(
            'Monitoring result ${monitoringResult.region.identifier}: ${monitoringResult.monitoringEventType.toString()}');
        addMonitoringBeaconLog(
            'Monitoring result ${monitoringResult.region.identifier}: ${monitoringResult.monitoringState.toString()}');
      });
    } catch (e) {
      print(e.toString());
    }
  }

  void addMonitoringBeaconLog(String log) {
    List<String> list =
        beaconMonitoringBox?.get(beaconMonitoringBoxName) ?? <String>[];
    list.add(
        '${DateFormat(DateFormat.HOUR24_MINUTE_SECOND).format(DateTime.now())} - $log');

    beaconMonitoringBox?.put(beaconMonitoringBoxName, list);
    print('Beacon monitoring log: $log');
  }

  void addRangingBeaconLog(String log) {
    List<String> list =
        beaconRangingBox?.get(beaconRangingBoxName) ?? <String>[];
    list.add(
        '${DateFormat(DateFormat.HOUR24_MINUTE_SECOND).format(DateTime.now())} - $log');

    beaconRangingBox?.put(beaconRangingBoxName, list);
    print('Beacon ranging log: $log');
  }

  Future<void> stop() async {
    regions.clear();
    flutterBeacon.close;
  }

  void sendData(SendPort? sendPort) {
    if (beaconMonitoringBox?.get(beaconMonitoringBoxName) != null) {
      sendPort?.send(BeaconMonitoringLog(
          beaconMonitoringBox?.get(beaconMonitoringBoxName)));
    }
    if (beaconRangingBox?.get(beaconRangingBoxName) != null) {
      sendPort
          ?.send(BeaconRangingLog(beaconRangingBox?.get(beaconRangingBoxName)));
    }
  }
}
