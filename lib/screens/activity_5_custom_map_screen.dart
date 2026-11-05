import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/custom_geofence_spot.dart';
import '../services/custom_marker_storage.dart';
import '../services/location_service.dart';

class Activity5CustomMapScreen extends StatefulWidget {
  static const routeName = '/activity-5';

  const Activity5CustomMapScreen({super.key});

  @override
  State<Activity5CustomMapScreen> createState() =>
      _Activity5CustomMapScreenState();
}

class _Activity5CustomMapScreenState extends State<Activity5CustomMapScreen> {
  final List<CustomGeofenceSpot> _spots = <CustomGeofenceSpot>[];
  final List<CustomGeofenceSpot> _customSpots = <CustomGeofenceSpot>[];
  final Set<String> _defaultSpotIds = <String>{};
  GoogleMapController? _mapController;
  Position? _currentPosition;
  bool _permissionGranted = false;
  bool _isTrackingLocation = false;
  String? _latestArrivalMessage;
  CustomGeofenceSpot? _selectedSpot;
  final Set<String> _notifiedSpotIds = <String>{};
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  MapType _mapType = MapType.normal;
  bool _showNearbySpots = true;
  String _networkStatus = 'Checking connection…';

  List<CustomGeofenceSpot> get _allSpots =>
      <CustomGeofenceSpot>[..._spots, ..._customSpots];

