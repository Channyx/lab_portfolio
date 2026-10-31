import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class GoogleMapsRouteService {
  static const String _apiKey = 'AIzaSyDV7vQTMvNt-VJBYBKt--Aa5mjixWFk_c0';

  static Future<LatLng?> geocodeAddress(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return null;
    }

    final Uri url = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeQueryComponent(trimmedQuery)}&key=$_apiKey',
    );

    final http.Response response = await http.get(url);
    if (response.statusCode != 200) {
      return null;
    }

    final Map<String, dynamic> decoded = jsonDecode(response.body);
    if (decoded['status'] != 'OK') {
      return null;
    }

    final List<dynamic> results = decoded['results'] as List<dynamic>;
    if (results.isEmpty) {
      return null;
    }

    final Map<String, dynamic> location =
        results.first['geometry']['location'] as Map<String, dynamic>;

    return LatLng(
      (location['lat'] as num).toDouble(),
      (location['lng'] as num).toDouble(),
    );
  }

  static Future<RoutePlan> getDirections({
    required LatLng origin,
    required LatLng destination,
    String mode = 'walking',
  }) async {
    final Uri url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=${origin.latitude},${origin.longitude}'
      '&destination=${destination.latitude},${destination.longitude}'
      '&mode=$mode'
      '&key=$_apiKey',
    );

    final http.Response response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception('Directions request failed with status ${response.statusCode}');
    }

    final Map<String, dynamic> decoded = jsonDecode(response.body);
    if (decoded['status'] != 'OK') {
      throw Exception('Directions API returned ${decoded['status']}');
    }

    final List<dynamic> routes = decoded['routes'] as List<dynamic>;
    if (routes.isEmpty) {
      throw Exception('No route found');
    }

    final Map<String, dynamic> route = routes.first as Map<String, dynamic>;
    final Map<String, dynamic> overviewPolyline =
        route['overview_polyline'] as Map<String, dynamic>;
    final String encodedPoints = overviewPolyline['points'] as String;
    final List<LatLng> routePoints = _decodePolyline(encodedPoints);

    final List<dynamic> legs = route['legs'] as List<dynamic>;
    final Map<String, dynamic> firstLeg = legs.first as Map<String, dynamic>;
    final Map<String, dynamic> distance = firstLeg['distance'] as Map<String, dynamic>;
    final Map<String, dynamic> duration = firstLeg['duration'] as Map<String, dynamic>;

    return RoutePlan(
      points: routePoints,
      distanceText: distance['text'] as String,
      durationText: duration['text'] as String,
      summary: route['summary'] as String? ?? 'Route',
    );
  }

  static List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = <LatLng>[];
    int index = 0;
    final int latLength = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < latLength) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(
        LatLng(
          lat / 1e5,
          lng / 1e5,
        ),
      );
    }

    return points;
  }
}

class RoutePlan {
  final List<LatLng> points;
  final String distanceText;
  final String durationText;
  final String summary;

  RoutePlan({
    required this.points,
    required this.distanceText,
    required this.durationText,
    required this.summary,
  });
}
