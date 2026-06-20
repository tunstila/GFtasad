import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mediflow/models/stock_request.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/stock_request_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class StockRequestsScreen extends StatefulWidget {
  const StockRequestsScreen({super.key});

  @override
  State<StockRequestsScreen> createState() => _StockRequestsScreenState();
}

class _StockRequestsScreenState extends State<StockRequestsScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user != null) {
      context.read<StockRequestService>().loadForProvider(user.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    final service = context.watch<StockRequestService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Stock Requests'),
        actions: [
          IconButton(
            tooltip: 'New request',
            onPressed: () => context.push('/stock-requests/new'),
            icon: const Icon(Icons.add),
          ),
          const AppAccountMenu(),
        ],
      ),
      body: SafeArea(
        child: user == null
            ? const Center(child: Text('Not signed in'))
            : service.isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => service.loadForProvider(user.id),
                    child: ListView.separated(
                      padding: AppSpacing.paddingLg,
                      itemCount: service.providerRequests.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final req = service.providerRequests[index];
                        return _RequestCard(request: req, subtitle: 'To: ${req.supplierName}', onTap: () => context.push('/stock-requests/${req.id}'));
                      },
                    ),
                  ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final StockRequest request;
  final String subtitle;
  final VoidCallback onTap;

  const _RequestCard({required this.request, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = request.status;
    final statusColor = switch (status) {
      StockRequestStatus.pending => scheme.primary,
      StockRequestStatus.approved => Colors.orange,
      StockRequestStatus.rejected => scheme.error,
      StockRequestStatus.in_transit => Colors.blue,
      StockRequestStatus.delivered => Colors.green,
      StockRequestStatus.cancelled => scheme.error,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: scheme.outline.withValues(alpha: 0.2))),
        child: Row(
          children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.request_quote, color: statusColor)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${request.items.length} item(s)', style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(subtitle, style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Text('Status: ${status.name}', style: context.textStyles.labelMedium?.copyWith(color: statusColor, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