  @override
  void initState() {
    super.initState();
    final List<CustomGeofenceSpot> defaultSpots =
        CustomGeofenceSpot.defaultSpots();
    _spots.addAll(defaultSpots);
    _defaultSpotIds
        .addAll(defaultSpots.map((CustomGeofenceSpot spot) => spot.id));
    unawaited(_loadSavedCustomMarkers());
    unawaited(_refreshNetworkStatus());
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        if (!mounted) {
          return;
        }

        setState(() {
          _networkStatus = _describeConnectivity(results);
        });
      },
      onError: (_) {
        if (!mounted) {
          return;
        }

        setState(() {
          _networkStatus = 'Connection unavailable';
        });
      },
    );
    _requestLocationAccess();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  String _describeConnectivity(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) {
      return 'Wi‑Fi connected';
    }
    if (results.contains(ConnectivityResult.mobile)) {
      return 'Cellular connected';
    }
    return 'Offline';
  }

  Future<void> _refreshNetworkStatus() async {
    try {
      final List<ConnectivityResult> results =
          await _connectivity.checkConnectivity();
      if (!mounted) {
        return;
      }

      setState(() {
        _networkStatus = _describeConnectivity(results);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _networkStatus = 'Connection unavailable';
      });
    }
  }

  bool _isEditableSpot(CustomGeofenceSpot spot) {
    return _defaultSpotIds.contains(spot.id) || spot.id.startsWith('custom-');
  }

  Future<void> _loadSavedCustomMarkers() async {
    try {
      final List<CustomGeofenceSpot> savedMarkers =
          await CustomMarkerStorage.loadMarkers();
      if (!mounted) {
        return;
      }

      setState(() {
        _customSpots
          ..clear()
          ..addAll(savedMarkers);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to load saved custom markers.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _persistCustomMarkers() async {
    try {
      await CustomMarkerStorage.saveMarkers(_customSpots);
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save custom markers offline.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _requestLocationAccess() async {
    final bool granted = await LocationService.requestPermission();
    if (!mounted) {
      return;
    }

    setState(() {
      _permissionGranted = granted;
      if (!granted) {
        _latestArrivalMessage =
            'Location permission is required to enable geofencing.';
      }
    });

    if (!granted) {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Turn on location services to track your real-time position.'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    try {
      final Position position = await LocationService.getCurrentPosition();
      if (!mounted) {
        return;
      }

      setState(() {
        _currentPosition = position;
        _isTrackingLocation = true;
      });

      _centerMapOnPosition(position);
      _startPositionTracking();
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _latestArrivalMessage = 'Unable to read location at the moment.';
      });
    }
  }

  void _startPositionTracking() {
    _positionSubscription = LocationService.positionStream().listen(
      (Position position) {
        if (!mounted) {
          return;
        }

        setState(() {
          _currentPosition = position;
          _isTrackingLocation = true;
          _permissionGranted = true;
        });

        _checkGeofences(position);
      },
      onError: (_) {
        if (!mounted) {
          return;
        }

        setState(() {
          _latestArrivalMessage =
              'Location updates are temporarily unavailable.';
        });
      },
    );
  }

  void _checkGeofences(Position position) {
    for (final CustomGeofenceSpot spot in _allSpots) {
      final double distance = LocationService.distanceBetween(
        LatLng(position.latitude, position.longitude),
        spot.position,
      );
      final bool isInsideRange = distance <= spot.radiusMeters;

      if (isInsideRange && !_notifiedSpotIds.contains(spot.id)) {
        _notifiedSpotIds.add(spot.id);
        setState(() {
          _latestArrivalMessage =
              'You are within ${spot.radiusMeters.round()}m of ${spot.name}.';
          _selectedSpot = spot;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).removeCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
              backgroundColor: spot.accentColor,
              content: Row(
                children: [
                  const Icon(Icons.location_on_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You are near ${spot.name}!',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              action: SnackBarAction(
                label: 'VIEW',
                textColor: Colors.white,
                onPressed: () => _showSpotDetails(spot),
              ),
            ),
          );

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showSpotDetails(spot);
            }
          });
        }
      }

      if (!isInsideRange) {
        _notifiedSpotIds.remove(spot.id);
      }
    }
  }

  void _centerMapOnPosition(Position position) {
    final LatLng target = LatLng(position.latitude, position.longitude);
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: target,
          zoom: 15,
        ),
      ),
    );
  }

  void _fitMapToSpots() {
    if (_mapController == null || _allSpots.isEmpty) {
      return;
    }

    final double minLat = _allSpots
        .map((spot) => spot.position.latitude)
        .reduce((a, b) => a < b ? a : b);
    final double maxLat = _allSpots
        .map((spot) => spot.position.latitude)
        .reduce((a, b) => a > b ? a : b);
    final double minLng = _allSpots
        .map((spot) => spot.position.longitude)
        .reduce((a, b) => a < b ? a : b);
    final double maxLng = _allSpots
        .map((spot) => spot.position.longitude)
        .reduce((a, b) => a > b ? a : b);

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 90),
    );
  }

  Set<Circle> _buildCircles() {
    return _allSpots
        .map((CustomGeofenceSpot spot) => Circle(
              circleId: CircleId(spot.id),
              center: spot.position,
              radius: spot.radiusMeters,
              strokeWidth: 2,
              strokeColor: spot.accentColor,
              fillColor: spot.accentColor.withValues(alpha: 0.14),
            ))
        .toSet();
  }

  Set<Marker> _buildMarkers() {
    final Set<Marker> markers = <Marker>{};

    if (_currentPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('my-location'),
          position:
              LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'My Location'),
        ),
      );
    }

    markers.addAll(
      _allSpots.map((CustomGeofenceSpot spot) {
        return Marker(
          markerId: MarkerId(spot.id),
          position: spot.position,
          zIndexInt: 2,
          icon: BitmapDescriptor.defaultMarkerWithHue(spot.hue),
          infoWindow: InfoWindow(
            title: spot.name,
            snippet:
                'Lat: ${spot.position.latitude.toStringAsFixed(6)}\nLng: ${spot.position.longitude.toStringAsFixed(6)}',
          ),
          onTap: () => _showSpotDetails(spot),
        );
      }),
    );

    return markers;
  }

  String _formatDistance(double distanceInMeters) {
    if (distanceInMeters >= 1000) {
      final double distanceInKm = distanceInMeters / 1000;
      return '${distanceInKm.toStringAsFixed(distanceInKm >= 10 ? 1 : 2)} km away';
    }
    return '${distanceInMeters.round()} m away';
  }

  String _spotDistanceText(CustomGeofenceSpot spot) {
    if (_currentPosition == null) {
      return 'Distance unavailable';
    }

    final double distance = LocationService.distanceBetween(
      LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      spot.position,
    );

    return _formatDistance(distance);
  }

  String _spotStatusText(CustomGeofenceSpot spot) {
    if (_currentPosition == null) {
      return 'Waiting for location';
    }

    final double distance = LocationService.distanceBetween(
      LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      spot.position,
    );

    if (distance <= spot.radiusMeters) {
      return 'Inside geofence';
    }

    return 'Outside geofence';
  }

  Future<Map<String, dynamic>?> _showMarkerFormDialog({
    CustomGeofenceSpot? existingSpot,
    required LatLng point,
  }) async {
    final String dialogTitle =
        existingSpot == null ? 'Add custom marker' : 'Edit custom marker';
    final String submitLabel =
        existingSpot == null ? 'Save marker' : 'Save changes';

    final TextEditingController nameController = TextEditingController(
      text: existingSpot?.name ?? '',
    );
    final TextEditingController radiusController = TextEditingController(
      text: existingSpot == null
          ? '100'
          : existingSpot.radiusMeters.toStringAsFixed(
              existingSpot.radiusMeters.truncateToDouble() ==
                      existingSpot.radiusMeters
                  ? 0
                  : 1,
            ),
    );

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(dialogTitle),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Marker name',
                    hintText: 'e.g. My favorite lookout',
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                Text(
                  'Latitude: ${point.latitude.toStringAsFixed(6)}\nLongitude: ${point.longitude.toStringAsFixed(6)}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: radiusController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Geofence radius (meters)',
                    hintText: '100',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final String name = nameController.text.trim();
                final double? radius =
                    double.tryParse(radiusController.text.trim());

                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a marker name.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                if (radius == null || radius <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Radius must be greater than 0 meters.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                Navigator.of(dialogContext).pop({
                  'name': name,
                  'radius': radius,
                });
              },
              child: Text(submitLabel),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleMapTap(LatLng point) async {
    final Map<String, dynamic>? result =
        await _showMarkerFormDialog(existingSpot: null, point: point);

    if (result == null) {
      return;
    }

    final CustomGeofenceSpot spot = CustomGeofenceSpot(
      id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      name: result['name'] as String,
      shortDescription: 'User-created spot near this area.',
      details:
          'Custom geofence marker placed at this location. The point is saved with a geofence radius of ${(result['radius'] as double).round()} meters.',
      position: point,
      radiusMeters: result['radius'] as double,
      hue: BitmapDescriptor.hueMagenta,
      accentColor: const Color(0xFF9C27B0),
    );

    setState(() {
      _customSpots.add(spot);
      _selectedSpot = spot;
    });
    unawaited(_persistCustomMarkers());

    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: point, zoom: 16),
        ),
      );
    }

    _showSpotDetails(spot);
  }

  Future<void> _editCustomSpot(CustomGeofenceSpot spot) async {
    final Map<String, dynamic>? result =
        await _showMarkerFormDialog(existingSpot: spot, point: spot.position);

    if (result == null) {
      return;
    }

    final double radius = result['radius'] as double;
    final String updatedName = result['name'] as String;

    final CustomGeofenceSpot updatedSpot = CustomGeofenceSpot(
      id: spot.id,
      name: updatedName,
      shortDescription: spot.shortDescription,
      details:
          'Custom geofence marker placed at this location. The point is saved with a geofence radius of ${radius.round()} meters.',
      position: spot.position,
      radiusMeters: radius,
      hue: spot.hue,
      accentColor: spot.accentColor,
    );

    setState(() {
      final int defaultIndex =
          _spots.indexWhere((CustomGeofenceSpot item) => item.id == spot.id);
      if (defaultIndex >= 0) {
        _spots[defaultIndex] = updatedSpot;
      } else {
        final int customIndex = _customSpots
            .indexWhere((CustomGeofenceSpot item) => item.id == spot.id);
        if (customIndex >= 0) {
          _customSpots[customIndex] = updatedSpot;
        }
      }
      _selectedSpot = updatedSpot;
    });
    unawaited(_persistCustomMarkers());

    if (mounted) {
      _showSpotDetails(updatedSpot);
    }
  }

  void _deleteCustomSpot(CustomGeofenceSpot spot) {
    setState(() {
      _customSpots.removeWhere((CustomGeofenceSpot item) => item.id == spot.id);
      if (_selectedSpot?.id == spot.id) {
        _selectedSpot = null;
      }
    });
    unawaited(_persistCustomMarkers());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('${spot.name} deleted.'),
        ),
      );
    }
  }

  void _showSpotDetails(CustomGeofenceSpot spot) {
    setState(() {
      _selectedSpot = spot;
    });

    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: spot.position,
            zoom: 16,
          ),
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bottomSheetContext) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 52,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: spot.accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.location_on_rounded,
                        color: spot.accentColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            spot.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${spot.radiusMeters.round()} m geofence radius',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: spot.accentColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: spot.accentColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Distance from you',
                              style: TextStyle(
                                color: spot.accentColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _currentPosition == null
                                  ? 'Location unavailable'
                                  : _spotDistanceText(spot),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Geofence status',
                              style: TextStyle(
                                color: spot.accentColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _currentPosition == null
                                  ? 'Waiting for location'
                                  : _spotStatusText(spot),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  spot.shortDescription,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  spot.details,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                if (_isEditableSpot(spot))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _editCustomSpot(spot);
                            },
                            icon: const Icon(Icons.edit_rounded),
                            label: const Text('Edit marker'),
                          ),
                        ),
                        if (spot.id.startsWith('custom-')) ...<Widget>[
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                _deleteCustomSpot(spot);
                              },
                              icon: const Icon(Icons.delete_rounded),
                              label: const Text('Delete'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: spot.accentColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: spot.accentColor.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Exact location',
                        style: TextStyle(
                          color: spot.accentColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Lat: ${spot.position.latitude.toStringAsFixed(6)}\nLng: ${spot.position.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget mapWidget = GoogleMap(
      initialCameraPosition: const CameraPosition(
        target: CustomGeofenceSpot.mapCenter,
        zoom: 14.5,
      ),
      mapType: _mapType,
      markers: _buildMarkers(),
      circles: _buildCircles(),
      myLocationEnabled: _permissionGranted,
      myLocationButtonEnabled: _permissionGranted,
      zoomControlsEnabled: false,
      compassEnabled: true,
      onTap: _handleMapTap,
      onMapCreated: (GoogleMapController controller) {
        _mapController = controller;
        _fitMapToSpots();
        if (_currentPosition != null) {
          _centerMapOnPosition(_currentPosition!);
        }
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Map & Geofencing Tracker'),
        actions: [
          PopupMenuButton<MapType>(
            tooltip: 'Map type',
            initialValue: _mapType,
            onSelected: (MapType value) {
              setState(() {
                _mapType = value;
              });
            },
            itemBuilder: (BuildContext context) {
              return const [
                PopupMenuItem<MapType>(
                  value: MapType.normal,
                  child: Text('Default'),
                ),
                PopupMenuItem<MapType>(
                  value: MapType.satellite,
                  child: Text('Satellite'),
                ),
                PopupMenuItem<MapType>(
                  value: MapType.terrain,
                  child: Text('Terrain'),
                ),
              ];
            },
            icon: const Icon(Icons.layers_rounded),
          ),
          IconButton(
            onPressed: () {
              if (_permissionGranted && _currentPosition != null) {
                _centerMapOnPosition(_currentPosition!);
              } else {
                _requestLocationAccess();
              }
            },
            icon: const Icon(Icons.my_location_rounded),
            tooltip: 'Center map on my location',
          ),
        ],
      ),
      body: Stack(
        children: [
          mapWidget,
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Geofencing status',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _latestArrivalMessage ??
                        (_isTrackingLocation
                            ? 'Live GPS active: tracking your real-time location.'
                            : (_permissionGranted
                                ? (_currentPosition != null
                                    ? 'Tap any place on the map to add a custom geofenced marker.'
                                    : 'Tracking location and waiting for arrival...')
                                : 'Permission not granted yet.')),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        _networkStatus == 'Offline'
                            ? Icons
                                .signal_cellular_connected_no_internet_4_bar_rounded
                            : _networkStatus == 'Wi‑Fi connected'
                                ? Icons.wifi_rounded
                                : Icons.signal_cellular_4_bar_rounded,
                        size: 16,
                        color: Colors.grey.shade700,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Network: $_networkStatus',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_currentPosition != null)
                    Text(
                      'Lat: ${_currentPosition!.latitude.toStringAsFixed(5)} • '
                      'Lng: ${_currentPosition!.longitude.toStringAsFixed(5)}',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 18,
            left: 18,
            right: 18,
            child: _showNearbySpots
                ? Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Nearby local spots',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _showNearbySpots = false;
                                  });
                                },
                                icon: const Icon(Icons.expand_more_rounded),
                                tooltip: 'Minimize nearby spots',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _allSpots.map((CustomGeofenceSpot spot) {
                              final bool active = _selectedSpot?.id == spot.id;
                              final String distanceText =
                                  _spotDistanceText(spot);
                              return GestureDetector(
                                onTap: () => _showSpotDetails(spot),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? spot.accentColor
                                            .withValues(alpha: 0.15)
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: active
                                          ? spot.accentColor
                                          : Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        spot.name,
                                        style: TextStyle(
                                          color: active
                                              ? spot.accentColor
                                              : Colors.black87,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        distanceText,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  )
                : Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      width: 220,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _showNearbySpots = true;
                          });
                        },
                        icon: const Icon(Icons.expand_less_rounded),
                        label: const Text('Show nearby spots'),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
