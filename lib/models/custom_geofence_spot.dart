import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class CustomGeofenceSpot {
  final String id;
  final String name;
  final String shortDescription;
  final String details;
  final LatLng position;
  final double radiusMeters;
  final double hue;
  final Color accentColor;

  const CustomGeofenceSpot({
    required this.id,
    required this.name,
    required this.shortDescription,
    required this.details,
    required this.position,
    required this.radiusMeters,
    required this.hue,
    required this.accentColor,
  });

  static const LatLng mapCenter = LatLng(8.677029171453656, 126.12910971583551);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'shortDescription': shortDescription,
      'details': details,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'radiusMeters': radiusMeters,
      'hue': hue,
      'accentColor': accentColor.value,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  factory CustomGeofenceSpot.fromJson(Map<String, dynamic> json) {
    final double latitude =
        (json['latitude'] as num?)?.toDouble() ?? mapCenter.latitude;
    final double longitude =
        (json['longitude'] as num?)?.toDouble() ?? mapCenter.longitude;

    return CustomGeofenceSpot(
      id: json['id'] as String? ??
          'custom-${DateTime.now().microsecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Custom marker',
      shortDescription:
          json['shortDescription'] as String? ?? 'User-created spot.',
      details: json['details'] as String? ?? 'User-created marker',
      position: LatLng(latitude, longitude),
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 100,
      hue: (json['hue'] as num?)?.toDouble() ?? BitmapDescriptor.hueMagenta,
      accentColor: Color((json['accentColor'] as num?)?.toInt() ??
          const Color(0xFF9C27B0).value),
    );
  }

  static CustomGeofenceSpot decodeJson(String rawJson) {
    return CustomGeofenceSpot.fromJson(
      Map<String, dynamic>.from(jsonDecode(rawJson) as Map<String, dynamic>),
    );
  }

  static List<CustomGeofenceSpot> defaultSpots() {
    return const [
      CustomGeofenceSpot(
        id: 'palwar-river',
        name: 'Palwar River',
        shortDescription: 'Undiscovered river spot near P-2 Hilltop.',
        details:
            'This local river area is a natural landmark and travel route important to the P-2 Hilltop community and nearby walking paths.',
        position: LatLng(8.680250640267404, 126.12908728193949),
        radiusMeters: 45,
        hue: BitmapDescriptor.hueGreen,
        accentColor: Color(0xFF2E7D32),
      ),
      CustomGeofenceSpot(
        id: 'p2-hilltop-chapel',
        name: 'P-2 Hilltop Catholic Chapel',
        shortDescription: 'Hilltop chapel overlooking the barangay.',
        details:
            'A quiet spiritual landmark on the elevated ridge, commonly used by residents as a short stop along the hilltop route.',
        position: LatLng(8.676413281372131, 126.12949749729839),
        radiusMeters: 40,
        hue: BitmapDescriptor.hueAzure,
        accentColor: Color(0xFF1976D2),
      ),
      CustomGeofenceSpot(
        id: 'p2-new-bridge',
        name: 'Newly Constructed Bridge in P-2 Hilltop',
        shortDescription: 'Fresh bridge along the higher hill path.',
        details:
            'This new bridge connects the hilltop community with the lower barangay route and serves as a practical local access point.',
        position: LatLng(8.67733458930424, 126.13074802058294),
        radiusMeters: 35,
        hue: BitmapDescriptor.hueOrange,
        accentColor: Color(0xFFF57C00),
      ),
      CustomGeofenceSpot(
        id: 'bao-bao-reservoir',
        name: 'Water Reservoir above Bao-Bao Falls',
        shortDescription:
            'Water storage system linked to the hilltop watering network.',
        details:
            'This elevated reservoir is part of the local watering system above Bao-Bao Falls and supports the community through the hillside network.',
        position: LatLng(8.688685433681147, 126.11956339967665),
        radiusMeters: 42,
        hue: BitmapDescriptor.hueRose,
        accentColor: Color(0xFFD32F2F),
      ),
      CustomGeofenceSpot(
        id: 'globe-tower-p3',
        name: 'Globe Tower in P-3 St. Christine',
        shortDescription: 'Telecom tower near the elementary school area.',
        details:
            'A communication structure near St. Christine Elementary School, marking a clear local landmark and signal tower in the barangay.',
        position: LatLng(8.675517876037304, 126.12737870296252),
        radiusMeters: 38,
        hue: BitmapDescriptor.hueViolet,
        accentColor: Color(0xFF7B1FA2),
      ),
    ];
  }
}
