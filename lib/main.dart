import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyApp());
}

/// Data model representing a locally cached photo with GPS telemetry and user note.
class GeoPhotoRecord {
  final String id;
  final String imagePath;
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final double? accuracy;
  final double? speed;
  final String locationStatus;
  final String timestamp;
  final String note;

  const GeoPhotoRecord({
    required this.id,
    required this.imagePath,
    this.latitude,
    this.longitude,
    this.altitude,
    this.accuracy,
    this.speed,
    required this.locationStatus,
    required this.timestamp,
    this.note = '',
  });

  /// Creates a copy of this record with selectively updated fields.
  GeoPhotoRecord copyWith({
    String? note,
  }) {
    return GeoPhotoRecord(
      id: id,
      imagePath: imagePath,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      accuracy: accuracy,
      speed: speed,
      locationStatus: locationStatus,
      timestamp: timestamp,
      note: note ?? this.note,
    );
  }

  /// Serializes this record into a JSON-compatible map for SharedPreferences storage.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imagePath': imagePath,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'accuracy': accuracy,
      'speed': speed,
      'locationStatus': locationStatus,
      'timestamp': timestamp,
      'note': note,
    };
  }

  /// Deserializes a record from a JSON map stored in SharedPreferences.
  factory GeoPhotoRecord.fromJson(Map<String, dynamic> json) {
    return GeoPhotoRecord(
      id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      imagePath: json['imagePath'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      locationStatus: json['locationStatus'] as String? ?? 'Unknown',
      timestamp: json['timestamp'] as String? ?? '',
      note: json['note'] as String? ?? '',
    );
  }
}

/// Centralized Apple HIG color palette supporting Light and OLED Dark modes.
class ApplePalette {
  final bool isDark;

  const ApplePalette(this.isDark);

  Color get groupedBackground =>
      isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
  Color get cardSurface =>
      isDark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
  Color get secondarySurface =>
      isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
  Color get separator =>
      isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA);
  Color get primaryText =>
      isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
  Color get secondaryText =>
      isDark ? const Color(0xFF8E8E93) : const Color(0xFF6C6C70);
  Color get accentBlue =>
      isDark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);
  Color get systemGreen =>
      isDark ? const Color(0xFF30D158) : const Color(0xFF34C759);
  Color get systemOrange =>
      isDark ? const Color(0xFFFF9F0A) : const Color(0xFFFF9500);
  Color get systemRed =>
      isDark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30);
}

/// Root widget managing persisted Light/Dark theme state.
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  static const String _keyDarkMode = 'pref_is_dark_mode';
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  /// Restores saved Light/Dark theme mode from SharedPreferences.
  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDark = prefs.getBool(_keyDarkMode) ?? false;
    if (!mounted) return;
    setState(() => _isDarkMode = savedDark);
  }

  /// Toggles theme mode and persists the preference locally.
  Future<void> _toggleTheme() async {
    HapticFeedback.selectionClick();
    final nextMode = !_isDarkMode;
    setState(() => _isDarkMode = nextMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkMode, nextMode);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ApplePalette(_isDarkMode);

    return MaterialApp(
      title: 'GeoPhoto',
      debugShowCheckedModeBanner: false,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: palette.groupedBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AFF),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF000000),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0A84FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: GeoPhotoHomePage(
        isDarkMode: _isDarkMode,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}

