import 'package:shared_preferences/shared_preferences.dart';

import '../models/custom_geofence_spot.dart';

class CustomMarkerStorage {
  static const String _storageKey = 'activity_5_custom_markers';

  static Future<List<CustomGeofenceSpot>> loadMarkers() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String>? markerJson = prefs.getStringList(_storageKey);

    if (markerJson == null || markerJson.isEmpty) {
      return <CustomGeofenceSpot>[];
    }

    return markerJson
        .where((String rawValue) => rawValue.trim().isNotEmpty)
        .map((String rawValue) => CustomGeofenceSpot.decodeJson(rawValue))
        .toList();
  }

  static Future<void> saveMarkers(List<CustomGeofenceSpot> markers) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> markerJson = markers
        .map((CustomGeofenceSpot marker) => marker.toJsonString())
        .toList();

    await prefs.setStringList(_storageKey, markerJson);
  }
}
