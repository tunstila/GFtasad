import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/test_record_service.dart';
import 'package:mediflow/services/inventory_service.dart';
import 'package:mediflow/services/delivery_service.dart';
import 'package:mediflow/services/notification_service.dart';
import 'package:mediflow/services/stock_alert_service.dart';
import 'package:mediflow/services/stock_request_service.dart';
import 'package:mediflow/services/client_service.dart';
import 'package:mediflow/services/fieldprovider_analytics_service.dart';
import 'package:mediflow/services/prevention_messaging_record_service.dart';
import 'package:mediflow/supabase/supabase_config.dart';
import 'theme.dart';
import 'nav.dart';
import 'package:mediflow/screens/auth/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseConfig.initialize();

  final authService = AuthService();
  final testRecordService = TestRecordService();
  final preventionMessagingRecordService = PreventionMessagingRecordService();
  final inventoryService = InventoryService();
  final deliveryService = DeliveryService();
  final notificationService = NotificationService();
  final stockAlertService = StockAlertService();
  final stockRequestService = StockRequestService();
  final clientService = ClientService();
  final fieldProviderAnalyticsService = FieldProviderAnalyticsService();

  await Future.wait([
    authService.initialize(),
    testRecordService.initialize(),
    preventionMessagingRecordService.initialize(),
    inventoryService.initialize(),
    deliveryService.initialize(),
    notificationService.initialize(),
    stockAlertService.initialize(),
  ]);

  runApp(MyApp(
    authService: authService,
    testRecordService: testRecordService,
    preventionMessagingRecordService: preventionMessagingRecordService,
    inventoryService: inventoryService,
    deliveryService: deliveryService,
    notificationService: notificationService,
    stockAlertService: stockAlertService,
    stockRequestService: stockRequestService,
    clientService: clientService,
    fieldProviderAnalyticsService: fieldProviderAnalyticsService,
  ));
}

class MyApp extends StatefulWidget {
  final AuthService authService;
  final TestRecordService testRecordService;
  final PreventionMessagingRecordService preventionMessagingRecordService;
  final InventoryService inventoryService;
  final DeliveryService deliveryService;
  final NotificationService notificationService;
  final StockAlertService stockAlertService;
  final StockRequestService stockRequestService;
  final ClientService clientService;
  final FieldProviderAnalyticsService fieldProviderAnalyticsService;

  const MyApp({
    super.key,
    required this.authService,
    required this.testRecordService,
    required this.preventionMessagingRecordService,
    required this.inventoryService,
    required this.deliveryService,
    required this.notificationService,
    required this.stockAlertService,
    required this.stockRequestService,
    required this.clientService,
    required this.fieldProviderAnalyticsService,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _showStartupSplash = true;

  @override
  void initState() {
    super.initState();
    _hideSplashSoon();
  }

  Future<void> _hideSplashSoon() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    setState(() => _showStartupSplash = false);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.authService),
        ChangeNotifierProvider.value(value: widget.testRecordService),
        ChangeNotifierProvider.value(value: widget.preventionMessagingRecordService),
        ChangeNotifierProvider.value(value: widget.inventoryService),
        ChangeNotifierProvider.value(value: widget.deliveryService),
        ChangeNotifierProvider.value(value: widget.notificationService),
        ChangeNotifierProvider.value(value: widget.stockAlertService),
        ChangeNotifierProvider.value(value: widget.stockRequestService),
        ChangeNotifierProvider.value(value: widget.clientService),
        ChangeNotifierProvider.value(value: widget.fieldProviderAnalyticsService),
      ],
      child: MaterialApp.router(
        title: 'MediFlow',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.system,
        routerConfig: AppRouter.router,
        builder: (context, child) {
          return Stack(
            children: [
              if (child != null) child,
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_showStartupSplash,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: _showStartupSplash ? const SplashScaffold(key: ValueKey('startup_splash')) : const SizedBox.shrink(key: ValueKey('startup_empty')),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
