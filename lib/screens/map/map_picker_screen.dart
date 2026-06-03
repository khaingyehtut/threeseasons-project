import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:dio/dio.dart';
import '../../core/theme.dart';
import '../../core/constants.dart';

class MapPickerScreen extends StatefulWidget {
  final LatLng? initialPosition;
  final String? initialAddress;

  const MapPickerScreen({
    super.key,
    this.initialPosition,
    this.initialAddress,
  });

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  GoogleMapController? _mapController;

  // Default: Yangon, Myanmar
  static const _defaultPosition = LatLng(16.8661, 96.1951);

  late LatLng _pickedPosition;
  String _pickedAddress = '';
  bool _isLoadingAddress = false;
  bool _isLoadingLocation = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _pickedPosition = widget.initialPosition ?? _defaultPosition;
    _pickedAddress = widget.initialAddress ?? '';
    if (_pickedAddress.isEmpty) _reverseGeocode(_pickedPosition);
    // Ask for location permission as soon as the map opens
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissionOnOpen());
  }

  Future<void> _requestPermissionOnOpen() async {
    if (_disposed) return;
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    } else if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      // Only auto-locate if the device GPS is actually on.
      // If it's off, stay silent — the user can tap the button manually.
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!_disposed && serviceEnabled) await _goToCurrentLocation();
    }
  }

  Future<void> _reverseGeocode(LatLng position) async {
    if (_disposed) return;
    setState(() => _isLoadingAddress = true);
    try {
      String address = '';

      if (kIsWeb) {
        // geocoding package doesn't support web — use REST API
        final response = await Dio().get(
          'https://maps.googleapis.com/maps/api/geocode/json',
          queryParameters: {
            'latlng': '${position.latitude},${position.longitude}',
            'key': AppConstants.googleMapsApiKey,
          },
        );
        final results = response.data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          address = results.first['formatted_address'] as String? ?? '';
        }
      } else {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = [
            p.street,
            p.subLocality,
            p.locality,
            p.administrativeArea,
          ].where((s) => s != null && s.isNotEmpty).toList();
          address = parts.join(', ');
        }
      }

      if (_disposed || !mounted) return;
      setState(() => _pickedAddress = address);
    } catch (_) {
      if (!_disposed && mounted) setState(() => _pickedAddress = 'လိပ်စာ မတွေ့ပါ');
    } finally {
      if (!_disposed && mounted) setState(() => _isLoadingAddress = false);
    }
  }

  Future<void> _goToCurrentLocation() async {
    if (mounted) setState(() => _isLoadingLocation = true);
    try {
      // ── 1. Check device-level GPS switch ────────────────────────────────
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        final open = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text('GPS Disabled',
                style: GoogleFonts.poppins(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700)),
            content: Text(
              'Location services are turned off on your device.\n'
              'Please enable GPS in your device settings, then try again.',
              style: GoogleFonts.poppins(
                  color: AppColors.textMedium, fontSize: 13, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel',
                    style: GoogleFonts.poppins(color: AppColors.textMedium)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Open Settings',
                    style: GoogleFonts.poppins(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
        if (open == true) await Geolocator.openLocationSettings();
        return;
      }

      // ── 2. Check app-level permission ────────────────────────────────────
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnack('Location permission denied.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        final open = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text('Permission Required',
                style: GoogleFonts.poppins(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700)),
            content: Text(
              'Location permission was permanently denied.\n'
              'Enable it under Settings → App → Permissions.',
              style: GoogleFonts.poppins(
                  color: AppColors.textMedium, fontSize: 13, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel',
                    style: GoogleFonts.poppins(color: AppColors.textMedium)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Open Settings',
                    style: GoogleFonts.poppins(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
        if (open == true) await Geolocator.openAppSettings();
        return;
      }

      // ── 3. Get position ──────────────────────────────────────────────────
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (_disposed || !mounted) return;

      final newPos = LatLng(position.latitude, position.longitude);
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: newPos, zoom: 16),
        ),
      );
      setState(() => _pickedPosition = newPos);
      await _reverseGeocode(newPos);
    } catch (e) {
      _showSnack('Could not get location: $e');
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  void _onCameraMove(CameraPosition position) {
    _pickedPosition = position.target;
  }

  void _onCameraIdle() {
    if (!_disposed) _reverseGeocode(_pickedPosition);
  }

  void _confirmLocation() {
    _disposed = true;
    Navigator.pop(context, {
      'address': _pickedAddress,
      'lat': _pickedPosition.latitude,
      'lng': _pickedPosition.longitude,
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'ပို့ဆောင်ရမည့်နေရာ',
          style: GoogleFonts.poppins(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Stack(
        children: [
          // Map — bottom padding shifts the map's logical center up so it
          // stays in the visible area above the bottom address sheet (~210px)
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _pickedPosition,
              zoom: 15,
            ),
            onMapCreated: (c) => _mapController = c,
            onCameraMove: _onCameraMove,
            onCameraIdle: _onCameraIdle,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            padding: const EdgeInsets.only(bottom: 210),
          ),

          // Center pin — tip must align with the map's logical center.
          // With padding: bottom 210, Google Maps shifts its logical center
          // UP by 210/2 = 105px from screen center.
          // Offset = -(iconSize/2 + bottomPadding/2) = -(24 + 105) = -129
          Center(
            child: Transform.translate(
              offset: const Offset(0, -129),
              child: const Icon(
                Icons.location_pin,
                color: Color(0xFF6C63FF),
                size: 48,
              ),
            ),
          ),

          // Current location button
          Positioned(
            right: 12,
            bottom: 200,
            child: GestureDetector(
              onTap: _isLoadingLocation ? null : _goToCurrentLocation,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _isLoadingLocation
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : Icon(Icons.my_location_rounded,
                            color: AppColors.primary, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'လက်ရှိနေရာ',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom address card + confirm button
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  Text(
                    'ရွေးချယ်ထားသောနေရာ',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.textMedium,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),

                  Row(
                    children: [
                      Icon(Icons.location_on_rounded,
                          color: AppColors.primary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _isLoadingAddress
                            ? Row(children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('လိပ်စာ ရှာနေသည်...',
                                    style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: AppColors.textMedium)),
                              ])
                            : Text(
                                _pickedAddress.isEmpty
                                    ? 'မြေပုံကို ရွှေ့၍ နေရာရွေးချယ်ပါ'
                                    : _pickedAddress,
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  color: _pickedAddress.isEmpty
                                      ? AppColors.textMedium
                                      : AppColors.textPrimary,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Confirm button
                  GestureDetector(
                    onTap: _pickedAddress.isEmpty ? null : _confirmLocation,
                    child: Container(
                      width: double.infinity,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: _pickedAddress.isEmpty
                            ? LinearGradient(colors: [
                                AppColors.primary.withValues(alpha: 0.4),
                                const Color(0xFF9C8FFF).withValues(alpha: 0.4),
                              ])
                            : AppColors.gradient1,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          'နေရာ အတည်ပြုမည်',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
