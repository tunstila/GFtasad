import 'package:flutter/foundation.dart';
import 'package:mediflow/models/business_address.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/supabase/supabase_config.dart';

class EnrollmentCounts {
  final int ppmv;
  final int cp;

  const EnrollmentCounts({required this.ppmv, required this.cp});
}

class EnrolledProviderRow {
  final String userId;
  final String name;
  final String email;
  final String? contactEmail;
  final UserRole role;
  final ProviderType? providerType;
  final String? state;
  final String? lga;
  final String? ward;
  final String? facilityName;
  final String? businessAddress;
  final DateTime createdAt;

  const EnrolledProviderRow({
    required this.userId,
    required this.name,
    required this.email,
    required this.contactEmail,
    required this.role,
    required this.providerType,
    required this.state,
    required this.lga,
    required this.ward,
    required this.facilityName,
    required this.businessAddress,
    required this.createdAt,
  });
}

class TestRecordAnalyticsRow {
  final String recordId;
  final String program;
  final String clientName;
  final String clientId;
  final DateTime testDate;
  final String providerId;
  final String? providerState;
  final String? providerLga;

  const TestRecordAnalyticsRow({
    required this.recordId,
    required this.program,
    required this.clientName,
    required this.clientId,
    required this.testDate,
    required this.providerId,
    required this.providerState,
    required this.providerLga,
  });
}

class SuperAdminAnalyticsService {
  static const String _usersTable = 'users';
  static const String _addressTable = 'user_business_addresses';
  static const String _testRecordsTable = 'test_records';

  /// Counts only FieldProviders with providerType of ppmv/cp.
  static Future<EnrollmentCounts> fetchEnrollmentCounts() async {
    try {
      // Schema-safe: some deployments use `providerType` (camelCase) only.
      // Selecting a non-existent column causes PostgREST to throw.
      List<dynamic> rows;
      try {
        rows = await SupabaseService.select(_usersTable, select: 'role,providerType');
      } catch (_) {
        // Fallback for older schemas that used snake_case.
        rows = await SupabaseService.select(_usersTable, select: 'role,provider_type');
      }
      var ppmv = 0;
      var cp = 0;
      for (final r in rows) {
        final role = (r['role'] ?? '').toString();
        if (role != UserRole.fieldProvider.name) continue;

        final ptRaw = (r['providerType'] ?? r['provider_type'] ?? '').toString().toLowerCase().trim();
        if (ptRaw == ProviderType.ppmv.name) ppmv++;
        if (ptRaw == ProviderType.cp.name) cp++;
      }
      return EnrollmentCounts(ppmv: ppmv, cp: cp);
    } catch (e) {
      debugPrint('Failed to fetch enrollment counts: $e');
      rethrow;
    }
  }

