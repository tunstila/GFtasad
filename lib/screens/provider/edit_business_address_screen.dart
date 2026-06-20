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

    // Ward options depend on State+LGA.
    _loadWardsForSelection();
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
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

  Future<void> _captureLocation() async {
    setState(() => _locating = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        throw Exception('Location services are disabled. Please enable location services and try again.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        throw Exception('Location permission not granted.');
      }

      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
      });
    } catch (e) {
      debugPrint('Failed to capture location: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not capture location: $e')));
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

    setState(() => _saving = true);
    try {
      final updated = await auth.updateBusinessProfile(
        businessAddress: address,
        ward: wardSelected.isEmpty ? null : wardSelected,
        state: _state!,
        lga: _lga!,
        latitude: _lat,
        longitude: _lng,
      );
      if (!mounted) return;
      if (updated) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Business profile updated')));
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save. Please try again.')));
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
