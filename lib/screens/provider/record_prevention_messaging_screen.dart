import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:mediflow/models/prevention_messaging_record.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/client_service.dart';
import 'package:mediflow/services/prevention_messaging_record_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';
import 'package:mediflow/widgets/yes_no_field.dart';

class RecordPreventionMessagingScreen extends StatefulWidget {
  const RecordPreventionMessagingScreen({super.key});

  @override
  State<RecordPreventionMessagingScreen> createState() => _RecordPreventionMessagingScreenState();
}

class _RecordPreventionMessagingScreenState extends State<RecordPreventionMessagingScreen> {
  static const _uuid = Uuid();
  final _formKey = GlobalKey<FormState>();

  bool _isSaving = false;

  final _clientNameController = TextEditingController();
  final _ageController = TextEditingController();
  final _phoneController = TextEditingController();
  final _clientIdController = TextEditingController();

  String _sex = 'Male';
  final Set<String> _clientGroups = {};

  bool? _firstTimeVisit;

  String _referredFrom = 'Self';
  final _referredFromOtherController = TextEditingController();

  bool? _educatedHivPrevention;
  bool? _educatedHivTesting;
  bool? _educatedMalaria;

  final Set<String> _referralServices = {};
  final _otherReferralServiceController = TextEditingController();
  final _referralFacilityController = TextEditingController();

  Timer? _clientLookupDebounce;
  bool _clientLookupLoading = false;

  static const _sexOptions = <String>['Male', 'Female', 'Other'];
  static const _clientGroupOptions = <String>['GP', 'Pregnant', 'FSW', 'MSM', 'TG', 'PWID', 'AGYW'];
  static const _referredFromOptions = <String>['Self', 'IPCA', 'Others'];
  static const _referralServiceOptions = <String>[
    'HIV Confirmatory testing',
    'TB presumptive',
    'STI services',
    'GBV',
    'Malaria services',
    'Other',
    'No referral',
  ];

