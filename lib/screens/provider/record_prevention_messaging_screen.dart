import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/client_service.dart';
import 'package:mediflow/services/prevention_messaging_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';
import 'package:mediflow/widgets/yes_no_field.dart';
import 'package:provider/provider.dart';

class RecordPreventionMessagingScreen extends StatefulWidget {
  const RecordPreventionMessagingScreen({super.key});

  @override
  State<RecordPreventionMessagingScreen> createState() => _RecordPreventionMessagingScreenState();
}

class _RecordPreventionMessagingScreenState extends State<RecordPreventionMessagingScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _isSaving = false;

  final _clientNameController = TextEditingController();
  final _ageController = TextEditingController();
  final _phoneController = TextEditingController();
  final _clientIdController = TextEditingController();

  String _sex = 'Male';
  final Set<String> _clientGroups = {};

  bool _firstTimeVisit = true;
  String? _referredFrom;

  bool _educatedHivPrevention = true;
  bool _educatedHivTesting = true;
  bool _educatedMalaria = true;

  static const List<String> _sexOptions = ['Male', 'Female', 'Other'];
  static const List<String> _groupOptions = ['GP', 'Pregnant', 'FSW', 'MSM', 'TG', 'PWID', 'AGYW'];
  static const List<String> _referredFromOptions = ['Self', 'IPCA', 'Others'];

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
      debugPrint('Failed to generate provisional client code: $e');
      setState(() => _clientIdController.text = 'UNK-UNK-ALL-0000000');
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

  String? _validateRequiredText(String? value) => (value ?? '').trim().isEmpty ? 'Required' : null;

  String? _validateClientGroups() => _clientGroups.isEmpty ? 'Select at least one client group' : null;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final ok = _formKey.currentState?.validate() ?? false;
    final groupErr = _validateClientGroups();

    if (!ok || groupErr != null) {
      if (groupErr != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(groupErr)));
      }
      return;
    }

    if ((_referredFrom ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Referred from is required')));
      return;
    }

    if (_isSaving) return;

    setState(() => _isSaving = true);
    try {
      final clientService = context.read<ClientService>();
      final resolvedClient = await clientService.createOrUpdateForCurrentProvider(
        name: _clientNameController.text.trim(),
        sex: _sex,
        phoneNumber: _phoneController.text.trim(),
        // IMPORTANT: keep existing client-code logic; backend allocates the stable unique code.
        desiredClientId: '',
      );

      if (!mounted) return;
      final stableClientId = (resolvedClient?.clientId ?? _clientIdController.text.trim()).trim().toUpperCase();
      if (stableClientId.isNotEmpty && stableClientId != _clientIdController.text.trim()) {
        setState(() => _clientIdController.text = stableClientId);
      }

      final service = context.read<PreventionMessagingService>();
      await service.createRecord(
        clientId: stableClientId,
        clientName: _clientNameController.text.trim(),
        age: int.parse(_ageController.text.trim()),
        phoneNumber: _phoneController.text.trim(),
        sex: _sex,
        clientGroups: _clientGroups.toList()..sort(),
        firstTimeVisit: _firstTimeVisit,
        referredFrom: _referredFrom!,
        educatedOnHivPrevention: _educatedHivPrevention,
        educatedOnHivTestingOptions: _educatedHivTesting,
        educatedOnMalariaPreventionTreatment: _educatedMalaria,
      );

      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Saved', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(
                'Prevention Messaging record saved successfully.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      );

      if (!mounted) return;
      context.pop();
    } catch (e) {
      debugPrint('Prevention Messaging save failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prevention Messaging'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        actions: const [AppAccountMenu()],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.paddingLg,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Client information', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _clientNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Client name', prefixIcon: Icon(Icons.person)),
                  validator: _validateRequiredText,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Age', prefixIcon: Icon(Icons.cake)),
                  validator: _validateAge,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Client telephone number', prefixIcon: Icon(Icons.phone)),
                  validator: _validatePhone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _clientIdController,
                  readOnly: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Client code / unique ID',
                    prefixIcon: const Icon(Icons.badge),
                    helperText: 'Auto-generated and saved with this record',
                    helperStyle: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  validator: _validateRequiredText,
                ),
                const SizedBox(height: 16),

                Text('Sex', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _sexOptions
                      .map(
                        (s) => ChoiceChip(
                          label: Text(s),
                          selected: _sex == s,
                          onSelected: (_) => setState(() => _sex = s),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 20),

                Text('Client Group (select one or more)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _groupOptions
                      .map((g) {
                        final selected = _clientGroups.contains(g);
                        return FilterChip(
                          label: Text(g),
                          selected: selected,
                          onSelected: (v) => setState(() {
                            if (v) {
                              _clientGroups.add(g);
                            } else {
                              _clientGroups.remove(g);
                            }
                          }),
                        );
                      })
                      .toList(),
                ),
                const SizedBox(height: 20),

                Text('Visit & referral', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                YesNoField(
                  label: 'First time visit?',
                  value: _firstTimeVisit,
                  onChanged: (v) => setState(() => _firstTimeVisit = v),
                  icon: Icons.repeat,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _referredFrom,
                  decoration: const InputDecoration(labelText: 'Referred from', prefixIcon: Icon(Icons.call_split)),
                  items: _referredFromOptions.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => setState(() => _referredFrom = v),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 20),

                Text('Education', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                YesNoField(
                  label: 'Client educated on HIV prevention services/transmission routes?',
                  value: _educatedHivPrevention,
                  onChanged: (v) => setState(() => _educatedHivPrevention = v),
                  icon: Icons.shield,
                ),
                const SizedBox(height: 12),
                YesNoField(
                  label: 'Client educated on HIV testing options, including HIVST?',
                  value: _educatedHivTesting,
                  onChanged: (v) => setState(() => _educatedHivTesting = v),
                  icon: Icons.fact_check,
                ),
                const SizedBox(height: 12),
                YesNoField(
                  label: 'Client educated on Malaria Prevention and Treatment?',
                  value: _educatedMalaria,
                  onChanged: (v) => setState(() => _educatedMalaria = v),
                  icon: Icons.bug_report,
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _submit,
                    icon: _isSaving
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary),
                          )
                        : Icon(Icons.save, color: scheme.onPrimary),
                    label: Text(_isSaving ? 'Saving...' : 'Save record', style: TextStyle(color: scheme.onPrimary)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
