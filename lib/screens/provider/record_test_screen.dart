import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/client_service.dart';
import 'package:mediflow/services/test_record_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/program_badge.dart';
import 'package:mediflow/widgets/yes_no_field.dart';
import 'package:mediflow/widgets/app_account_menu.dart';
import 'package:uuid/uuid.dart';

class RecordTestScreen extends StatefulWidget {
  final String programName;

  const RecordTestScreen({super.key, required this.programName});

  @override
  State<RecordTestScreen> createState() => _RecordTestScreenState();
}

class _RecordTestScreenState extends State<RecordTestScreen> {
  static const _uuid = Uuid();
  final _formKey = GlobalKey<FormState>();
  late HealthProgram _program;
  late final bool _isUnsupportedProgram;

  bool _isSaving = false;

  // Common fields
  final _clientNameController = TextEditingController();
  final _clientIdController = TextEditingController();
  final _ageController = TextEditingController();
  final _phoneController = TextEditingController();
  String _sex = 'Male';
  bool _pregnant = false;
  VisitType _visitType = VisitType.newVisit;

  Timer? _clientLookupDebounce;
  bool _clientLookupLoading = false;

  // Malaria fields (expanded form)
  final _clientAddressController = TextEditingController();
  final _otherReferralSourceController = TextEditingController();
  final _dangerSignsReferralFacilityController = TextEditingController();

  final Set<String> _malariaClientGroups = {};
  final Set<String> _malariaSymptoms = {};

  bool? _firstTimeVisitYes;
  String? _referredFrom;
  String? _mRdtResult; // "Positive" | "Negative"
  String? _actGivenOption;
  bool? _referralForDangerSigns;

  // HIV fields
  bool? _hivCounselling;
  HIVPreviousTesting? _hivPreviousTesting;
  HTSType? _htsType;
  HIVSTKitType? _hivstKitType;
  HIVSTServiceDeliveryModel? _hivstServiceDeliveryModel;
  HIVTestResult? _hivTestResult;

  final Set<String> _hivClientGroups = {};
  String? _hivReferredFrom;

  final Set<String> _tbSymptoms = {};
  bool _suggestTBReferral = false;

  final Set<String> _referralServices = {};
  final _otherReferralServiceController = TextEditingController();

  final _referralFacilityController = TextEditingController();
  bool? _prepAssessed;
  bool? _prepEligible;
  bool? _prepOffered;
  bool? _prepAccepted;
  bool? _prepNewlyStarted;