  bool get _referredFromIsOther => _referredFrom.trim().toLowerCase() == 'others';
  bool get _referralHasNoReferral => _referralServices.any((e) => e.trim().toLowerCase() == 'no referral');
  bool get _referralHasOther => _referralServices.any((e) => e.trim().toLowerCase() == 'other');
  bool get _referralHasRealReferral => _referralServices.isNotEmpty && !_referralHasNoReferral;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureClientIdGenerated();
    });
  }

  @override
  void dispose() {
    _clientNameController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    _clientIdController.dispose();
    _referredFromOtherController.dispose();
    _otherReferralServiceController.dispose();
    _referralFacilityController.dispose();
    _clientLookupDebounce?.cancel();
    super.dispose();
  }

  void _ensureClientIdGenerated() {
    final current = _clientIdController.text.trim();
    if (current.isNotEmpty) return;
    try {
      final authUser = context.read<AuthService>().currentUser;
      final id = ClientService.generateLocalProvisionalClientId(authUser);
      setState(() => _clientIdController.text = id);
    } catch (e) {
      debugPrint('Failed to generate client code prefix, using fallback: $e');
      final id = 'UNK-UNK-UNK-${_uuid.v4().split('-').first.toUpperCase()}';
      setState(() => _clientIdController.text = id);
    }
  }

  static String? _validateAge(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return 'Required';
    final n = int.tryParse(raw);
    if (n == null) return 'Whole numbers only';
    if (n < 0) return 'Minimum value: 0';
    if (n > 120) return 'Maximum value: 120';
    return null;
  }

  static String? _validatePhone(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return 'Required';
    if (!RegExp(r'^0\d{10}$').hasMatch(raw)) return 'Phone number must start with 0 and be exactly 11 digits.';
    return null;
  }

  Future<void> _maybeLookupClientById(String raw) async {
    final id = raw.trim();
    if (id.isEmpty) return;
    setState(() => _clientLookupLoading = true);
    try {
      final client = await context.read<ClientService>().fetchByClientId(id);
      if (!mounted) return;
      if (client == null) return;

      _clientNameController.text = client.name;
      _phoneController.text = client.phoneNumber;
      if (client.sex.trim().isNotEmpty) _sex = client.sex;
      setState(() {});
    } catch (e) {
      debugPrint('Client lookup failed (prevention): $e');
    } finally {
      if (mounted) setState(() => _clientLookupLoading = false);
    }
  }

  void _onClientIdChanged(String value) {
    _clientLookupDebounce?.cancel();
    _clientLookupDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_maybeLookupClientById(value));
    });
  }

  void _toggleClientGroup(String v) {
    setState(() {
      if (_clientGroups.contains(v)) {
        _clientGroups.remove(v);
      } else {
        _clientGroups.add(v);
      }
    });
  }

  void _toggleReferralService(String v) {
    setState(() {
      final isNoReferral = v.trim().toLowerCase() == 'no referral';
      if (_referralServices.contains(v)) {
        _referralServices.remove(v);
      } else {
        if (isNoReferral) {
          _referralServices
            ..clear()
            ..add(v);
        } else {
          _referralServices.removeWhere((e) => e.trim().toLowerCase() == 'no referral');
          _referralServices.add(v);
        }
      }

      if (_referralHasNoReferral) {
        _referralFacilityController.text = '';
        _otherReferralServiceController.text = '';
      }
      if (!_referralHasOther) {
        _otherReferralServiceController.text = '';
      }
    });
  }

  Future<void> _save({required bool syncNow}) async {
    if (_isSaving) return;

    // Defensive sanitization (in addition to UI toggles): ensure `No referral` never
    // co-exists with other selections.
    if (_referralHasNoReferral && _referralServices.length > 1) {
      _referralServices
        ..removeWhere((e) => e.trim().toLowerCase() != 'no referral');
    }
    if (_referralHasRealReferral) {
      _referralServices.removeWhere((e) => e.trim().toLowerCase() == 'no referral');
    }

    // Pre-clear stale hidden values so they can't be submitted.
    if (!_referredFromIsOther) {
      _referredFromOtherController.text = '';
    }
    if (_referralHasNoReferral) {
      _referralFacilityController.text = '';
      _otherReferralServiceController.text = '';
    }
    if (!_referralHasOther) {
      _otherReferralServiceController.text = '';
    }

    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    if (_firstTimeVisit == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select First time visit.')));
      return;
    }
    if (_educatedHivPrevention == null || _educatedHivTesting == null || _educatedMalaria == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please answer all education questions.')));
      return;
    }

    if (_clientGroups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one Client Group.')));
      return;
    }

    if (_referralHasRealReferral && _referralFacilityController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Referral Facility is required when a referral is provided.')));
      return;
    }

    if (_referredFromIsOther && _referredFromOtherController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please specify the referral source.')));
      return;
    }

    if (_referralHasOther && _otherReferralServiceController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please specify the referral service.')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final auth = context.read<AuthService>();
      final authUser = auth.currentUser;
      if (authUser == null) throw StateError('Not authenticated');

      final now = DateTime.now();
      final localClientId = _clientIdController.text.trim();
      if (localClientId.isEmpty) throw StateError('Client code missing');
      final record = PreventionMessagingRecord(
        id: PreventionMessagingRecordService.newLocalId(),
        userId: authUser.id,
        clientName: _clientNameController.text.trim(),
        age: int.parse(_ageController.text.trim()),
        phoneNumber: _phoneController.text.trim(),
        clientId: localClientId,
        sex: _sex.trim(),
        clientGroups: _clientGroups.toList()..sort(),
        firstTimeVisit: _firstTimeVisit!,
        referredFrom: _referredFrom.trim(),
        otherReferredFrom: _referredFromIsOther ? _referredFromOtherController.text.trim() : null,
        educatedOnHivPrevention: _educatedHivPrevention!,
        educatedOnHivTestingOptions: _educatedHivTesting!,
        educatedOnMalariaPrevention: _educatedMalaria!,
        referralServices: _referralServices.toList()..sort(),
        otherReferralService: _referralHasOther ? _otherReferralServiceController.text.trim() : null,
        referralFacility: _referralHasRealReferral ? _referralFacilityController.text.trim() : null,
        syncStatus: SyncStatus.pending,
        createdAt: now,
        updatedAt: now,
      );

      final svc = context.read<PreventionMessagingRecordService>();
      await svc.addRecordLocal(record);

      if (syncNow) {
        unawaited(() async {
          try {
            // Best-effort: upsert client in background so backend has a canonical client row.
            final clientSvc = context.read<ClientService>();
            final client = await clientSvc.createOrUpdateForCurrentProvider(
              name: _clientNameController.text.trim(),
              sex: _sex.trim(),
              phoneNumber: _phoneController.text.trim(),
              // Do not block saving if offline; just try to reconcile server-side.
              desiredClientId: localClientId,
              ward: auth.currentUser?.ward,
            );
            if (client != null && client.clientId.trim().isNotEmpty && client.clientId.trim() != localClientId) {
              await svc.updateRecordLocal(record.copyWith(clientId: client.clientId.trim()));
            }
            await svc.syncRecordInBackground(record.id);
          } catch (e) {
            debugPrint('Prevention messaging background sync failed: $e');
          }
        }());
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(syncNow ? 'Saved. Syncing…' : 'Saved offline.')));
      context.pop();
    } catch (e) {
      debugPrint('Failed to save prevention messaging record: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save. Please try again.')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    final mustGate = user?.role.name == 'fieldProvider' && user?.hasCompleteBusinessLocation != true;
    if (mustGate) {
      final scheme = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Prevention Messaging'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          actions: const [AppAccountMenu()],
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: AppSpacing.paddingLg,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(color: scheme.error.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(24)),
                      child: Icon(Icons.location_off_outlined, color: scheme.error, size: 34),
                    ),
                    const SizedBox(height: 14),
                    Text('Business profile required', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    const Text('Please complete your Business Profile State, LGA, and Ward before recording tests.', textAlign: TextAlign.center),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => context.push('/provider-profile/address'),
                        icon: Icon(Icons.location_on_outlined, color: scheme.onPrimary),
                        label: Text('Go to Profile → Business', style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(onPressed: () => context.go('/select-program'), child: const Text('Back to programs')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prevention Messaging'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: const [AppAccountMenu()],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: AppSpacing.paddingLg,
            children: [
              _InfoCard(),
              const SizedBox(height: 16),
              _SectionTitle(title: 'Client details', icon: Icons.person_outline),
              const SizedBox(height: 12),
              TextFormField(
                controller: _clientNameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Client name', prefixIcon: Icon(Icons.badge_outlined)),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ageController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Age', prefixIcon: Icon(Icons.cake_outlined)),
                validator: _validateAge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Client telephone number', prefixIcon: Icon(Icons.phone_outlined)),
                validator: _validatePhone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _clientIdController,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'Client code / unique ID',
                  prefixIcon: const Icon(Icons.qr_code_2),
                  suffixIcon: _clientLookupLoading
                      ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                      : IconButton(
                          tooltip: 'Lookup existing client by code',
                          icon: const Icon(Icons.search),
                          onPressed: () {
                            final v = _clientIdController.text.trim();
                            if (v.isEmpty) return;
                            unawaited(_maybeLookupClientById(v));
                          },
                        ),
                ),
                onChanged: _onClientIdChanged,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _sex,
                decoration: const InputDecoration(labelText: 'Sex', prefixIcon: Icon(Icons.wc_outlined)),
                items: _sexOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: _isSaving ? null : (v) => setState(() => _sex = v ?? 'Male'),
              ),
              const SizedBox(height: 16),
              _SectionTitle(title: 'Client Group (multi-select)', icon: Icons.groups_outlined),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _clientGroupOptions.map((g) {
                  final selected = _clientGroups.contains(g);
                  return FilterChip(
                    selected: selected,
                    onSelected: _isSaving ? null : (_) => _toggleClientGroup(g),
                    label: Text(g),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              _SectionTitle(title: 'Visit', icon: Icons.event_repeat_outlined),
              const SizedBox(height: 10),
              YesNoField(
                label: 'First time visit?',
                value: _firstTimeVisit,
                onChanged: (v) {
                  if (_isSaving) return;
                  setState(() => _firstTimeVisit = v);
                },
              ),
              const SizedBox(height: 18),
              _SectionTitle(title: 'Referral source', icon: Icons.directions_outlined),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _referredFrom,
                decoration: const InputDecoration(labelText: 'Referred from', prefixIcon: Icon(Icons.near_me_outlined)),
                items: _referredFromOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: _isSaving
                    ? null
                    : (v) {
                        setState(() {
                          _referredFrom = v ?? 'Self';
                          if (!_referredFromIsOther) _referredFromOtherController.text = '';
                        });
                      },
              ),
              if (_referredFromIsOther) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _referredFromOtherController,
                  decoration: const InputDecoration(labelText: 'Specify source', prefixIcon: Icon(Icons.edit_note_outlined)),
                  validator: (v) => _referredFromIsOther && (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
              ],
              const SizedBox(height: 18),
              _SectionTitle(title: 'Education', icon: Icons.school_outlined),
              const SizedBox(height: 10),
              YesNoField(
                label: 'Client educated on HIV prevention services/transmission routes?',
                value: _educatedHivPrevention,
                onChanged: (v) {
                  if (_isSaving) return;
                  setState(() => _educatedHivPrevention = v);
                },
              ),
              const SizedBox(height: 12),
              YesNoField(
                label: 'Client educated on HIV testing options, including HIVST?',
                value: _educatedHivTesting,
                onChanged: (v) {
                  if (_isSaving) return;
                  setState(() => _educatedHivTesting = v);
                },
              ),
              const SizedBox(height: 12),
              YesNoField(
                label: 'Client educated on Malaria Prevention and Treatment?',
                value: _educatedMalaria,
                onChanged: (v) {
                  if (_isSaving) return;
                  setState(() => _educatedMalaria = v);
                },
              ),
              const SizedBox(height: 18),
              _SectionTitle(title: 'Referral services', icon: Icons.local_hospital_outlined),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _referralServiceOptions.map((s) {
                  final selected = _referralServices.contains(s);
                  return FilterChip(
                    selected: selected,
                    onSelected: _isSaving ? null : (_) => _toggleReferralService(s),
                    label: Text(s),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  );
                }).toList(),
              ),
              if (_referralHasOther && !_referralHasNoReferral) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _otherReferralServiceController,
                  decoration: const InputDecoration(labelText: 'Specify referral service', prefixIcon: Icon(Icons.edit_outlined)),
                  validator: (v) => _referralHasOther && !_referralHasNoReferral && (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
              ],
              if (_referralHasRealReferral) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _referralFacilityController,
                  decoration: const InputDecoration(labelText: 'Referral Facility', prefixIcon: Icon(Icons.apartment_outlined)),
                  validator: (v) => _referralHasRealReferral && (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving ? null : () => unawaited(_save(syncNow: false)),
                      icon: Icon(Icons.save_outlined, color: Theme.of(context).colorScheme.primary),
                      label: const Text('Save offline'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : () => unawaited(_save(syncNow: true)),
                      icon: Icon(Icons.cloud_upload, color: Theme.of(context).colorScheme.onPrimary),
                      label: Text(_isSaving ? 'Saving…' : 'Save & Sync'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Tip: Save offline works without internet; Sync will retry automatically.',
                style: context.textStyles.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.primary.withValues(alpha: 0.18), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.campaign_outlined, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Capture prevention education and referrals. Client code is generated and persisted by the app.',
              style: context.textStyles.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: cs.outline.withValues(alpha: 0.2))),
          child: Icon(icon, color: cs.primary, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
      ],
    );
  }
}
