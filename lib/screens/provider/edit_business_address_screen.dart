import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import 'package:mediflow/models/user.dart' as app_models;
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/location_reference_service.dart';
import 'package:mediflow/utils/ng_locations.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class EditBusinessAddressScreen extends StatefulWidget {
  const EditBusinessAddressScreen({super.key});

  @override
  State<EditBusinessAddressScreen> createState() => _EditBusinessAddressScreenState();
}

class _EditBusinessAddressScreenState extends State<EditBusinessAddressScreen> {
  final _addressController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  String? _state;
  String? _lga;
  String? _ward;
  String? _legacyWardValue;
  String? _lastWardsKey;

  List<String> _wards = const [];
  bool _wardsLoading = false;
  String? _wardsLoadError;

  double? _lat;
  double? _lng;
  bool _saving = false;
  bool _locating = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app_models.User? user = context.read<AuthService>().currentUser;
    if (user == null) return;

    _addressController.text = user.businessAddress ?? '';

    final initialState = (user.state == 'FCT') ? 'Abuja FCT' : user.state;
    if (_state == null) _state = initialState;
    _lga ??= user.lga;

    // Keep the previous value around so we can detect mismatches once wards load.
    _legacyWardValue ??= (user.ward ?? '').trim().isEmpty ? null : user.ward!.trim();

    _lat ??= user.latitude;
    _lng ??= user.longitude;

    if (_latController.text.trim().isEmpty && _lat != null) {
      _latController.text = _lat!.toStringAsFixed(6);
    }
    if (_lngController.text.trim().isEmpty && _lng != null) {
      _lngController.text = _lng!.toStringAsFixed(6);
    }

