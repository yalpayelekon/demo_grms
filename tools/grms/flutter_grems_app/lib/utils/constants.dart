import '../models/alarm.dart';
import '../models/service_status_entry.dart';
import '../models/zone_button.dart';

const mapOriginalWidth = 1920.0;
const mapOriginalHeight = 1080.0;
const demoRoomNumber = 'Demo 101';

final defaultZones = ZonesData(
  homePageBlockButtons: const [
    ZoneButton(uiDisplayName: 'Owner Villa', buttonName: 'Owner Villas', xCoordinate: 340, yCoordinate: 429, active: true),
    ZoneButton(uiDisplayName: '5200 East', buttonName: '5200 East', xCoordinate: 285, yCoordinate: 500, active: true),
    ZoneButton(uiDisplayName: '5900', buttonName: '5900', xCoordinate: 235, yCoordinate: 580, active: true),
    ZoneButton(uiDisplayName: '5800', buttonName: '5800', xCoordinate: 175, yCoordinate: 648, active: true),
    ZoneButton(uiDisplayName: 'A Block', buttonName: 'A', xCoordinate: 529, yCoordinate: 570, active: true),
    ZoneButton(uiDisplayName: 'General Area', buttonName: 'General Area', xCoordinate: 910, yCoordinate: 601, active: false),
    ZoneButton(uiDisplayName: 'F Block', buttonName: 'F', xCoordinate: 1198, yCoordinate: 601, active: true),
    ZoneButton(uiDisplayName: '5000', buttonName: '5000', xCoordinate: 1505, yCoordinate: 701, active: true),
    ZoneButton(uiDisplayName: '5100', buttonName: '5100', xCoordinate: 1598, yCoordinate: 742, active: true),
  ],
  polyPointsData: const [],
  categoryNamesBlockFloorMap: const {
    'A': ['1101', '1102', '1114', '2214', '4300'],
    'F': ['1310', '2214', '4300'],
    '5000': ['5001', '5002', '5003', '5004', '5005', '5006'],
    '5100': ['5101', '5102', '5103', '5104', '5105', '5106'],
    '5200 East': ['5201', '5202', '5203', '5204'],
    '5900': ['5901', '5902', '5903'],
    '5800': ['5801', '5802', '5803'],
  },
);

final zoneRoomNumbersByZone = <String, List<String>>{
  'A': const [
    '1100', '1101', '1102', '1103', '1104', '1105', '1110', '1111', '1112', '1113', '1114', '1115',
    '1200', '1201', '1202', '1203', '1204', '1205', '1210', '1211', '1212', '1213', '1214', '1215',
    '2100', '2101', '2102', '2103', '2104', '2105', '2210', '2211', '2212', '2213', '2214', '2215',
    '3100', '3101', '3102', '3103', '3104', '3105', '3210', '3211', '3212', '3213', '3214', '3215',
    '4100', '4101', '4102', '4103', '4104', '4105', '4200', '4201', '4202', '4203', '4213', '4214'
  ],
  'F': const [
    '1300', '1301', '1302', '1303', '1304', '1305', '1310', '1311', '1312', '1313', '1314', '1315',
    '1400', '1401', '1402', '1403', '1404', '1405', '1410', '1411', '1412', '1413', '1414', '1415',
    '2300', '2301', '2302', '2303', '2304', '2305', '2310', '2311', '2312', '2313', '2314', '2315',
    '3300', '3301', '3302', '3303', '3304', '3305', '3310', '3311', '3312', '3313', '3314', '3315',
    '4300', '4301', '4302', '4303', '4304', '4305', '4400', '4401', '4402', '4403', '4404', '4405'
  ],
  '5000': const [
    '5001', '5002', '5003', '5004', '5005', '5006',
    '5011', '5012', '5013', '5014', '5015', '5016',
    '5021', '5022', '5023', '5024', '5025', '5026',
    '5031', '5032', '5033', '5034', '5035', '5036',
    '5041', '5042', '5043', '5044', '5045', '5046',
    '5051', '5052', '5053', '5054', '5055', '5056'
  ],
  '5100': const [
    '5101', '5102', '5103', '5104', '5105', '5106',
    '5111', '5112', '5113', '5114', '5115', '5116',
    '5121', '5122', '5123', '5124', '5125', '5126',
    '5131', '5132', '5133', '5134', '5135', '5136',
    '5141', '5142', '5143', '5144', '5145', '5146',
    '5151', '5152', '5153', '5154', '5155', '5156'
  ],
  '5200 West': const [
    '5201', '5202', '5203', '5204', '5205', '5206', '5207', '5208', '5209',
    '5210', '5211', '5212', '5213', '5214', '5215', '5216', '5217', '5218'
  ],
  '5200 East': const ['5201', '5202', '5203', '5204', '5205', '5206', '5207', '5208'],
  '5300': const [
    '5301', '5302', '5303', '5304', '5305', '5306', '5307', '5308',
    '5311', '5312', '5313', '5314', '5315', '5316', '5317', '5318',
    '5321', '5322', '5323', '5324', '5325', '5326', '5327', '5328'
  ],
  '5800': const [
    '5801', '5802', '5803', '5804', '5805', '5806',
    '5811', '5812', '5813', '5814', '5815', '5816',
    '5821', '5822', '5823', '5824', '5825', '5826',
    '5831', '5832', '5833', '5834', '5835', '5836'
  ],
  '5900': const ['5901', '5902', '5903', '5904', '5905', '5906', '5907', '5908', '5909', '5910', '5911', '5912', '5913', '5914', '5915', '5916'],
  'Owner Villas': const ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10'],
};

