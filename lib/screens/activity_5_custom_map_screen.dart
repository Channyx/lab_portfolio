import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/custom_geofence_spot.dart';
import '../services/google_maps_route_service.dart';
import '../services/location_service.dart';

class Activity5CustomMapScreen extends StatefulWidget {
  static const routeName = '/activity-5';

  const Activity5CustomMapScreen({super.key});

  @override
  State<Activity5CustomMapScreen> createState() =>
      _Activity5CustomMapScreenState();
}

class _Activity5CustomMapScreenState extends State<Activity5CustomMapScreen> {
  late final List<CustomGeofenceSpot> _spots;
  GoogleMapController? _mapController;
  Position? _currentPosition;
  bool _permissionGranted = false;
  bool _isTrackingLocation = false;
  String? _latestArrivalMessage;
  CustomGeofenceSpot? _selectedSpot;
  final Set<String> _notifiedSpotIds = <String>{};
  StreamSubscription<Position>? _positionSubscription;
  MapType _mapType = MapType.normal;
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  String? _selectedDestinationId;
  bool _routeLoading = false;
  bool _showNearbySpots = true;
  String _routeInfo = '';
  List<LatLng> _routePoints = <LatLng>[];
  Set<Polyline> _polylines = <Polyline>{};

  @override
  void initState() {
    super.initState();
    _spots = CustomGeofenceSpot.defaultSpots();
    _requestLocationAccess();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _mapController?.dispose();
    _originController.dispose();
    _destinationController.dispose();
    super.dispose();
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
        _originController.text = 'My Location';
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
    for (final CustomGeofenceSpot spot in _spots) {
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
    if (_mapController == null || _spots.isEmpty) {
      return;
    }

    final double minLat = _spots
        .map((spot) => spot.position.latitude)
        .reduce((a, b) => a < b ? a : b);
    final double maxLat = _spots
        .map((spot) => spot.position.latitude)
        .reduce((a, b) => a > b ? a : b);
    final double minLng = _spots
        .map((spot) => spot.position.longitude)
        .reduce((a, b) => a < b ? a : b);
    final double maxLng = _spots
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

  Future<void> _showRoutePlannerSheet() async {
    if (_originController.text.isEmpty && _currentPosition != null) {
      _originController.text = 'My Location';
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return AnimatedPadding(
              padding: EdgeInsets.only(bottom: bottomInset),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    child: Column(
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
                        const Text(
                          'Route planner',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _originController,
                          decoration: const InputDecoration(
                            labelText: 'Origin',
                            hintText: 'My Location or a place name',
                            prefixIcon: Icon(Icons.my_location_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedDestinationId,
                          decoration: const InputDecoration(
                            labelText: 'Destination',
                            prefixIcon: Icon(Icons.flag_outlined),
                            border: OutlineInputBorder(),
                          ),
                          items: _spots.map((spot) {
                            return DropdownMenuItem<String>(
                              value: spot.id,
                              child: Text(spot.name),
                            );
                          }).toList(),
                          onChanged: (String? value) {
                            setSheetState(() {
                              _selectedDestinationId = value;
                              final selectedSpot = _spots.firstWhere(
                                (spot) => spot.id == value,
                                orElse: () => _spots.first,
                              );
                              _destinationController.text = selectedSpot.name;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _destinationController,
                          decoration: const InputDecoration(
                            labelText: 'Or type a destination',
                            hintText: 'e.g. St. Christine Elementary School',
                            prefixIcon: Icon(Icons.place_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _routeLoading ? null : _buildRoute,
                            icon: _routeLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.directions),
                            label: Text(_routeLoading
                                ? 'Calculating...'
                                : 'Show Directions'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _buildRoute() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _routeLoading = true;
      _routeInfo = '';
    });

    try {
      final String originInput = _originController.text.trim();
      final String destinationInput = _destinationController.text.trim();

      LatLng origin;
      if (originInput.isEmpty || originInput.toLowerCase() == 'my location') {
        if (_currentPosition == null) {
          throw Exception('Current location is unavailable.');
        }
        origin =
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
      } else {
        final LatLng? geocodedOrigin =
            await GoogleMapsRouteService.geocodeAddress(originInput);
        if (geocodedOrigin == null) {
          throw Exception('Origin location could not be found.');
        }
        origin = geocodedOrigin;
      }

      LatLng destination;
      if (destinationInput.isNotEmpty) {
        final LatLng? geocodedDestination =
            await GoogleMapsRouteService.geocodeAddress(destinationInput);
        if (geocodedDestination == null) {
          throw Exception('Destination location could not be found.');
        }
        destination = geocodedDestination;
      } else if (_selectedDestinationId != null) {
        final selectedSpot = _spots.firstWhere(
          (spot) => spot.id == _selectedDestinationId,
          orElse: () => _spots.first,
        );
        destination = selectedSpot.position;
      } else {
        throw Exception('Please choose a destination.');
      }

      final RoutePlan routePlan = await GoogleMapsRouteService.getDirections(
        origin: origin,
        destination: destination,
        mode: 'walking',
      );

      setState(() {
        _routePoints = routePlan.points;
        _routeInfo =
            '${routePlan.summary} • ${routePlan.distanceText} • ${routePlan.durationText}';
        _polylines = <Polyline>{
          Polyline(
            polylineId: const PolylineId('route'),
            points: routePlan.points,
            color: Colors.blue,
            width: 6,
            patterns: <PatternItem>[PatternItem.dot, PatternItem.gap(8)],
            consumeTapEvents: true,
          ),
        };
      });

      if (_mapController != null && routePlan.points.isNotEmpty) {
        final bounds = _createBounds(routePlan.points);
        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, 90),
        );
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _routeLoading = false;
        });
      }
    }
  }

  LatLngBounds _createBounds(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      minLat = point.latitude < minLat ? point.latitude : minLat;
      maxLat = point.latitude > maxLat ? point.latitude : maxLat;
      minLng = point.longitude < minLng ? point.longitude : minLng;
      maxLng = point.longitude > maxLng ? point.longitude : maxLng;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
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
      _spots.map((CustomGeofenceSpot spot) {
        return Marker(
          markerId: MarkerId(spot.id),
          position: spot.position,
          zIndex: 2,
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
      polylines: _polylines,
      myLocationEnabled: _permissionGranted,
      myLocationButtonEnabled: _permissionGranted,
      zoomControlsEnabled: false,
      compassEnabled: true,
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
                    _routeInfo.isNotEmpty
                        ? 'Route: $_routeInfo'
                        : (_latestArrivalMessage ??
                            (_permissionGranted
                                ? (_currentPosition != null
                                    ? 'Live GPS active: tracking your real-time location.'
                                    : 'Tracking location and waiting for arrival...')
                                : 'Permission not granted yet.')),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
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
                            children: _spots.map((CustomGeofenceSpot spot) {
                              final bool active = _selectedSpot?.id == spot.id;
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
                                  child: Text(
                                    spot.name,
                                    style: TextStyle(
                                      color: active
                                          ? spot.accentColor
                                          : Colors.black87,
                                      fontWeight: FontWeight.w600,
                                    ),
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