  /// Lists enrolled PPMV/CP with best-effort join to business address table.
  static Future<List<EnrolledProviderRow>> fetchEnrolledProviders({
    ProviderType? providerType,
    String? state,
    String? lga,
  }) async {
    try {
      // Schema-safe: build two select strings and fall back if PostgREST rejects unknown columns.
      final selectCamel = '''
        id,username,email,contactEmail,role,providerType,state,lga,facilityName,createdAt,
        $_addressTable(business_address,ward,state,lga,created_at,updated_at)
      ''';
      final selectSnake = '''
        id,username,email,contact_email,role,provider_type,state,lga,facility_name,created_at,
        $_addressTable(business_address,ward,state,lga,created_at,updated_at)
      ''';

      Future<List> runQuery({required String select, required String providerTypeCol, required String createdAtCol}) async {
        dynamic q = SupabaseConfig.client.from(_usersTable).select(select);
        q = q.eq('role', UserRole.fieldProvider.name);
        if (providerType != null) q = q.eq(providerTypeCol, providerType.name);
        if ((state ?? '').trim().isNotEmpty) q = q.eq('state', state);
        if ((lga ?? '').trim().isNotEmpty) q = q.eq('lga', lga);
        return (await q.order(createdAtCol, ascending: false)) as List;
      }

      List rows;
      try {
        rows = await runQuery(select: selectCamel, providerTypeCol: 'providerType', createdAtCol: 'createdAt');
      } catch (_) {
        rows = await runQuery(select: selectSnake, providerTypeCol: 'provider_type', createdAtCol: 'created_at');
      }

      return rows.map((raw) {
        final r = (raw as Map).cast<String, dynamic>();
        final embeddedAddr = (r[_addressTable] as List?)?.cast<Map>().firstOrNull;
        final addr = embeddedAddr == null ? null : BusinessAddress.fromJson(embeddedAddr.cast<String, dynamic>());

        final createdRaw = r['createdAt'] ?? r['created_at'];
        final createdAt = createdRaw == null ? DateTime.now() : (DateTime.tryParse(createdRaw.toString()) ?? DateTime.now());

        final providerTypeRaw = (r['providerType'] ?? r['provider_type'])?.toString();
        final pt = providerTypeRaw == null
            ? null
            : ProviderType.values.firstWhere((e) => e.name == providerTypeRaw, orElse: () => ProviderType.ppmv);

        return EnrolledProviderRow(
          userId: (r['id'] ?? '').toString(),
          name: (r['username'] ?? '').toString().trim().isEmpty ? 'Unknown' : (r['username'] ?? '').toString(),
          email: (r['email'] ?? '').toString(),
          contactEmail: (r['contactEmail'] ?? r['contact_email'])?.toString(),
          role: UserRole.values.firstWhere((e) => e.name == (r['role'] ?? '').toString(), orElse: () => UserRole.fieldProvider),
          providerType: pt,
          state: (addr?.state.isNotEmpty == true) ? addr!.state : (r['state']?.toString()),
          lga: (addr?.lga.isNotEmpty == true) ? addr!.lga : (r['lga']?.toString()),
          ward: addr?.ward,
          facilityName: (r['facilityName'] ?? r['facility_name'])?.toString(),
          businessAddress: addr?.businessAddress ?? r['businessAddress']?.toString(),
          createdAt: createdAt,
        );
      }).toList();
    } catch (e) {
      debugPrint('Failed to fetch enrolled providers: $e');
      rethrow;
    }
  }

  /// Cumulative TestRecord list for drilldowns.
  ///
  /// Note: This uses a join to `users` via the FK (test_records.userId -> users.id).
  static Future<List<TestRecordAnalyticsRow>> fetchTestRecords({
    String? state,
    String? lga,
    String? program,
    DateTime? start,
    DateTime? end,
  }) async {
    try {
      final select = 'id,program,clientName,clientId,testDate,userId,users(state,lga)';
      dynamic q = SupabaseConfig.client.from(_testRecordsTable).select(select);

      if ((program ?? '').trim().isNotEmpty) q = q.eq('program', program);
      if ((start != null)) q = q.gte('testDate', start.toIso8601String());
      if ((end != null)) q = q.lte('testDate', end.toIso8601String());

      // We can only reliably filter by state/lga after fetching embedded user.
      // For performance you can create a view that denormalizes provider state/lga into test_records.

      final rows = (await q.order('testDate', ascending: false)) as List;
      final parsed = rows.map((raw) {
        final r = (raw as Map).cast<String, dynamic>();
        final user = (r['users'] as Map?)?.cast<String, dynamic>();
        final testDateRaw = r['testDate'] ?? r['test_date'];
        final testDate = testDateRaw == null ? DateTime.now() : (DateTime.tryParse(testDateRaw.toString()) ?? DateTime.now());

        return TestRecordAnalyticsRow(
          recordId: (r['id'] ?? '').toString(),
          program: (r['program'] ?? '').toString(),
          clientName: (r['clientName'] ?? r['client_name'] ?? '').toString(),
          clientId: (r['clientId'] ?? r['client_id'] ?? '').toString(),
          testDate: testDate,
          providerId: (r['userId'] ?? r['user_id'] ?? '').toString(),
          providerState: user?['state']?.toString(),
          providerLga: user?['lga']?.toString(),
        );
      }).toList();

      return parsed.where((r) {
        if ((state ?? '').trim().isNotEmpty && (r.providerState ?? '') != state) return false;
        if ((lga ?? '').trim().isNotEmpty && (r.providerLga ?? '') != lga) return false;
        return true;
      }).toList();
    } catch (e) {
      debugPrint('Failed to fetch test records analytics: $e');
      rethrow;
    }
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