  @override
  void initState() {
    super.initState();
    // TB is deprecated and must never be recordable.
    final supported = <String, HealthProgram>{
      HealthProgram.malaria.name: HealthProgram.malaria,
      HealthProgram.hiv.name: HealthProgram.hiv,
    };
    _program = supported[widget.programName] ?? HealthProgram.malaria;
    _isUnsupportedProgram = !supported.containsKey(widget.programName);

    // Always show a code (offline placeholder until backend allocation).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureClientIdGenerated();
    });
  }

  @override
  void dispose() {
    _clientNameController.dispose();
    _clientIdController.dispose();
    _ageController.dispose();
    _phoneController.dispose();
    _clientAddressController.dispose();
    _otherReferralSourceController.dispose();
    _dangerSignsReferralFacilityController.dispose();
    _clientLookupDebounce?.cancel();
    _otherReferralServiceController.dispose();
    _referralFacilityController.dispose();
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
    if (n > 100) return 'Maximum value: 100';
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

      // Auto-fill age if DOB exists (from existing client record) and age field is empty.
      final dob = client.dateOfBirth;
      if (dob != null && _ageController.text.trim().isEmpty) {
        final now = DateTime.now();
        var age = now.year - dob.year;
        final birthdayThisYear = DateTime(now.year, dob.month, dob.day);
        if (now.isBefore(birthdayThisYear)) age -= 1;
        if (age >= 0 && age <= 100) _ageController.text = age.toString();
      }
      setState(() {});
    } finally {
      if (mounted) setState(() => _clientLookupLoading = false);
    }
  }

  Future<void> _openClientCodeLookup() async {
    final controller = TextEditingController(text: _clientIdController.text.trim());
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final bottom = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 16 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Find existing client', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextFormField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Client code',
                  hintText: 'E.g. LAG-IKE-ALL-0000001',
                  prefixIcon: Icon(Icons.badge),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => context.pop(controller.text.trim()),
                      child: const Text('Use code'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    final trimmed = (code ?? '').trim();
    if (trimmed.isEmpty) return;
    setState(() => _clientIdController.text = trimmed.toUpperCase());
    unawaited(_maybeLookupClientById(trimmed));
  }

  Future<void> _saveTest({bool syncNow = false}) async {
    if (_isSaving) return;
    if (_isUnsupportedProgram) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This program is no longer supported.')),
        );
        context.pop();
      }
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final authService = context.read<AuthService>();
      final testRecordService = context.read<TestRecordService>();
      final clientService = context.read<ClientService>();

      // Phase 1 (fast): local commit only. Do NOT block on any network calls.
      // Ensure we always have a stable clientId for the record, even offline.
      final rawClientId = _clientIdController.text.trim();
      final isLocalPlaceholder = rawClientId.isEmpty || rawClientId.startsWith('LOCAL-');
      final localClientId = !isLocalPlaceholder
          ? rawClientId
          : ClientService.generateLocalProvisionalClientId(authService.currentUser);
      if (rawClientId.isEmpty) _clientIdController.text = localClientId;

       // Derivations for malaria for backwards compatibility fields.
       final malariaSymptoms = _malariaSymptoms.toList()..sort();
       final feverPresented = malariaSymptoms.contains('Fever');
       final mRdtPositive = _mRdtResult == 'Positive';

      final actLegacyBool = (_program == HealthProgram.malaria)
          ? (() {
              final v = (_actGivenOption ?? '').trim();
              if (v.isEmpty) return null;
              return v != 'None';
            })()
          : null;

      final record = TestRecord(
        id: _uuid.v4(),
        userId: authService.currentUser?.id ?? '',
        program: _program,
        clientName: _clientNameController.text,
        clientId: localClientId,
        age: int.tryParse(_ageController.text.trim()),
        dateOfBirth: null,
        phoneNumber: _phoneController.text.trim(),
        testDate: DateTime.now(),
        sex: _sex,
        pregnant: _sex == 'Female' ? _pregnant : null,
        visitType: (_program == HealthProgram.malaria)
            ? ((_firstTimeVisitYes == true) ? VisitType.newVisit : VisitType.returnVisit)
            : _visitType,

        clientAddress: (_program == HealthProgram.malaria || _program == HealthProgram.hiv) ? _clientAddressController.text.trim() : null,
        clientGroups: _program == HealthProgram.malaria
            ? (_malariaClientGroups.toList()..sort())
            : (_program == HealthProgram.hiv ? (_hivClientGroups.toList()..sort()) : null),
        firstTimeVisit: _program == HealthProgram.malaria ? _firstTimeVisitYes : null,
        referredFrom: _program == HealthProgram.malaria ? _referredFrom : (_program == HealthProgram.hiv ? _hivReferredFrom : null),
        otherReferralSource: () {
          if (_program == HealthProgram.malaria && _referredFrom == 'Others') return _otherReferralSourceController.text.trim();
          if (_program == HealthProgram.hiv && _hivReferredFrom == 'Others') return _otherReferralSourceController.text.trim();
          return null;
        }(),
        symptomsPresented: _program == HealthProgram.malaria ? malariaSymptoms : null,
        mRDTResult: _program == HealthProgram.malaria ? _mRdtResult : null,
        referralForDangerSigns: _program == HealthProgram.malaria ? _referralForDangerSigns : null,
        dangerSignsReferralFacility: _program == HealthProgram.malaria && _referralForDangerSigns == true ? _dangerSignsReferralFacilityController.text.trim() : null,

        // Legacy malaria fields (kept for existing dashboards/details that expect booleans)
        feverPresented: _program == HealthProgram.malaria ? feverPresented : null,
        mRDTTested: _program == HealthProgram.malaria ? true : null,
        mRDTPositive: _program == HealthProgram.malaria ? mRdtPositive : null,
        actGiven: _program == HealthProgram.malaria ? actLegacyBool : null,
        actGivenOption: _program == HealthProgram.malaria ? _actGivenOption : null,
        hivCounselling: _program == HealthProgram.hiv ? _hivCounselling : null,
        // Preserve legacy HIV columns for historical records, but do not write new data into them.
        hivstType: null,
        determineTest: null,
        artLinkage: null,

        hivPreviousTesting: _program == HealthProgram.hiv ? _hivPreviousTesting : null,
        htsType: _program == HealthProgram.hiv ? _htsType : null,
        hivstKitType: _program == HealthProgram.hiv && _htsType == HTSType.hivst ? _hivstKitType : null,
        hivstServiceDeliveryModel: _program == HealthProgram.hiv && _htsType == HTSType.hivst ? _hivstServiceDeliveryModel : null,
        hivTestResult: _program == HealthProgram.hiv ? _hivTestResult : null,
        tbSymptomsPresented: _program == HealthProgram.hiv ? (_tbSymptoms.toList()..sort()) : null,
        referralServices: _program == HealthProgram.hiv ? (_referralServices.toList()..sort()) : null,
        otherReferralService: _program == HealthProgram.hiv && _referralServices.contains('Other') ? _otherReferralServiceController.text.trim() : null,

        referralFacility: _program == HealthProgram.hiv && _referralFacilityController.text.isNotEmpty ? _referralFacilityController.text.trim() : null,
        prepAssessed: _program == HealthProgram.hiv ? _prepAssessed : null,
        prepEligible: _program == HealthProgram.hiv && _prepAssessed == true ? _prepEligible : null,
        prepOffered: _program == HealthProgram.hiv && _prepAssessed == true ? _prepOffered : null,
        prepAccepted: _program == HealthProgram.hiv && _prepAssessed == true ? _prepAccepted : null,
        prepStarted: _program == HealthProgram.hiv && _prepAssessed == true ? _prepNewlyStarted : null,
        // Never mark as synced until the backend confirms.
        syncStatus: SyncStatus.pending,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await testRecordService.addRecordLocal(record);

      // Phase 2: background sync (non-blocking) for Save & Sync.
      if (syncNow) {
        unawaited(() async {
          try {
            // If the user didn't provide a real clientId, allocate one via edge function
            // before syncing the test record.
            final wantsAllocation = rawClientId.isEmpty || rawClientId.startsWith('LOCAL-');
            if (wantsAllocation) {
              final client = await clientService.createOrUpdateForCurrentProvider(
                name: _clientNameController.text,
                sex: _sex,
                phoneNumber: _phoneController.text,
                // Backend allocates the sequential code; we do not send placeholders.
                desiredClientId: '',
              );
              final resolved = (client?.clientId ?? '').trim();
              if (resolved.isNotEmpty && resolved != localClientId) {
                await testRecordService.updateRecord(
                  record.copyWith(clientId: resolved, syncStatus: SyncStatus.pending, updatedAt: DateTime.now()),
                );
              }
            } else {
              // Still upsert the client record best-effort (but don't block the UI).
              await clientService.createOrUpdateForCurrentProvider(
                name: _clientNameController.text,
                sex: _sex,
                phoneNumber: _phoneController.text,
                // Only accept a strict, already-generated code.
                desiredClientId: rawClientId,
              );
            }

            await testRecordService.syncRecordInBackground(record.id);
          } catch (e) {
            debugPrint('RecordTestScreen background sync failed: $e');
            // Keep record pending/failed; user can retry via Sync Status.
          }
        }());
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(syncNow ? 'Saved locally. Syncing in background…' : 'Saved locally. Will sync when connected.'),
          ),
        );
        context.pop();
      }
    } catch (e) {
      debugPrint('RecordTestScreen: failed to save test: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to save test. Please try again.')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isUnsupportedProgram) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Record Test'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
          actions: const [AppAccountMenu()],
        ),
        body: Center(
          child: Padding(
            padding: AppSpacing.paddingLg,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block, size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 12),
                Text('Program not supported', style: context.textStyles.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(
                  'This program has been deprecated and can no longer be recorded from the app.',
                  style: context.textStyles.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: 220,
                  child: ElevatedButton(
                    onPressed: () => context.go('/select-program'),
                    child: const Text('Back to programs'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: ProgramBadge(program: _program),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: const [AppAccountMenu()],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: AppSpacing.paddingLg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Record ${_program.name.toUpperCase()} Test',
                  style: context.textStyles.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                _buildCommonFields(),
                const SizedBox(height: 24),
                if (_program == HealthProgram.malaria) _buildMalariaFields(),
                if (_program == HealthProgram.hiv) _buildHIVFields(),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSaving ? null : () => _saveTest(syncNow: false),
                        child: _isSaving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Save Offline'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : () => _saveTest(syncNow: true),
                        child: _isSaving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Save & Sync'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCommonFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _clientNameController,
          decoration: const InputDecoration(
            labelText: 'Client Name',
            prefixIcon: Icon(Icons.person),
          ),
          validator: (value) => value?.isEmpty == true ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _clientIdController,
          decoration: InputDecoration(
            labelText: 'Client code (generated)',
            prefixIcon: const Icon(Icons.badge),
            suffixIcon: IconButton(
              tooltip: 'Find existing client',
              onPressed: _isSaving ? null : _openClientCodeLookup,
              icon: const Icon(Icons.search),
            ),
          ),
          readOnly: true,
          onChanged: (v) {
            if (_program == HealthProgram.malaria) return;
            _clientLookupDebounce?.cancel();
            _clientLookupDebounce = Timer(const Duration(milliseconds: 450), () => _maybeLookupClientById(v));
            setState(() {});
          },
          onFieldSubmitted: (v) {
            if (_program == HealthProgram.malaria) return;
            _maybeLookupClientById(v);
          },
        ),
        ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Client code is generated by the backend. Offline, a placeholder is shown and will be replaced on sync.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _isSaving ? null : _ensureClientIdGenerated,
                icon: const Icon(Icons.refresh),
                label: const Text('Generate'),
              ),
            ],
          ),
        ],
        if (_clientLookupLoading) ...[
          const SizedBox(height: 8),
          Row(children: [const SizedBox(width: 6), const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 10), Text('Looking up client…', style: Theme.of(context).textTheme.bodySmall)]),
        ],
        const SizedBox(height: 16),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone number', prefixIcon: Icon(Icons.phone)),
          validator: _validatePhone,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _ageController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Age',
            hintText: 'Age (0 to 100). Limited to whole numbers',
            prefixIcon: Icon(Icons.calendar_today),
          ),
          validator: _validateAge,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _sex,
          decoration: const InputDecoration(
            labelText: 'Sex',
            prefixIcon: Icon(Icons.wc),
          ),
          items: const [
            DropdownMenuItem(value: 'Male', child: Text('Male')),
            DropdownMenuItem(value: 'Female', child: Text('Female')),
            DropdownMenuItem(value: 'Other', child: Text('Other')),
          ],
          onChanged: (value) => setState(() => _sex = value!),
        ),
        if (_sex == 'Female') ...[
          const SizedBox(height: 16),
          YesNoField(label: 'Pregnant', value: _pregnant, onChanged: (v) => setState(() => _pregnant = v), icon: Icons.pregnant_woman),
        ],
        const SizedBox(height: 16),
        if (_program == HealthProgram.malaria)
          DropdownButtonFormField<bool>(
            value: _firstTimeVisitYes,
            decoration: const InputDecoration(labelText: 'First time visit?', prefixIcon: Icon(Icons.event_repeat)),
            items: const [
              DropdownMenuItem(value: true, child: Text('Yes')),
              DropdownMenuItem(value: false, child: Text('No')),
            ],
            validator: (v) => v == null ? 'Required' : null,
            onChanged: (v) => setState(() => _firstTimeVisitYes = v),
          )
        else
          DropdownButtonFormField<VisitType>(
            value: _visitType,
            decoration: const InputDecoration(labelText: 'Visit Type', prefixIcon: Icon(Icons.event_repeat)),
            items: const [
              DropdownMenuItem(value: VisitType.newVisit, child: Text('New Visit')),
              DropdownMenuItem(value: VisitType.returnVisit, child: Text('Return Visit')),
            ],
            onChanged: (value) => setState(() => _visitType = value!),
          ),
      ],
    );
  }

  Widget _buildMalariaFields() {
    final showTbReferralPrompt = _malariaSymptoms.any((s) => s == 'Current Cough' || s == 'Weight Loss' || s == 'Night Sweats');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Malaria', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        TextFormField(
          controller: _clientAddressController,
          decoration: const InputDecoration(labelText: 'Client Address', prefixIcon: Icon(Icons.home)),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 16),
        _MultiSelectChipsFormField(
          label: 'Client Group',
          icon: Icons.groups,
          options: const ['GP', 'Pregnant', 'FSW', 'MSM', 'TG', 'PWID', 'AGYW'],
          selected: _malariaClientGroups,
          requiredSelection: false,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _referredFrom,
          decoration: const InputDecoration(labelText: 'Referred from', prefixIcon: Icon(Icons.login)),
          items: const [
            DropdownMenuItem(value: 'Self', child: Text('Self')),
            DropdownMenuItem(value: 'IPCA', child: Text('IPCA')),
            DropdownMenuItem(value: 'Others', child: Text('Others')),
          ],
          validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          onChanged: (v) {
            setState(() {
              _referredFrom = v;
              if (_referredFrom != 'Others') _otherReferralSourceController.clear();
            });
          },
        ),
        if (_referredFrom == 'Others') ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _otherReferralSourceController,
            decoration: const InputDecoration(labelText: 'Other referral source (optional)', prefixIcon: Icon(Icons.edit_note)),
          ),
        ],
        const SizedBox(height: 16),
        _MultiSelectChipsFormField(
          label: 'Symptoms Presented',
          icon: Icons.sick,
          options: const ['Fever', 'Current Cough', 'Weight Loss', 'Night Sweats'],
          selected: _malariaSymptoms,
          requiredSelection: true,
          onChanged: () => setState(() {}),
        ),
        if (showTbReferralPrompt) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Theme.of(context).colorScheme.tertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'TB referral prompt: Client has symptoms beyond only Fever. Please refer for TB services where appropriate.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onTertiaryContainer, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _mRdtResult,
          decoration: const InputDecoration(labelText: 'mRDT Tested?', prefixIcon: Icon(Icons.science)),
          items: const [
            DropdownMenuItem(value: 'Positive', child: Text('Positive')),
            DropdownMenuItem(value: 'Negative', child: Text('Negative')),
          ],
          validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          onChanged: (v) => setState(() => _mRdtResult = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _actGivenOption,
          decoration: const InputDecoration(labelText: 'ACT Given?', prefixIcon: Icon(Icons.medication)),
          items: const [
            DropdownMenuItem(value: 'TopMal', child: Text('TopMal')),
            DropdownMenuItem(value: 'Others', child: Text('Others')),
            DropdownMenuItem(value: 'None', child: Text('None')),
          ],
          validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          onChanged: (v) => setState(() => _actGivenOption = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<bool>(
          value: _referralForDangerSigns,
          decoration: const InputDecoration(labelText: 'Referral for danger signs?', prefixIcon: Icon(Icons.local_hospital)),
          items: const [
            DropdownMenuItem(value: true, child: Text('Yes')),
            DropdownMenuItem(value: false, child: Text('No')),
          ],
          validator: (v) => v == null ? 'Required' : null,
          onChanged: (v) {
            setState(() {
              _referralForDangerSigns = v;
              if (v != true) _dangerSignsReferralFacilityController.clear();
            });
          },
        ),
        if (_referralForDangerSigns == true) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _dangerSignsReferralFacilityController,
            decoration: const InputDecoration(labelText: 'Referral Facility', prefixIcon: Icon(Icons.local_hospital_outlined)),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
        ],
      ],
    );
  }

  Widget _buildHIVFields() {
    final scheme = Theme.of(context).colorScheme;
    final showPrepDetails = _prepAssessed == true;
    final hasReferral = _referralServices.isNotEmpty && !_referralServices.contains('No referral');
    final showOtherReferralSource = _hivReferredFrom == 'Others';
    final showOtherReferralService = _referralServices.contains('Other');
    final showHivstDetails = _htsType == HTSType.hivst;
    final showRecommendationReactive = _hivTestResult == HIVTestResult.reactive;
    final showRecommendationNonReactive = _hivTestResult == HIVTestResult.nonReactive;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Client Information', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        TextFormField(
          controller: _clientAddressController,
          decoration: const InputDecoration(labelText: 'Client address', prefixIcon: Icon(Icons.location_on_outlined)),
        ),
        const SizedBox(height: 12),
        _MultiSelectChipsFormField(
          label: 'Client Group',
          icon: Icons.groups_2_outlined,
          options: const ['GP', 'Pregnant', 'FSW', 'MSM', 'TG', 'PWID', 'AGYW'],
          selected: _hivClientGroups,
          requiredSelection: false,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 12),
        // Visit Type is captured in the shared (top) section for HIV.
        // We intentionally do not ask a duplicate "First time visit" question here.
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _hivReferredFrom,
          decoration: const InputDecoration(labelText: 'Referred from', prefixIcon: Icon(Icons.person_pin_circle_outlined)),
          items: const [
            DropdownMenuItem(value: 'Self', child: Text('Self')),
            DropdownMenuItem(value: 'IPCA', child: Text('IPCA')),
            DropdownMenuItem(value: 'Others', child: Text('Others')),
          ],
          validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          onChanged: (v) {
            setState(() {
              _hivReferredFrom = v;
              if (v != 'Others') _otherReferralSourceController.clear();
            });
          },
        ),
        if (showOtherReferralSource) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _otherReferralSourceController,
            decoration: const InputDecoration(labelText: 'Specify source', prefixIcon: Icon(Icons.edit_note_outlined)),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
        ],
        const SizedBox(height: 22),

        Text('Previous HIV Testing and Counselling', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        DropdownButtonFormField<HIVPreviousTesting>(
          value: _hivPreviousTesting,
          decoration: const InputDecoration(labelText: 'Tested for HIV before within this year?', prefixIcon: Icon(Icons.quiz_outlined)),
          items: const [
            DropdownMenuItem(value: HIVPreviousTesting.notPreviouslyTested, child: Text('Not previously tested')),
            DropdownMenuItem(value: HIVPreviousTesting.previouslyTestedNegative, child: Text('Previously tested negative')),
            DropdownMenuItem(value: HIVPreviousTesting.previouslyTestedPositive, child: Text('Previously tested positive')),
            DropdownMenuItem(value: HIVPreviousTesting.previouslyTestedPositiveNotOnCare, child: Text('Previously tested positive not on HIV care')),
          ],
          validator: (v) => v == null ? 'Required' : null,
          onChanged: (v) => setState(() => _hivPreviousTesting = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<bool>(
          value: _hivCounselling,
          decoration: const InputDecoration(labelText: 'HIV Counselling Provided?', prefixIcon: Icon(Icons.volunteer_activism_outlined)),
          items: const [
            DropdownMenuItem(value: true, child: Text('Yes')),
            DropdownMenuItem(value: false, child: Text('No')),
          ],
          validator: (v) => v == null ? 'Required' : null,
          onChanged: (v) => setState(() => _hivCounselling = v),
        ),
        const SizedBox(height: 22),

        Text('HIV Test Details', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        DropdownButtonFormField<HTSType>(
          value: _htsType,
          decoration: const InputDecoration(labelText: 'HTS Type', prefixIcon: Icon(Icons.science_outlined)),
          items: const [
            DropdownMenuItem(value: HTSType.hivst, child: Text('HIVST')),
            DropdownMenuItem(value: HTSType.determine, child: Text('Determine')),
          ],
          validator: (v) => v == null ? 'Required' : null,
          onChanged: (v) {
            setState(() {
              _htsType = v;
              if (v == HTSType.determine) {
                _hivstKitType = null;
                _hivstServiceDeliveryModel = null;
              }
            });
          },
        ),
        if (showHivstDetails) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<HIVSTKitType>(
            value: _hivstKitType,
            decoration: const InputDecoration(labelText: 'HIVST Type', prefixIcon: Icon(Icons.medical_services_outlined)),
            items: const [
              DropdownMenuItem(value: HIVSTKitType.oral, child: Text('Oral')),
              DropdownMenuItem(value: HIVSTKitType.bloodBased, child: Text('Blood-based')),
            ],
            validator: (v) => v == null ? 'Required' : null,
            onChanged: (v) => setState(() => _hivstKitType = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<HIVSTServiceDeliveryModel>(
            value: _hivstServiceDeliveryModel,
            decoration: const InputDecoration(labelText: 'HIVST Service Delivery Model', prefixIcon: Icon(Icons.support_agent_outlined)),
            items: const [
              DropdownMenuItem(value: HIVSTServiceDeliveryModel.assisted, child: Text('Assisted')),
              DropdownMenuItem(value: HIVSTServiceDeliveryModel.unassisted, child: Text('Unassisted')),
            ],
            validator: (v) => v == null ? 'Required' : null,
            onChanged: (v) => setState(() => _hivstServiceDeliveryModel = v),
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<HIVTestResult>(
          value: _hivTestResult,
          decoration: const InputDecoration(labelText: 'HIV test result', prefixIcon: Icon(Icons.rule_folder_outlined)),
          items: const [
            DropdownMenuItem(value: HIVTestResult.reactive, child: Text('Reactive')),
            DropdownMenuItem(value: HIVTestResult.nonReactive, child: Text('Non-reactive')),
          ],
          validator: (v) => v == null ? 'Required' : null,
          onChanged: (v) {
            setState(() {
              _hivTestResult = v;
              if (v == HIVTestResult.reactive) {
                // Suggest confirmatory referral but allow review.
                if (!_referralServices.contains('HIV Confirmatory testing') && !_referralServices.contains('No referral')) {
                  _referralServices.add('HIV Confirmatory testing');
                }
              }
            });
          },
        ),
        if (showRecommendationReactive) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.errorContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: scheme.error.withValues(alpha: 0.25)),
            ),
            child: Text('Reactive result: refer the client for confirmatory testing.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer, height: 1.4)),
          ),
        ],
        if (showRecommendationNonReactive) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: scheme.tertiary.withValues(alpha: 0.25)),
            ),
            child: Text('Non-reactive result: recommend retesting after 3 months.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onTertiaryContainer, height: 1.4)),
          ),
        ],

        const SizedBox(height: 22),
        Text('TB Screening', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        _MultiSelectChipsFormField(
          label: 'Symptoms Presented',
          icon: Icons.sick_outlined,
          options: const ['Fever', 'Current Cough', 'Weight loss', 'Night sweats'],
          selected: _tbSymptoms,
          requiredSelection: false,
          onChanged: () {
            final onlyFever = _tbSymptoms.isNotEmpty && _tbSymptoms.every((e) => e == 'Fever');
            final trigger = _tbSymptoms.isNotEmpty && !onlyFever;
            setState(() {
              _suggestTBReferral = trigger;
              if (trigger && !_referralServices.contains('TB presumptive') && !_referralServices.contains('No referral')) {
                _referralServices.add('TB presumptive');
              }
            });
          },
        ),
        if (_suggestTBReferral) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: scheme.tertiary.withValues(alpha: 0.25)),
            ),
            child: Text('TB referral prompt: symptoms beyond only Fever. Refer for TB services where appropriate.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onTertiaryContainer, height: 1.4)),
          ),
        ],

        const SizedBox(height: 22),
        Text('PrEP', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        DropdownButtonFormField<bool>(
          value: _prepAssessed,
          decoration: const InputDecoration(labelText: 'PrEP Assessed?', prefixIcon: Icon(Icons.fact_check_outlined)),
          items: const [
            DropdownMenuItem(value: true, child: Text('Yes')),
            DropdownMenuItem(value: false, child: Text('No')),
          ],
          validator: (v) => v == null ? 'Required' : null,
          onChanged: (v) {
            setState(() {
              _prepAssessed = v;
              if (v != true) {
                _prepEligible = null;
                _prepOffered = null;
                _prepAccepted = null;
                _prepNewlyStarted = null;
              }
            });
          },
        ),
        if (showPrepDetails) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<bool>(
            value: _prepEligible,
            decoration: const InputDecoration(labelText: 'PrEP Eligible?', prefixIcon: Icon(Icons.verified_outlined)),
            items: const [
              DropdownMenuItem(value: true, child: Text('Yes')),
              DropdownMenuItem(value: false, child: Text('No')),
            ],
            validator: (v) => v == null ? 'Required' : null,
            onChanged: (v) => setState(() => _prepEligible = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<bool>(
            value: _prepOffered,
            decoration: const InputDecoration(labelText: 'PrEP Offered?', prefixIcon: Icon(Icons.recommend_outlined)),
            items: const [
              DropdownMenuItem(value: true, child: Text('Yes')),
              DropdownMenuItem(value: false, child: Text('No')),
            ],
            validator: (v) => v == null ? 'Required' : null,
            onChanged: (v) => setState(() => _prepOffered = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<bool>(
            value: _prepAccepted,
            decoration: const InputDecoration(labelText: 'PrEP Accepted?', prefixIcon: Icon(Icons.thumb_up_alt_outlined)),
            items: const [
              DropdownMenuItem(value: true, child: Text('Yes')),
              DropdownMenuItem(value: false, child: Text('No')),
            ],
            validator: (v) => v == null ? 'Required' : null,
            onChanged: (v) => setState(() => _prepAccepted = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<bool>(
            value: _prepNewlyStarted,
            decoration: const InputDecoration(labelText: 'Client newly started on PrEP?', prefixIcon: Icon(Icons.play_circle_outline)),
            items: const [
              DropdownMenuItem(value: true, child: Text('Yes')),
              DropdownMenuItem(value: false, child: Text('No')),
            ],
            validator: (v) => v == null ? 'Required' : null,
            onChanged: (v) => setState(() => _prepNewlyStarted = v),
          ),
        ],

        const SizedBox(height: 22),
        Text('Referral', style: context.textStyles.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        _MultiSelectChipsFormField(
          label: 'Client referred for?',
          icon: Icons.local_hospital_outlined,
          options: const ['HIV Confirmatory testing', 'TB presumptive', 'STI services', 'GBV', 'Other', 'No referral'],
          selected: _referralServices,
          requiredSelection: false,
          onChanged: () {
            setState(() {
              if (_referralServices.contains('No referral') && _referralServices.length > 1) {
                _referralServices
                  ..clear()
                  ..add('No referral');
              }
              if (_referralServices.contains('No referral')) {
                _referralFacilityController.clear();
              }
              if (!_referralServices.contains('Other')) {
                _otherReferralServiceController.clear();
              }
            });
          },
        ),
        if (showOtherReferralService) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _otherReferralServiceController,
            decoration: const InputDecoration(labelText: 'Specify other referral', prefixIcon: Icon(Icons.edit_outlined)),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
        ],
        if (hasReferral) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _referralFacilityController,
            decoration: const InputDecoration(labelText: 'Referral Facility', prefixIcon: Icon(Icons.local_hospital)),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
        ],
      ],
    );
  }
}

class _MultiSelectChipsFormField extends FormField<Set<String>> {
  _MultiSelectChipsFormField({
    required String label,
    required IconData icon,
    required List<String> options,
    required Set<String> selected,
    required bool requiredSelection,
    required VoidCallback onChanged,
  }) : super(
          initialValue: selected,
          validator: (v) {
            if (!requiredSelection) return null;
            if (v == null || v.isEmpty) return 'Select at least one';
            return null;
          },
          builder: (state) {
            final theme = state.context;
            final scheme = Theme.of(theme).colorScheme;
            final err = state.errorText;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: label,
                    prefixIcon: Icon(icon),
                    errorText: err,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: options.map((opt) {
                      final isSelected = selected.contains(opt);
                      return FilterChip(
                        selected: isSelected,
                        label: Text(opt),
                        labelStyle: Theme.of(theme).textTheme.labelLarge?.copyWith(
                              color: isSelected ? scheme.onPrimary : scheme.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                        backgroundColor: scheme.surface,
                        selectedColor: scheme.primary,
                        checkmarkColor: scheme.onPrimary,
                        onSelected: (v) {
                          if (v) {
                            selected.add(opt);
                          } else {
                            selected.remove(opt);
                          }
                          state.didChange(selected);
                          onChanged();
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            );
          },
        );
}
