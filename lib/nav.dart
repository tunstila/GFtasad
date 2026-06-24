import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:mediflow/models/test_record.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:provider/provider.dart';
import 'package:mediflow/screens/auth/splash_screen.dart';
import 'package:mediflow/screens/auth/login_screen.dart';
import 'package:mediflow/screens/auth/signup_screen.dart';
import 'package:mediflow/screens/auth/forgot_password_screen.dart';
import 'package:mediflow/screens/auth/force_password_change_screen.dart';
import 'package:mediflow/screens/provider/provider_home_screen.dart';
import 'package:mediflow/screens/provider/select_program_screen.dart';
import 'package:mediflow/screens/provider/record_test_screen.dart';
import 'package:mediflow/screens/provider/record_prevention_messaging_screen.dart';
import 'package:mediflow/screens/provider/inventory_screen.dart';
import 'package:mediflow/screens/provider/commodity_detail_screen.dart';
import 'package:mediflow/screens/provider/manual_stock_adjustment_screen.dart';
import 'package:mediflow/screens/provider/stock_movement_history_screen.dart';
import 'package:mediflow/screens/provider/deliveries_screen.dart';
import 'package:mediflow/screens/provider/delivery_detail_screen.dart';
import 'package:mediflow/screens/provider/confirm_receipt_screen.dart';
import 'package:mediflow/screens/provider/delivery_success_screen.dart';
import 'package:mediflow/screens/provider/provider_profile_screen.dart';
import 'package:mediflow/screens/provider/change_password_screen.dart';
import 'package:mediflow/screens/provider/sync_status_screen.dart';
import 'package:mediflow/screens/provider/notifications_screen.dart';
import 'package:mediflow/screens/provider/stock_alerts_screen.dart';
import 'package:mediflow/screens/provider/test_records_history_screen.dart';
import 'package:mediflow/screens/provider/prevention_messaging_records_history_screen.dart';
import 'package:mediflow/screens/provider/test_record_detail_screen.dart';
import 'package:mediflow/screens/provider/lifetime_tests_screen.dart';
import 'package:mediflow/screens/auth/pending_approval_screen.dart';
import 'package:mediflow/screens/admin/admin_users_screen.dart';
import 'package:mediflow/screens/admin/admin_dashboard_screen.dart';
import 'package:mediflow/screens/admin/fieldprovider_analytics_screen.dart';
import 'package:mediflow/screens/admin/superadmin_enrollment_screen.dart';
import 'package:mediflow/screens/admin/superadmin_test_records_analytics_screen.dart';
import 'package:mediflow/screens/admin/login_tracker_screen.dart';
import 'package:mediflow/screens/provider/request_stock_screen.dart';
import 'package:mediflow/screens/provider/stock_requests_screen.dart';
import 'package:mediflow/screens/provider/stock_request_detail_screen.dart';
import 'package:mediflow/screens/provider/supplier_stock_requests_screen.dart';
import 'package:mediflow/screens/provider/edit_business_address_screen.dart';
import 'package:mediflow/screens/national/national_malaria_dashboard_screen.dart';
import 'package:mediflow/screens/national/national_hivtb_dashboard_screen.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      // Global route guard based on current signed-in user and role.
      // This prevents deep-link access to admin/supplier-only routes.
      try {
        // Provider is available above MaterialApp.router (see main.dart).
        final auth = context.read<AuthService>();
        final user = auth.currentUser;
        final loc = state.matchedLocation;

        const publicRoutes = <String>{'/', '/login', '/signup', '/forgot-password'};
        final isPublic = publicRoutes.contains(loc);

        if (user == null) {
          // Allow public routes only.
          if (isPublic) return null;
          if (loc == '/force-password-change') return '/login';
          return '/login';
        }

        // Signed-in users shouldn't stay on login/signup.
        if (loc == '/login' || loc == '/signup') return auth.homeRouteForCurrentUser();

        // Force password change gate.
        if (user.forcePasswordChange && loc != '/force-password-change') return '/force-password-change';
        if (!user.forcePasswordChange && loc == '/force-password-change') return auth.homeRouteForCurrentUser();

        // Admin routes.
        if (loc.startsWith('/admin/users') && !user.hasSuperAdminFull) return auth.homeRouteForCurrentUser();
        if (loc.startsWith('/admin/dashboard') && !user.hasGlobalView) return auth.homeRouteForCurrentUser();
        if (loc.startsWith('/admin/enrollment') && !user.hasSuperAdminFull) return auth.homeRouteForCurrentUser();
        if (loc.startsWith('/admin/test-records-analytics') && !user.hasSuperAdminFull) return auth.homeRouteForCurrentUser();
        if (loc.startsWith('/admin/login-tracker') && !user.hasSuperAdminFull) return auth.homeRouteForCurrentUser();

        // National read-only dashboards.
        if (loc.startsWith('/national/malaria') && user.role != UserRole.nationalMalaria && !user.hasSuperAdminFull) return auth.homeRouteForCurrentUser();
        if (loc.startsWith('/national/hivtb') && user.role != UserRole.nationalHIVTB && !user.hasSuperAdminFull) return auth.homeRouteForCurrentUser();

        // Supplier-only routes.
        if (loc.startsWith('/supplier/') && user.role != UserRole.supplier && !user.hasSuperAdminFull) {
          return auth.homeRouteForCurrentUser();
        }

        // Provider-only operational routes.
        if (loc.startsWith('/record-test') && !user.effectiveRole.canRecordTests) return auth.homeRouteForCurrentUser();

        if (loc.startsWith('/record-prevention-messaging') && !user.effectiveRole.canRecordTests) return auth.homeRouteForCurrentUser();

        if (loc.startsWith('/lifetime-tests') && !user.effectiveRole.canRecordTests) return auth.homeRouteForCurrentUser();

        // TB program has been deprecated and must not be recordable via deep links.
        if (loc == '/record-test/tb' || loc.startsWith('/record-test/tb/')) return '/select-program';

        return null;
      } catch (_) {
        // If Provider isn't ready yet (rare during boot), don't block routing.
        return null;
      }
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/signup',
        builder: (context, state) => const SignupScreen(),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/force-password-change',
        builder: (context, state) => const ForcePasswordChangeScreen(),
      ),
      GoRoute(
        path: '/pending-approval',
        builder: (context, state) => PendingApprovalScreen(mode: state.uri.queryParameters['mode']),
      ),
      GoRoute(
        path: '/provider-home',
        builder: (context, state) => const ProviderHomeScreen(),
      ),
      GoRoute(
        path: '/select-program',
        builder: (context, state) => const SelectProgramScreen(),
      ),
      GoRoute(
        path: '/record-test/:program',
        builder: (context, state) {
          final program = state.pathParameters['program'] ?? 'malaria';
          return RecordTestScreen(programName: program);
        },
      ),
      GoRoute(
        path: '/record-prevention-messaging',
        builder: (context, state) => const RecordPreventionMessagingScreen(),
      ),
      GoRoute(
        path: '/inventory',
        builder: (context, state) => const InventoryScreen(),
      ),
      GoRoute(
        path: '/inventory/adjust',
        builder: (context, state) {
          final commodityId = state.uri.queryParameters['commodityId'];
          return ManualStockAdjustmentScreen(preselectedCommodityId: commodityId);
        },
      ),
      GoRoute(
        path: '/inventory/movements',
        builder: (context, state) {
          final commodityId = state.uri.queryParameters['commodityId'];
          return StockMovementHistoryScreen(preselectedCommodityId: commodityId);
        },
      ),
      GoRoute(
        path: '/inventory/:commodityId',
        builder: (context, state) {
          final commodityId = state.pathParameters['commodityId']!;
          return CommodityDetailScreen(commodityId: commodityId);
        },
      ),
      GoRoute(
        path: '/deliveries',
        builder: (context, state) => const DeliveriesScreen(),
      ),
      GoRoute(
        path: '/deliveries/:deliveryId',
        builder: (context, state) {
          final deliveryId = state.pathParameters['deliveryId']!;
          return DeliveryDetailScreen(deliveryId: deliveryId);
        },
      ),
      GoRoute(
        path: '/deliveries/:deliveryId/confirm',
        builder: (context, state) {
          final deliveryId = state.pathParameters['deliveryId']!;
          return ConfirmReceiptScreen(deliveryId: deliveryId);
        },
      ),
      GoRoute(
        path: '/deliveries/:deliveryId/success',
        builder: (context, state) {
          final deliveryId = state.pathParameters['deliveryId']!;
          return DeliverySuccessScreen(deliveryId: deliveryId);
        },
      ),
      GoRoute(
        path: '/provider-profile',
        builder: (context, state) => const ProviderProfileScreen(),
      ),
      GoRoute(
        path: '/provider-profile/address',
        builder: (context, state) => const EditBusinessAddressScreen(),
      ),
      GoRoute(
        path: '/change-password',
        builder: (context, state) => const ChangePasswordScreen(),
      ),
      GoRoute(
        path: '/sync-status',
        builder: (context, state) => const SyncStatusScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/stock-alerts',
        builder: (context, state) => const StockAlertsScreen(),
      ),

      GoRoute(
        path: '/test-records',
        builder: (context, state) {
          final program = state.uri.queryParameters['program'];
          final todayOnly = state.uri.queryParameters['today'] == '1';
          final startStr = state.uri.queryParameters['start'];
          final endStr = state.uri.queryParameters['end'];
          DateTimeRange? range;
          final start = startStr == null ? null : DateTime.tryParse(startStr);
          final end = endStr == null ? null : DateTime.tryParse(endStr);
          if (start != null && end != null) range = DateTimeRange(start: start, end: end);
          return TestRecordsHistoryScreen(
            initialProgram: program == null ? null : HealthProgram.values.where((p) => p.name == program).cast<HealthProgram?>().firstOrNull,
            todayOnly: todayOnly,
            initialDateRange: range,
          );
        },
        routes: [
          GoRoute(
            path: ':id',
            builder: (context, state) {
              final id = state.pathParameters['id']!;
              return TestRecordDetailScreen(recordId: id);
            },
          ),
        ],
      ),

      GoRoute(
        path: '/lifetime-tests',
        builder: (context, state) => const LifetimeTestsScreen(),
      ),

      GoRoute(
        path: '/admin/users',
        builder: (context, state) => const AdminUsersScreen(),
      ),
      GoRoute(
        path: '/admin/enrollment',
        builder: (context, state) {
          final pt = state.uri.queryParameters['providerType'];
          final parsed = switch (pt) {
            'ppmv' => ProviderType.ppmv,
            'cp' => ProviderType.cp,
            'chp' => ProviderType.chp,
            _ => null,
          };
          return SuperAdminEnrollmentScreen(initialProviderType: parsed);
        },
      ),
      GoRoute(
        path: '/prevention-messaging-records',
        builder: (context, state) {
          final today = state.uri.queryParameters['today'] == '1';
          return PreventionMessagingRecordsHistoryScreen(todayOnly: today);
        },
      ),
      GoRoute(
        path: '/admin/test-records-analytics',
        builder: (context, state) => const SuperAdminTestRecordsAnalyticsScreen(),
      ),
      GoRoute(
        path: '/admin/dashboard',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
      GoRoute(
        path: '/admin/login-tracker',
        builder: (context, state) => const LoginTrackerScreen(),
      ),
      GoRoute(
        path: '/admin/analytics/fieldproviders',
        builder: (context, state) {
          final initialState = state.uri.queryParameters['state'];
          final initialProviderType = state.uri.queryParameters['type'];
          return FieldProviderAnalyticsScreen(initialState: initialState, initialProviderType: initialProviderType);
        },
      ),

      GoRoute(
        path: '/national/malaria',
        builder: (context, state) => const NationalMalariaDashboardScreen(),
      ),

      GoRoute(
        path: '/national/hivtb',
        builder: (context, state) => const NationalHivtbDashboardScreen(),
      ),

      GoRoute(
        path: '/stock-requests',
        builder: (context, state) => const StockRequestsScreen(),
      ),
      GoRoute(
        path: '/stock-requests/new',
        builder: (context, state) => const RequestStockScreen(),
      ),
      GoRoute(
        path: '/stock-requests/:requestId',
        builder: (context, state) => StockRequestDetailScreen(requestId: state.pathParameters['requestId']!),
      ),
      GoRoute(
        path: '/supplier/stock-requests',
        builder: (context, state) => const SupplierStockRequestsScreen(),
      ),
      GoRoute(
        path: '/supplier/stock-requests/:requestId',
        builder: (context, state) => StockRequestDetailScreen(requestId: state.pathParameters['requestId']!, supplierView: true),
      ),
    ],
  );
}
