import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

/// Root application widget configuring Material 3 theme and entry screen.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GeoPhoto Cache',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F51B5),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6FA),
        useMaterial3: true,
      ),
      home: const GeoPhotoHomePage(),
    );
  }
}

/// Main screen for capturing photos, tagging GPS coordinates, and caching data locally.
class GeoPhotoHomePage extends StatefulWidget {
  const GeoPhotoHomePage({super.key});

  @override
  State<GeoPhotoHomePage> createState() => _GeoPhotoHomePageState();
}

class _GeoPhotoHomePageState extends State<GeoPhotoHomePage> {
  // SharedPreferences storage keys
  static const String _keyImagePath = 'cached_image_path';
  static const String _keyLatitude = 'cached_latitude';
  static const String _keyLongitude = 'cached_longitude';
  static const String _keyLocationStatus = 'cached_location_status';
  static const String _keyTimestamp = 'cached_timestamp';

  final ImagePicker _picker = ImagePicker();

  String? _imagePath;
  double? _latitude;
  double? _longitude;
  String _locationStatus = 'No GPS data captured yet';
  String? _timestamp;

  bool _isProcessing = false;
  bool _isLocationDenied = false;
  String _statusMessage = 'Ready to capture a photo with GPS coordinates.';

  @override
  void initState() {
    super.initState();
    // Automatically restore cached photo and GPS data on app startup
    _loadCachedData();
  }

  /// Loads previously saved image path and GPS metadata from SharedPreferences.
  Future<void> _loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString(_keyImagePath);
    final savedLat = prefs.getDouble(_keyLatitude);
    final savedLng = prefs.getDouble(_keyLongitude);
    final savedLocStatus = prefs.getString(_keyLocationStatus);
    final savedTime = prefs.getString(_keyTimestamp);

    // Verify that the cached image file still exists on local storage
    String? validPath;
    if (savedPath != null && File(savedPath).existsSync()) {
      validPath = savedPath;
    }