/// Main Apple-styled workspace for photo capture, GPS telemetry, and offline caching.
class GeoPhotoHomePage extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  const GeoPhotoHomePage({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  State<GeoPhotoHomePage> createState() => _GeoPhotoHomePageState();
}

class _GeoPhotoHomePageState extends State<GeoPhotoHomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const String _keyRecordsJson = 'cached_geo_photo_records_v2';

  final ImagePicker _picker = ImagePicker();

  // Persisted photo records and active selection
  List<GeoPhotoRecord> _records = [];
  int _selectedIndex = 0;

  // Sensor & permission states
  bool _cameraGranted = false;
  bool _locationGranted = false;
  bool _isLocationDeniedBannerVisible = false;

  // Live GPS tracking states
  bool _isLiveTracking = false;
  StreamSubscription<Position>? _positionStreamSub;
  double? _liveLat;
  double? _liveLng;
  double? _liveAlt;
  double? _liveAcc;
  double? _liveSpeed;

  // UI feedback and inspector states
  bool _isProcessing = false;
  bool _isInspectorExpanded = false;
  String? _toastMessage;
  bool _toastIsError = false;
  Timer? _toastTimer;

  // Pulse animation for active GPS acquisition / tracking indicator
  late final AnimationController _pulseController;

  GeoPhotoRecord? get _activeRecord =>
      _records.isNotEmpty && _selectedIndex < _records.length
          ? _records[_selectedIndex]
          : null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _loadCachedRecords();
    _refreshPermissionStatuses();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionStreamSub?.cancel();
    _toastTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check permissions when user returns from system Settings
    if (state == AppLifecycleState.resumed) {
      _refreshPermissionStatuses();
    }
  }

  /// Updates the pulsing indicator animation state based on active sensor activity.
  void _syncPulseAnimation() {
    if (_isProcessing || _isLiveTracking) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  /// Checks current runtime status of Camera and Location permissions safely.
  Future<void> _refreshPermissionStatuses() async {
    try {
      final camStatus = await Permission.camera.status;
      final locStatus = await Permission.locationWhenInUse.status;
      if (!mounted) return;
      setState(() {
        _cameraGranted = camStatus.isGranted;
        _locationGranted = locStatus.isGranted;
        if (_locationGranted) {
          _isLocationDeniedBannerVisible = false;
        }
      });
    } catch (_) {
      // Ignore platform channel errors in headless widget test environments
    }
  }

  /// Restores the JSON list of cached records from SharedPreferences on app startup.
  Future<void> _loadCachedRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(_keyRecordsJson);
    if (rawJson == null || rawJson.isEmpty) return;

    try {
      final decoded = jsonDecode(rawJson) as List<dynamic>;
      final loaded = decoded
          .map((e) => GeoPhotoRecord.fromJson(e as Map<String, dynamic>))
          .where((record) => record.imagePath.isNotEmpty)
          .toList();

      if (!mounted) return;
      setState(() {
        _records = loaded;
        _selectedIndex = 0;
      });
    } catch (_) {
      // Safely ignore corrupted cache payloads without crashing
    }
  }

  /// Persists the current records list as a JSON string in SharedPreferences.
  Future<void> _saveRecordsToCache() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_records.map((r) => r.toJson()).toList());
    await prefs.setString(_keyRecordsJson, encoded);
  }

  /// Displays a floating iOS-style pill notification at the top of the screen.
  void _showFloatingPill(String message, {bool isError = false}) {
    _toastTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _toastMessage = message;
      _toastIsError = isError;
    });
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _toastMessage = null);
      }
    });
  }

  /// Requests an individual permission when tapping its status pill.
  Future<void> _handlePermissionPillTap(Permission permission, String label) async {
    HapticFeedback.lightImpact();
    try {
      final status = await permission.request();
      await _refreshPermissionStatuses();
      if (status.isGranted) {
        _showFloatingPill('$label permission granted');
      } else if (status.isPermanentlyDenied) {
        _showFloatingPill('$label blocked. Opening Settings...', isError: true);
        await openAppSettings();
      } else {
        _showFloatingPill('$label permission denied', isError: true);
      }
    } catch (_) {
      _showFloatingPill('Unable to request $label permission', isError: true);
    }
  }

  /// Handles Camera & Location permissions, captures a photo, fetches GPS, and caches locally.
  Future<void> _capturePhotoAndTagLocation() async {
    if (_isProcessing) return;
    HapticFeedback.mediumImpact();

    setState(() {
      _isProcessing = true;
    });
    _syncPulseAnimation();

    try {
      // Step 1: Request Camera permission (mandatory for capture)
      final cameraStatus = await Permission.camera.request();
      await _refreshPermissionStatuses();
      if (!cameraStatus.isGranted) {
        _showFloatingPill(
          cameraStatus.isPermanentlyDenied
              ? 'Camera blocked. Enable in Settings.'
              : 'Camera permission denied.',
          isError: true,
        );
        if (cameraStatus.isPermanentlyDenied) {
          await openAppSettings();
        }
        return;
      }

      // Step 2: Request Location permission (gracefully degrade without crashing if denied)
      final locationStatus = await Permission.locationWhenInUse.request();
      await _refreshPermissionStatuses();
      final bool hasLocationPermission = locationStatus.isGranted;

      if (!hasLocationPermission && mounted) {
        setState(() => _isLocationDeniedBannerVisible = true);
        _showFloatingPill(
          'Location denied — photo will save without GPS',
          isError: true,
        );
      }

      // Step 3: Capture photo via device camera
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (pickedFile == null) {
        _showFloatingPill('Capture cancelled');
        return;
      }

      // Step 4: Copy captured image to persistent documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'geo_photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final permanentPath = '${appDir.path}/$fileName';
      await File(pickedFile.path).copy(permanentPath);

      // Step 5: Asynchronously fetch GPS telemetry with timeout and offline fallback
      double? lat;
      double? lng;
      double? alt;
      double? acc;
      double? speed;
      String locText;

      if (hasLocationPermission) {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          locText = 'Device GPS Disabled';
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
            alt = position.altitude;
            acc = position.accuracy;
            speed = position.speed < 0 ? 0.0 : position.speed;
            locText = 'GPS Tagged Successfully';
          } catch (_) {
            final lastPos = await Geolocator.getLastKnownPosition();
            if (lastPos != null) {
              lat = lastPos.latitude;
              lng = lastPos.longitude;
              alt = lastPos.altitude;
              acc = lastPos.accuracy;
              speed = lastPos.speed < 0 ? 0.0 : lastPos.speed;
              locText = 'GPS Tagged (Last Known)';
            } else {
              locText = 'GPS Unavailable (Offline/Indoors)';
            }
          }
        }
      } else {
        locText = 'Location Permission Denied';
      }

      // Step 6: Prepend new record and persist to SharedPreferences
      final nowStr = DateTime.now().toLocal().toString().substring(0, 19);
      final newRecord = GeoPhotoRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        imagePath: permanentPath,
        latitude: lat,
        longitude: lng,
        altitude: alt,
        accuracy: acc,
        speed: speed,
        locationStatus: locText,
        timestamp: nowStr,
      );

      if (!mounted) return;
      setState(() {
        _records.insert(0, newRecord);
        _selectedIndex = 0;
      });
      await _saveRecordsToCache();

      _showFloatingPill(
        hasLocationPermission
            ? 'Photo & GPS cached locally'
            : 'Photo cached (GPS skipped)',
      );
    } catch (e) {
      _showFloatingPill('Handled error safely', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
        _syncPulseAnimation();
      }
    }
  }

  /// Toggles continuous live GPS telemetry streaming via Geolocator.
  Future<void> _toggleLiveTracking(bool enable) async {
    HapticFeedback.selectionClick();
    if (!enable) {
      await _positionStreamSub?.cancel();
      _positionStreamSub = null;
      if (!mounted) return;
      setState(() {
        _isLiveTracking = false;
      });
      _syncPulseAnimation();
      _showFloatingPill('Live GPS tracking stopped');
      return;
    }

    // Request permission before starting live stream
    final status = await Permission.locationWhenInUse.request();
    await _refreshPermissionStatuses();
    if (!status.isGranted) {
      if (mounted) {
        setState(() => _isLocationDeniedBannerVisible = true);
      }
      _showFloatingPill('Location permission required for live tracking', isError: true);
      return;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showFloatingPill('Please turn on device GPS service', isError: true);
      return;
    }

    setState(() => _isLiveTracking = true);
    _syncPulseAnimation();
    _showFloatingPill('Live GPS tracking active');

    _positionStreamSub?.cancel();
    _positionStreamSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    ).listen(
          (Position pos) {
        if (!mounted) return;
        setState(() {
          _liveLat = pos.latitude;
          _liveLng = pos.longitude;
          _liveAlt = pos.altitude;
          _liveAcc = pos.accuracy;
          _liveSpeed = pos.speed < 0 ? 0.0 : pos.speed;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _isLiveTracking = false);
        _syncPulseAnimation();
        _showFloatingPill('Live GPS stream interrupted', isError: true);
      },
    );
  }

  /// Copies active GPS coordinates to system clipboard and triggers haptic feedback.
  Future<void> _copyCoordinates(double? lat, double? lng) async {
    if (lat == null || lng == null) {
      _showFloatingPill('No coordinates available to copy', isError: true);
      return;
    }
    HapticFeedback.lightImpact();
    final formatted = '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
    await Clipboard.setData(ClipboardData(text: formatted));
    _showFloatingPill('Coordinates Copied');
  }

  /// Opens an Apple-styled bottom sheet to add or edit a note for the selected photo.
  Future<void> _openNoteEditor() async {
    final record = _activeRecord;
    if (record == null) return;

    final palette = ApplePalette(widget.isDarkMode);
    final controller = TextEditingController(text: record.note);

    final String? updatedNote = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            14,
            20,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.separator,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Photo Note',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: palette.primaryText,
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                    child: Text(
                      'Save',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: palette.accentBlue,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 3,
                style: TextStyle(color: palette.primaryText, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Add a location tag or note (e.g., UPM Library)...',
                  hintStyle: TextStyle(color: palette.secondaryText),
                  filled: true,
                  fillColor: palette.secondarySurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (updatedNote != null && mounted) {
      setState(() {
        _records[_selectedIndex] = record.copyWith(note: updatedNote);
      });
      await _saveRecordsToCache();
      _showFloatingPill('Note saved to local cache');
    }
  }

  /// Prompts an iOS alert dialog to delete a single cached photo record.
  Future<void> _confirmDeleteRecord(int index) async {
    HapticFeedback.lightImpact();
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Cached Photo?'),
        content: const Text(
          'This removes the photo file and its GPS metadata from local storage.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && index < _records.length) {
      final removed = _records[index];
      await _deleteFileSafely(removed.imagePath);
      if (!mounted) return;
      setState(() {
        _records.removeAt(index);
        if (_selectedIndex >= _records.length) {
          _selectedIndex = _records.isEmpty ? 0 : _records.length - 1;
        }
      });
      await _saveRecordsToCache();
      _showFloatingPill('Photo removed from cache');
    }
  }

  /// Prompts an iOS alert dialog to clear all cached photos and SharedPreferences entries.
  Future<void> _confirmClearAllCache() async {
    if (_records.isEmpty) return;
    HapticFeedback.mediumImpact();

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Clear All Cache?'),
        content: Text(
          'This will permanently delete all ${_records.length} cached photo(s) and GPS records.',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final record in _records) {
        await _deleteFileSafely(record.imagePath);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyRecordsJson);
      if (!mounted) return;
      setState(() {
        _records.clear();
        _selectedIndex = 0;
      });
      _showFloatingPill('All local cache cleared');
    }
  }

  /// Safely deletes a local file if it exists without interrupting app flow.
  Future<void> _deleteFileSafely(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore filesystem cleanup failures
    }
  }

  /// Returns a formatted file size string (KB/MB) for the Storage Inspector.
  String _getFormattedFileSize(String? path) {
    if (path == null || path.isEmpty) return '0 KB';
    try {
      final file = File(path);
      if (!file.existsSync()) return 'Missing';
      final bytes = file.lengthSync();
      if (bytes >= 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
      }
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } catch (_) {
      return 'N/A';
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ApplePalette(widget.isDarkMode);
    final active = _activeRecord;

    // Prioritize live telemetry values when Live Tracking is enabled
    final double? displayLat = _isLiveTracking ? (_liveLat ?? active?.latitude) : active?.latitude;
    final double? displayLng = _isLiveTracking ? (_liveLng ?? active?.longitude) : active?.longitude;
    final double? displayAlt = _isLiveTracking ? (_liveAlt ?? active?.altitude) : active?.altitude;
    final double? displayAcc = _isLiveTracking ? (_liveAcc ?? active?.accuracy) : active?.accuracy;
    final double? displaySpeed = _isLiveTracking ? (_liveSpeed ?? active?.speed) : active?.speed;
    final String displayLocStatus = _isLiveTracking
        ? 'Live GPS Stream Active'
        : (active?.locationStatus ?? 'No GPS data captured yet');

    return Scaffold(
      backgroundColor: palette.groupedBackground,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              // Apple Large Title collapsible navigation bar
              SliverAppBar(
                expandedHeight: 108,
                pinned: true,
                stretch: true,
                elevation: 0,
                scrolledUnderElevation: 0,
                backgroundColor: palette.groupedBackground.withValues(alpha: 0.92),
                flexibleSpace: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(left: 20, bottom: 14),
                  title: Text(
                    'GeoPhoto',
                    style: TextStyle(
                      color: palette.primaryText,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: widget.onToggleTheme,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: palette.cardSurface,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.separator, width: 0.5),
                        ),
                        child: Icon(
                          widget.isDarkMode
                              ? CupertinoIcons.sun_max_fill
                              : CupertinoIcons.moon_fill,
                          size: 18,
                          color: widget.isDarkMode
                              ? palette.systemOrange
                              : palette.accentBlue,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // Control Center style Permission Status Pills
                    Row(
                      children: [
                        Expanded(
                          child: _buildPermissionPill(
                            palette: palette,
                            icon: CupertinoIcons.camera_fill,
                            label: 'Camera',
                            granted: _cameraGranted,
                            onTap: () => _handlePermissionPillTap(
                              Permission.camera,
                              'Camera',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildPermissionPill(
                            palette: palette,
                            icon: CupertinoIcons.location_fill,
                            label: 'Location',
                            granted: _locationGranted,
                            onTap: () => _handlePermissionPillTap(
                              Permission.locationWhenInUse,
                              'Location',
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Graceful permission denial banner with direct Settings recovery
                    if (_isLocationDeniedBannerVisible) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: palette.systemOrange.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: palette.systemOrange.withValues(alpha: 0.4),
                            width: 0.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              CupertinoIcons.exclamationmark_triangle_fill,
                              color: palette.systemOrange,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Location permission denied. Photos are saved offline without GPS.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: palette.primaryText,
                                  height: 1.3,
                                ),
                              ),
                            ),
                            CupertinoButton(
                              padding: const EdgeInsets.only(left: 8),
                              minimumSize: Size.zero,
                              onPressed: openAppSettings,
                              child: Text(
                                'Settings',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: palette.systemOrange,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Main Photo Preview Card with Hero transition & AnimatedSwitcher
                    _buildPhotoCard(palette, active),

                    // Horizontal Filmstrip History Gallery
                    if (_records.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildHistoryFilmstrip(palette),
                    ],
                    const SizedBox(height: 16),

                    // GPS Telemetry & Live Tracking Card
                    _buildTelemetryCard(
                      palette: palette,
                      lat: displayLat,
                      lng: displayLng,
                      alt: displayAlt,
                      acc: displayAcc,
                      speed: displaySpeed,
                      statusText: displayLocStatus,
                      timestamp: active?.timestamp,
                    ),
                    const SizedBox(height: 16),

                    // Inset Grouped Photo Note Card
                    if (active != null) ...[
                      _buildNoteCard(palette, active),
                      const SizedBox(height: 16),
                    ],

                    // Collapsible Storage & Cache Inspector Card
                    _buildStorageInspector(palette, active),
                  ]),
                ),
              ),
            ],
          ),

          // Floating Top Pill Toast Notification
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            top: _toastMessage != null
                ? MediaQuery.of(context).padding.top + 10
                : -80,
            left: 24,
            right: 24,
            child: IgnorePointer(
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: (_toastIsError
                            ? palette.systemRed
                            : (widget.isDarkMode
                            ? const Color(0xFF2C2C2E)
                            : const Color(0xFF1C1C1E)))
                            .withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _toastIsError
                                ? CupertinoIcons.exclamationmark_circle_fill
                                : CupertinoIcons.checkmark_circle_fill,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _toastMessage ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Floating Frosted-Glass Bottom Action Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    MediaQuery.of(context).padding.bottom + 14,
                  ),
                  decoration: BoxDecoration(
                    color: palette.cardSurface.withValues(alpha: 0.82),
                    border: Border(
                      top: BorderSide(color: palette.separator, width: 0.5),
                    ),
                  ),
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _capturePhotoAndTagLocation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.accentBlue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                        palette.accentBlue.withValues(alpha: 0.55),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: _isProcessing
                          ? const CupertinoActivityIndicator(color: Colors.white)
                          : const Icon(CupertinoIcons.camera_fill, size: 20),
                      label: Text(
                        _isProcessing ? 'Processing...' : 'Capture & Tag GPS',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a Control Center style pill displaying live permission state.
  Widget _buildPermissionPill({
    required ApplePalette palette,
    required IconData icon,
    required String label,
    required bool granted,
    required VoidCallback onTap,
  }) {
    final statusColor = granted ? palette.systemGreen : palette.systemRed;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: palette.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.separator, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Icon(icon, size: 15, color: palette.primaryText),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.primaryText,
                ),
              ),
            ),
            Text(
              granted ? 'On' : 'Off',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: statusColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the main photo preview card with Hero full-screen launch and smooth transitions.
  Widget _buildPhotoCard(ApplePalette palette, GeoPhotoRecord? active) {
    final bool fileExists =
        active != null && File(active.imagePath).existsSync();

    return Container(
      height: 270,
      decoration: BoxDecoration(
        color: palette.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.separator, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: fileExists
            ? GestureDetector(
          key: ValueKey(active.id),
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).push(
              PageRouteBuilder(
                opaque: false,
                pageBuilder: (_, __, ___) => FullScreenPhotoPage(
                  record: active,
                ),
              ),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: 'photo_${active.id}',
                child: Image.file(
                  File(active.imagePath),
                  fit: BoxFit.cover,
                ),
              ),
              // Top-left zoom hint & top-right offline cache badge
              Positioned(
                top: 12,
                left: 12,
                child: _buildFrostedBadge(
                  icon: CupertinoIcons.arrow_up_left_arrow_down_right,
                  label: 'Tap to Zoom',
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: _buildFrostedBadge(
                  icon: CupertinoIcons.checkmark_shield_fill,
                  iconColor: palette.systemGreen,
                  label: 'Cached',
                ),
              ),
            ],
          ),
        )
            : Container(
          key: const ValueKey('empty_placeholder'),
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: palette.accentBlue.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  CupertinoIcons.camera,
                  size: 30,
                  color: palette.accentBlue,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'No Photo Captured Yet',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: palette.primaryText,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Capture a photo below to tag GPS coordinates and cache offline.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: palette.secondaryText,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a translucent dark pill overlay for photo badges.
  Widget _buildFrostedBadge({
    required IconData icon,
    required String label,
    Color iconColor = Colors.white,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          color: Colors.black.withValues(alpha: 0.5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 13),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds a horizontal filmstrip of cached photos with selection and single-item deletion.
  Widget _buildHistoryFilmstrip(ApplePalette palette) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _records.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = _records[index];
          final isSelected = index == _selectedIndex;
          final exists = File(item.imagePath).existsSync();

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _selectedIndex = index);
            },
            onLongPress: () => _confirmDeleteRecord(index),
            child: Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? palette.accentBlue : palette.separator,
                      width: isSelected ? 2.5 : 0.5,
                    ),
                    color: palette.secondarySurface,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: exists
                      ? Image.file(
                    File(item.imagePath),
                    fit: BoxFit.cover,
                  )
                      : Icon(
                    CupertinoIcons.photo,
                    color: palette.secondaryText,
                    size: 22,
                  ),
                ),
                // Quick delete badge on top-right corner of selected thumbnail
                if (isSelected)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _confirmDeleteRecord(index),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.xmark,
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Builds the 5-metric GPS telemetry card with Live Tracking toggle and Copy button.
  Widget _buildTelemetryCard({
    required ApplePalette palette,
    required double? lat,
    required double? lng,
    required double? alt,
    required double? acc,
    required double? speed,
    required String statusText,
    required String? timestamp,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.separator, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with pulsing indicator and one-tap copy button
          Row(
            children: [
              Icon(
                CupertinoIcons.location_north_fill,
                color: palette.accentBlue,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'GPS Telemetry',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: palette.primaryText,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (_isProcessing || _isLiveTracking) ...[
                FadeTransition(
                  opacity: Tween<double>(begin: 0.3, end: 1.0)
                      .animate(_pulseController),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: palette.systemGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                color: palette.secondarySurface,
                borderRadius: BorderRadius.circular(10),
                onPressed: () => _copyCoordinates(lat, lng),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.doc_on_doc,
                      size: 13,
                      color: palette.accentBlue,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Copy',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: palette.accentBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Row 1: Latitude & Longitude
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  palette: palette,
                  label: 'LATITUDE',
                  value: lat != null ? lat.toStringAsFixed(6) : '--',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  palette: palette,
                  label: 'LONGITUDE',
                  value: lng != null ? lng.toStringAsFixed(6) : '--',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Altitude, Accuracy & Speed
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  palette: palette,
                  label: 'ALTITUDE',
                  value: alt != null ? '${alt.toStringAsFixed(1)} m' : '--',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  palette: palette,
                  label: 'ACCURACY',
                  value: acc != null ? '±${acc.toStringAsFixed(1)} m' : '--',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  palette: palette,
                  label: 'SPEED',
                  value: speed != null ? '${speed.toStringAsFixed(1)} m/s' : '--',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: palette.separator, height: 1, thickness: 0.5),
          const SizedBox(height: 10),

          // Live GPS Tracking CupertinoSwitch row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Live GPS Tracking',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: palette.primaryText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              CupertinoSwitch(
                value: _isLiveTracking,
                activeTrackColor: palette.systemGreen,
                onChanged: _toggleLiveTracking,
              ),
            ],
          ),

          if (timestamp != null && timestamp.isNotEmpty) ...[
            const SizedBox(height: 10),
            Divider(color: palette.separator, height: 1, thickness: 0.5),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Captured At',
                  style: TextStyle(fontSize: 13, color: palette.secondaryText),
                ),
                Text(
                  timestamp,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: palette.primaryText,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Builds a single telemetry readout tile using tabular figures to prevent jitter.
  Widget _buildMetricTile({
    required ApplePalette palette,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: palette.secondarySurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: palette.secondaryText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: palette.primaryText,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the inset-grouped photo note card that opens a bottom sheet editor on tap.
  Widget _buildNoteCard(ApplePalette palette, GeoPhotoRecord record) {
    final hasNote = record.note.isNotEmpty;

    return GestureDetector(
      onTap: _openNoteEditor,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: palette.cardSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: palette.separator, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.doc_text_fill,
              color: palette.accentBlue,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Photo Note',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hasNote ? record.note : 'Tap to add a note or location tag...',
                    style: TextStyle(
                      fontSize: 14,
                      color: hasNote ? palette.primaryText : palette.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: palette.secondaryText,
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the collapsible iOS Settings style Storage & Cache Inspector panel.
  Widget _buildStorageInspector(ApplePalette palette, GeoPhotoRecord? active) {
    return Container(
      decoration: BoxDecoration(
        color: palette.cardSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.separator, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _isInspectorExpanded = !_isInspectorExpanded);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.tray_full_fill,
                    size: 18,
                    color: palette.secondaryText,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Storage & Cache Inspector',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: palette.primaryText,
                      ),
                    ),
                  ),
                  Text(
                    '${_records.length} item${_records.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 13,
                      color: palette.secondaryText,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _isInspectorExpanded
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    size: 15,
                    color: palette.secondaryText,
                  ),
                ],
              ),
            ),
          ),
          if (_isInspectorExpanded) ...[
            Divider(color: palette.separator, height: 1, thickness: 0.5),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildInspectorRow(
                    palette,
                    'Cache Engine',
                    'SharedPreferences (JSON)',
                  ),
                  const SizedBox(height: 10),
                  _buildInspectorRow(
                    palette,
                    'Persistence',
                    _records.isNotEmpty ? 'Persisted Offline' : 'Empty',
                  ),
                  const SizedBox(height: 10),
                  _buildInspectorRow(
                    palette,
                    'Active File Size',
                    _getFormattedFileSize(active?.imagePath),
                  ),
                  const SizedBox(height: 10),
                  _buildInspectorRow(
                    palette,
                    'Local Path',
                    active?.imagePath ?? 'N/A',
                  ),
                  if (_records.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: CupertinoButton(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        color: palette.systemRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        onPressed: _confirmClearAllCache,
                        child: Text(
                          'Clear All Local Cache',
                          style: TextStyle(
                            color: palette.systemRed,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Builds a key-value row inside the Storage & Cache Inspector.
  Widget _buildInspectorRow(ApplePalette palette, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: palette.secondaryText,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: palette.primaryText,
            ),
          ),
        ),
      ],
    );
  }
}

/// Full-screen iOS Photos style viewer supporting pinch-to-zoom and Hero transition.
class FullScreenPhotoPage extends StatelessWidget {
  final GeoPhotoRecord record;

  const FullScreenPhotoPage({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.5,
              child: Hero(
                tag: 'photo_${record.id}',
                child: Image.file(
                  File(record.imagePath),
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    MediaQuery.of(context).padding.top + 8,
                    16,
                    12,
                  ),
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.timestamp,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (record.latitude != null && record.longitude != null)
                              Text(
                                '${record.latitude!.toStringAsFixed(5)}, ${record.longitude!.toStringAsFixed(5)}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            CupertinoIcons.xmark,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}