    // Ward options depend on State+LGA.
    _loadWardsForSelection();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  double? _parseNullableDouble(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Future<void> _loadWardsForSelection() async {
    final s = (_state ?? '').trim();
    final l = (_lga ?? '').trim();

    final key = '${s.toLowerCase()}|${l.toLowerCase()}';
    if (s.isNotEmpty && l.isNotEmpty && _lastWardsKey == key && (_wards.isNotEmpty || _wardsLoadError != null)) return;
    _lastWardsKey = (s.isEmpty || l.isEmpty) ? null : key;

    if (s.isEmpty || l.isEmpty) {
      if (!mounted) return;
      setState(() {
        _wards = const [];
        _wardsLoading = false;
        _wardsLoadError = null;
        _ward = null;
      });
      return;
    }

    setState(() {
      _wardsLoading = true;
      _wardsLoadError = null;
    });

    try {
      final wards = await LocationReferenceService.fetchWards(state: s, lga: l);
      if (!mounted) return;

      // Preselect existing ward if it matches.
      final legacy = (_legacyWardValue ?? '').trim();
      final normalized = legacy.toLowerCase();
      final legacyMatches = legacy.isNotEmpty && wards.any((w) => w.toLowerCase() == normalized);

      setState(() {
        _wards = wards;
        _wardsLoading = false;
        _wardsLoadError = null;
        _wardInvalid = legacy.isNotEmpty && wards.isNotEmpty && !legacyMatches;
        _ward = legacyMatches ? wards.firstWhere((w) => w.toLowerCase() == normalized) : null;
      });
    } catch (e) {
      debugPrint('Failed to load wards: $e');
      if (!mounted) return;
      setState(() {
        _wards = const [];
        _wardsLoading = false;
        _wardsLoadError = e.toString();
        _ward = null;
      });
    }
  }

  bool _wardInvalid = false;

  void _showLocationMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? scheme.error : null,
        behavior: SnackBarBehavior.floating,
        action: (!kIsWeb && message.toLowerCase().contains('settings'))
            ? SnackBarAction(label: 'Open settings', textColor: scheme.onPrimary, onPressed: () => Geolocator.openAppSettings())
            : null,
      ),
    );
  }

  Future<void> _captureLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      // 1) Check if location services are enabled (GPS / system location).
      bool enabled;
      try {
        enabled = await Geolocator.isLocationServiceEnabled();
      } catch (e) {
        debugPrint('isLocationServiceEnabled failed: $e');
        _showLocationMessage(
          kIsWeb
              ? 'This browser does not support location, or location is blocked. You can enter coordinates manually.'
              : 'This device does not support location services. You can enter coordinates manually.',
          isError: true,
        );
        return;
      }
      if (!enabled) {
        _showLocationMessage('Location services are turned off. Please enable Location and try again.', isError: true);
        return;
      }

      // 2) Check permission status.
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // 3) Request permission if currently denied.
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _showLocationMessage('Location permission was denied. You can still enter coordinates manually.', isError: true);
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _showLocationMessage(
          'Location permission is permanently denied. Enable it in your device/browser settings, then try again.',
          isError: true,
        );
        return;
      }

      // 4) Read GPS coordinates only after permission is granted.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _latController.text = _lat!.toStringAsFixed(6);
        _lngController.text = _lng!.toStringAsFixed(6);
      });
      _showLocationMessage('Location captured successfully.');
    } catch (e) {
      debugPrint('Failed to capture location: $e');
      final raw = e.toString().toLowerCase();
      if (raw.contains('timeout') || raw.contains('timed out') || raw.contains('time limit')) {
        _showLocationMessage('Timed out while getting your GPS location. Try again or enter coordinates manually.', isError: true);
      } else if (raw.contains('location services are disabled')) {
        _showLocationMessage('Location services are turned off. Please enable Location and try again.', isError: true);
      } else if (raw.contains('permission')) {
        _showLocationMessage('Location permission is required to capture coordinates. You can enter them manually.', isError: true);
      } else {
        _showLocationMessage('Could not capture location. Please try again or enter coordinates manually.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user == null) return;

    final address = _addressController.text.trim();
    if (address.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your business address.')));
      return;
    }
    if ((_state ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select your State.')));
      return;
    }
    if ((_lga ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select your LGA.')));
      return;
    }

    // Ward validation rules:
    // - Ward dropdown is required for FieldProvider if wards exist for the selected LGA.
    // - If the reference table has no wards for this LGA, ward remains optional.
    // - If a ward is selected, it MUST be in the fetched list.
    final isFieldProvider = user.role == app_models.UserRole.fieldProvider;
    final wardSelected = (_ward ?? '').trim();

    if (_wardsLoading) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please wait while wards are loading.')));
      return;
    }

    if (_wards.isNotEmpty) {
      if (isFieldProvider && wardSelected.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select your Ward.')));
        return;
      }
      if (wardSelected.isNotEmpty && !_wards.contains(wardSelected)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selected Ward is not valid for the chosen LGA.')));
        return;
      }
      if (_wardInvalid) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your saved Ward does not match your selected LGA. Please choose a valid Ward.')));
        return;
      }
    }

    final latParsed = _parseNullableDouble(_latController.text);
    final lngParsed = _parseNullableDouble(_lngController.text);
    if (_latController.text.trim().isNotEmpty && latParsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Latitude must be a number.')));
      return;
    }
    if (_lngController.text.trim().isNotEmpty && lngParsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Longitude must be a number.')));
      return;
    }
    if (latParsed != null && (latParsed < -90 || latParsed > 90)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Latitude must be between -90 and 90.')));
      return;
    }
    if (lngParsed != null && (lngParsed < -180 || lngParsed > 180)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Longitude must be between -180 and 180.')));
      return;
    }

    setState(() => _saving = true);
    try {
      final updated = await auth.updateBusinessProfile(
        businessAddress: address,
        ward: wardSelected.isEmpty ? null : wardSelected,
        state: _state!,
        lga: _lga!,
        latitude: latParsed,
        longitude: lngParsed,
      );
      if (!mounted) return;
      if (updated) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Business profile updated')));
        context.pop();
      } else {
        final err = auth.lastBusinessProfileError;
        final msg = (err == null || err.trim().isEmpty) ? 'Failed to save. Please try again.' : err;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roleName = context.watch<AuthService>().currentUser?.effectiveRole.name;
    final lgas = NgLocations.lgasForState(_state);
    final states = NgLocations.statesForRole(roleName);

    final wardEnabled = (_lga ?? '').trim().isNotEmpty && !_wardsLoading;
    final wardHint = (_lga ?? '').trim().isEmpty
        ? 'Select LGA first'
        : (_wardsLoading ? 'Loading wards…' : (_wards.isEmpty ? 'No wards found for this LGA' : 'Select ward'));

    return Scaffold(
      appBar: AppBar(title: const Text('Business Address'), actions: const [AppAccountMenu()]),
      body: SafeArea(
        child: ListView(
          padding: AppSpacing.paddingLg,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: scheme.outline.withValues(alpha: 0.2))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Where should suppliers deliver?', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text('This address is attached to your stock requests.', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Business address',
                hintText: 'Street / Area / Landmark',
                filled: true,
                fillColor: scheme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _state,
              decoration: InputDecoration(
                labelText: 'State',
                filled: true,
                fillColor: scheme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
              ),
              items: states.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) {
                setState(() {
                  _state = v;
                  _lga = null;
                  _ward = null;
                  _wards = const [];
                  _wardsLoadError = null;
                  _wardsLoading = false;
                  _wardInvalid = false;
                  _lastWardsKey = null;
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: lgas.contains(_lga) ? _lga : null,
              decoration: InputDecoration(
                labelText: 'LGA',
                filled: true,
                fillColor: scheme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
              ),
              items: lgas.map((l) => DropdownMenuItem(value: l, child: Text(l, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: lgas.isEmpty
                  ? null
                  : (v) {
                      setState(() {
                        _lga = v;
                        _ward = null;
                        _wards = const [];
                        _wardsLoadError = null;
                        _wardsLoading = false;
                        _wardInvalid = false;
                      });
                      _loadWardsForSelection();
                    },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: (_ward != null && _wards.contains(_ward)) ? _ward : null,
              decoration: InputDecoration(
                labelText: 'Ward',
                hintText: wardHint,
                filled: true,
                fillColor: scheme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                errorText: _wardInvalid ? 'Saved ward does not belong to selected LGA' : null,
              ),
              items: _wards.map((w) => DropdownMenuItem(value: w, child: Text(w, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: !wardEnabled || _wards.isEmpty ? null : (v) => setState(() {
                _ward = v;
                _wardInvalid = false;
              }),
            ),
            if (_wardsLoadError != null) ...[
              const SizedBox(height: 10),
              Text('Could not load wards. You can still save without a ward.', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: scheme.outline.withValues(alpha: 0.2))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Geocoordinates (optional)', style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
                      TextButton.icon(
                        onPressed: _locating ? null : _captureLocation,
                        icon: Icon(Icons.my_location, color: scheme.primary),
                        label: Text(_locating ? 'Locating...' : 'Use current location', style: TextStyle(color: scheme.primary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (_lat == null || _lng == null) ? 'Not captured' : 'Lat: ${_lat!.toStringAsFixed(6)}  •  Lng: ${_lng!.toStringAsFixed(6)}',
                    style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _latController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          decoration: InputDecoration(
                            labelText: 'Latitude',
                            hintText: 'e.g. 6.524379',
                            filled: true,
                            fillColor: scheme.surface,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                          ),
                          onChanged: (v) => setState(() => _lat = double.tryParse(v.trim())),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _lngController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                          decoration: InputDecoration(
                            labelText: 'Longitude',
                            hintText: 'e.g. 3.379206',
                            filled: true,
                            fillColor: scheme.surface,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.2))),
                          ),
                          onChanged: (v) => setState(() => _lng = double.tryParse(v.trim())),
                        ),
                      ),
                    ],
                  ),
                  if (kIsWeb) ...[
                    const SizedBox(height: 8),
                    Text('Note: on web, location permission depends on browser settings and HTTPS.', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save, color: Colors.white),
                label: Text(_saving ? 'Saving...' : 'Save', style: const TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
