import 'package:flutter/foundation.dart';
import 'package:mediflow/models/prevention_messaging_record.dart';
import 'package:mediflow/supabase/supabase_config.dart';

class PreventionMessagingService extends ChangeNotifier {
  static const String _table = 'prevention_messaging_records';

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  final List<PreventionMessagingRecord> _records = [];
  List<PreventionMessagingRecord> get records => List.unmodifiable(_records);

  Future<void> initialize() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      final rows = await SupabaseService.select(_table, orderBy: 'createdAt', ascending: false, limit: 250);
      _records
        ..clear()
        ..addAll(rows.map(PreventionMessagingRecord.fromJson));
    } catch (e) {
      debugPrint('Failed to load prevention messaging records: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<int?> fetchMyTodayCount() async {
    try {
      final res = await SupabaseConfig.client.rpc('count_my_prevention_messaging_today');
      if (res is int) return res;
      if (res is num) return res.toInt();
      return int.tryParse(res.toString());
    } catch (e) {
      debugPrint('Failed to fetch prevention messaging today count: $e');
      return null;
    }
  }

  int localMyTodayCount(String myUserId) {
    final today = DateTime.now();
    final d0 = DateTime(today.year, today.month, today.day);
    final d1 = d0.add(const Duration(days: 1));
    return _records.where((r) => r.userId == myUserId && r.createdAt.isAfter(d0) && r.createdAt.isBefore(d1)).length;
  }

  Future<PreventionMessagingRecord?> createRecord({
    required String clientId,
    required String clientName,
    required int age,
    required String phoneNumber,
    required String sex,
    required List<String> clientGroups,
    required bool firstTimeVisit,
    required String referredFrom,
    required bool educatedOnHivPrevention,
    required bool educatedOnHivTestingOptions,
    required bool educatedOnMalariaPreventionTreatment,
  }) async {
    try {
      final payload = {
        'p_client_id': clientId.trim(),
        'p_client_name': clientName.trim(),
        'p_age': age,
        'p_phone_number': phoneNumber.trim(),
        'p_sex': sex.trim(),
        'p_client_groups': clientGroups,
        'p_first_time_visit': firstTimeVisit,
        'p_referred_from': referredFrom.trim(),
        'p_educated_on_hiv_prevention': educatedOnHivPrevention,
        'p_educated_on_hiv_testing_options': educatedOnHivTestingOptions,
        'p_educated_on_malaria_prevention_treatment': educatedOnMalariaPreventionTreatment,
      };

      final row = await SupabaseConfig.client.rpc('create_prevention_messaging_record', params: payload);
      if (row is! Map) return null;
      final rec = PreventionMessagingRecord.fromJson(Map<String, dynamic>.from(row));
      _records.insert(0, rec);
      notifyListeners();
      return rec;
    } catch (e) {
      debugPrint('Failed to create prevention messaging record: $e');
      rethrow;
    }
  }
}