    if (!mounted) return;
    setState(() {
      _imagePath = validPath;
      _latitude = savedLat;
      _longitude = savedLng;
      _locationStatus = savedLocStatus ?? 'No GPS data captured yet';
      _timestamp = savedTime;
      _isLocationDenied = _locationStatus == 'Location Permission Denied';
      if (validPath != null) {
        _statusMessage = 'Restored last photo & GPS data from local cache.';
      }
    });
  }

  /// Handles runtime permissions, camera capture, asynchronous GPS lookup, and local caching.
  Future<void> _capturePhotoAndTagLocation() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _isLocationDenied = false;
      _statusMessage = 'Requesting Camera & Location permissions...';
    });

    try {
      // Step 1: Request Camera permission (required for capturing photos)
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        _showFeedback(
          cameraStatus.isPermanentlyDenied
              ? 'Camera permission permanently denied. Enable it in Settings.'
              : 'Camera permission denied. Unable to open camera.',
          isError: true,
          showSettingsAction: cameraStatus.isPermanentlyDenied,
        );
        return;
      }

      // Step 2: Request Location permission (gracefully degrade without crashing if denied)
      final locationStatus = await Permission.locationWhenInUse.request();
      final bool hasLocationPermission = locationStatus.isGranted;

      if (!hasLocationPermission) {
        if (mounted) {
          setState(() => _isLocationDenied = true);
        }
        _showFeedback(
          locationStatus.isPermanentlyDenied
              ? 'Location permission permanently denied. Photo will be saved without GPS.'
              : 'Location permission denied. Photo will be saved without GPS coordinates.',
          isError: true,
          showSettingsAction: locationStatus.isPermanentlyDenied,
        );
      }

      // Step 3: Launch device camera to capture an image
      if (mounted) {
        setState(() => _statusMessage = 'Opening camera...');
      }
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (pickedFile == null) {
        if (mounted) {
          setState(() => _statusMessage = 'Photo capture cancelled.');
        }
        return;
      }

      // Step 4: Copy image to persistent app storage to survive OS cache cleanup and app restarts
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'geo_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final permanentPath = '${appDir.path}/$fileName';
      await File(pickedFile.path).copy(permanentPath);

      // Remove previous cached photo file to avoid accumulating unused storage
      await _deleteFileSafely(_imagePath);

      // Step 5: Retrieve GPS coordinates asynchronously with timeout and offline fallback
      double? lat;
      double? lng;
      String locText;

      if (hasLocationPermission) {
        if (mounted) {
          setState(() => _statusMessage = 'Fetching GPS coordinates...');
        }
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          locText = 'Device GPS Service Disabled';
        } else {
          try {
            final position = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 10),
              ),
            );
            lat = position.latitude;
            lng = position.longitude;
            locText = 'GPS Tagged Successfully';
          } catch (_) {
            // Fall back to last known device location when offline or indoors
            final lastPos = await Geolocator.getLastKnownPosition();
            if (lastPos != null) {
              lat = lastPos.latitude;
              lng = lastPos.longitude;
              locText = 'GPS Tagged (Last Known)';
            } else {
              locText = 'GPS Unavailable (Offline/Indoors)';
            }
          }
        }
      } else {
        locText = 'Location Permission Denied';
      }

      // Step 6: Persist image path and GPS metadata to SharedPreferences
      final nowStr = DateTime.now().toLocal().toString().substring(0, 19);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyImagePath, permanentPath);
      await prefs.setString(_keyLocationStatus, locText);
      await prefs.setString(_keyTimestamp, nowStr);

      if (lat != null && lng != null) {
        await prefs.setDouble(_keyLatitude, lat);
        await prefs.setDouble(_keyLongitude, lng);
      } else {
        await prefs.remove(_keyLatitude);
        await prefs.remove(_keyLongitude);
      }

      if (!mounted) return;
      setState(() {
        _imagePath = permanentPath;
        _latitude = lat;
        _longitude = lng;
        _locationStatus = locText;
        _timestamp = nowStr;
        _statusMessage = hasLocationPermission
            ? 'Saved photo & GPS data locally via SharedPreferences.'
            : 'Photo cached locally (GPS skipped: permission denied).';
      });
    } catch (e) {
      _showFeedback('Operation failed safely: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// Clears all cached entries in SharedPreferences and deletes the stored photo file.
  Future<void> _clearCache() async {
    await _deleteFileSafely(_imagePath);
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (!mounted) return;
    setState(() {
      _imagePath = null;
      _latitude = null;
      _longitude = null;
      _locationStatus = 'No GPS data captured yet';
      _timestamp = null;
      _isLocationDenied = false;
      _statusMessage = 'Local cache cleared.';
    });
  }

  /// Safely deletes a local file if it exists, ignoring filesystem errors.
  Future<void> _deleteFileSafely(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore cleanup failures to keep UI flow uninterrupted
    }
  }

  /// Displays user feedback via status banner and SnackBar with optional Settings shortcut.
  void _showFeedback(
      String message, {
        bool isError = false,
        bool showSettingsAction = false,
      }) {
    if (!mounted) return;
    setState(() => _statusMessage = message);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : const Color(0xFF3F51B5),
        action: showSettingsAction
            ? SnackBarAction(
          label: 'Settings',
          textColor: Colors.white,
          onPressed: openAppSettings,
        )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasCachedPhoto = _imagePath != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'GeoPhoto Cache',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey.shade200, height: 1),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status banner with optional permission recovery action
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _isLocationDenied
                      ? const Color(0xFFFFF4E5)
                      : const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isLocationDenied
                        ? Colors.orange.shade300
                        : Colors.indigo.shade100,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isLocationDenied
                          ? Icons.location_off_rounded
                          : Icons.verified_user_outlined,
                      color: _isLocationDenied
                          ? Colors.orange.shade800
                          : const Color(0xFF3F51B5),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusMessage,
                        style: TextStyle(
                          color: _isLocationDenied
                              ? Colors.orange.shade900
                              : Colors.indigo.shade900,
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (_isLocationDenied)
                      TextButton(
                        onPressed: openAppSettings,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Settings',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Captured photo preview card with cache badge overlay
              Container(
                height: 290,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: hasCachedPhoto
                    ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(_imagePath!),
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.save_rounded,
                              color: Colors.greenAccent,
                              size: 14,
                            ),
                            SizedBox(width: 5),
                            Text(
                              'Cached Locally',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
                    : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.add_a_photo_outlined,
                        size: 40,
                        color: Colors.indigo.shade400,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No Photo Captured Yet',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap the button below to take a GPS-tagged photo',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // GPS coordinates and metadata card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.location_on_rounded,
                            color: Color(0xFF3F51B5),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'GPS Coordinates & Cache Info',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Two-column coordinate metric boxes
                    Row(
                      children: [
                        Expanded(
                          child: _buildCoordinateBox(
                            label: 'LATITUDE',
                            value: _latitude != null
                                ? _latitude!.toStringAsFixed(6)
                                : '--',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildCoordinateBox(
                            label: 'LONGITUDE',
                            value: _longitude != null
                                ? _longitude!.toStringAsFixed(6)
                                : '--',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Divider(color: Colors.grey.shade200, height: 1),
                    const SizedBox(height: 12),

                    _buildMetadataRow('GPS Status', _locationStatus),
                    const SizedBox(height: 8),
                    _buildMetadataRow('Captured At', _timestamp ?? 'N/A'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Primary action buttons
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _capturePhotoAndTagLocation,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        backgroundColor: const Color(0xFF3F51B5),
                        foregroundColor: Colors.white,
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: _isProcessing
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Icon(Icons.camera_alt_rounded),
                      label: Text(
                        _isProcessing ? 'Processing...' : 'Capture & Tag GPS',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      onPressed:
                      (_isProcessing || !hasCachedPhoto) ? null : _clearCache,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        foregroundColor: Colors.red.shade600,
                        side: BorderSide(
                          color: hasCachedPhoto
                              ? Colors.red.shade200
                              : Colors.grey.shade300,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Clear',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a styled metric container for displaying latitude or longitude.
  Widget _buildCoordinateBox({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a single key-value row for secondary metadata display.
  Widget _buildMetadataRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            '$label:',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}