final roomToZoneMap = <String, String>{
  for (final entry in zoneRoomNumbersByZone.entries)
    for (final room in entry.value) room: entry.key,
};

String? resolveZoneForRoomLabel(String label) {
  final normalized = label.toUpperCase();
  final numericSegments = RegExp(r'\d+').allMatches(label).map((m) => m.group(0)!).toList();
  for (final segment in numericSegments) {
    final zone = roomToZoneMap[segment];
    if (zone != null) {
      return zone;
    }
  }
  if (normalized.contains('A BLOCK') || normalized.contains('ROOM A')) return 'A';
  if (normalized.contains('F BLOCK') || normalized.contains('ROOM F')) return 'F';
  return null;
}

const defaultAlarms = [
  Alarm(
    id: '1',
    room: 'Room A103',
    incidentTime: '2026-02-23 08:17',
    category: 'Long Inact.',
    acknowledgement: 'Waiting Ack',
    acknowledgementTime: '',
    status: 'Waiting Repair/Cancel',
    details: 'Device inactive for 42 hours',
  ),
  Alarm(
    id: '2',
    room: 'Room A105',
    incidentTime: '2026-02-22 08:15',
    category: 'Open Door',
    acknowledgement: 'Acknowledged',
    acknowledgementTime: '2026-02-22 08:51',
    status: 'Waiting Repair/Cancel',
    details: 'Door has been open for 25 minutes',
  ),
  Alarm(
    id: '3',
    room: 'F Block sensor',
    incidentTime: '2026-02-22 15:26',
    category: 'PMS',
    acknowledgement: 'Waiting Ack',
    acknowledgementTime: '',
    status: 'Waiting Repair/Cancel',
    details: 'Communication issue with PMS system',
  ),
];

const defaultServiceEntries = [
  ServiceStatusEntry(
    id: 'rs-1',
    roomNumber: '1310',
    serviceType: 'DND',
    serviceState: 'On',
    activationTime: '2026-02-23 12:02',
    delayedMinutes: 0,
  ),
  ServiceStatusEntry(
    id: 'rs-2',
    roomNumber: '5812',
    serviceType: 'Laundry',
    serviceState: 'Finished',
    activationTime: '2026-02-23 12:01',
    delayedMinutes: 1,
    acknowledgement: 'Waiting Ack',
  ),
  ServiceStatusEntry(
    id: 'rs-3',
    roomNumber: '2214',
    serviceType: 'MUR',
    serviceState: 'Delayed',
    activationTime: '2026-02-23 11:58',
    delayedMinutes: 1,
    acknowledgement: 'Waiting Ack',
  ),
];
