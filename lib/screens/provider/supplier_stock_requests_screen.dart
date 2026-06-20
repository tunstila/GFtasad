import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:mediflow/models/stock_request.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/services/auth_service.dart';
import 'package:mediflow/services/stock_request_service.dart';
import 'package:mediflow/theme.dart';
import 'package:mediflow/widgets/app_account_menu.dart';

class SupplierStockRequestsScreen extends StatefulWidget {
  final String? status;

  const SupplierStockRequestsScreen({super.key, this.status});

  @override
  State<SupplierStockRequestsScreen> createState() => _SupplierStockRequestsScreenState();
}

class _SupplierStockRequestsScreenState extends State<SupplierStockRequestsScreen> {
  String? _loadedForUserId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    if (user != null && (user.role == UserRole.supplier || user.hasSuperAdminFull)) {
      if (_loadedForUserId != user.id) {
        _loadedForUserId = user.id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.read<StockRequestService>().loadForSupplier(user.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final user = auth.currentUser;
    final service = context.watch<StockRequestService>();

    final filter = (widget.status ?? '').trim().toLowerCase();
    final title = switch (filter) {
      'rejected' => 'Rejected Requests',
      'approved' => 'Fulfilled Requests',
      _ => 'Incoming Requests',
    };

    final requests = switch (filter) {
      'rejected' => service.supplierRequests.where((r) => r.status == StockRequestStatus.rejected).toList(),
      'approved' => service.supplierRequests.where((r) => r.status == StockRequestStatus.approved).toList(),
      _ => service.supplierRequests.where((r) => r.status == StockRequestStatus.pending).toList(),
    };

    final emptyCopy = switch (filter) {
      'rejected' => 'No rejected requests yet.',
      'approved' => 'No fulfilled requests yet.',
      _ => 'No incoming requests yet.',
    };

    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [AppAccountMenu()]),
      body: SafeArea(
        child: user == null
            ? const Center(child: Text('Not signed in'))
            : user.role != UserRole.supplier && !user.hasSuperAdminFull
                ? const Center(child: Text('This view is for suppliers.'))
                : service.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: () => service.loadForSupplier(user.id),
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: AppSpacing.paddingLg,
                          itemCount: requests.isEmpty ? 1 : requests.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            if (requests.isEmpty) {
                              final scheme = Theme.of(context).colorScheme;
                              return Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius: BorderRadius.circular(AppRadius.lg),
                                  border: Border.all(color: scheme.outline.withValues(alpha: 0.2)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                                      child: Icon(Icons.inbox_outlined, color: scheme.primary),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(child: Text(emptyCopy, style: context.textStyles.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
                                  ],
                                ),
                              );
                            }

                            final req = requests[index];
                            return _IncomingCard(request: req, onTap: () => context.push('/supplier/stock-requests/${req.id}'));
                          },
                        ),
                      ),
      ),
    );
  }
}

class _IncomingCard extends StatelessWidget {
  final StockRequest request;
  final VoidCallback onTap;

  const _IncomingCard({required this.request, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: scheme.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: scheme.outline.withValues(alpha: 0.2))),
        child: Row(
          children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: Icon(Icons.inbox, color: scheme.primary)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(request.providerName, style: context.textStyles.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text('${request.items.length} item(s) • ${request.providerState ?? '-'} / ${request.providerLga ?? '-'}', style: context.textStyles.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Text('Status: ${request.status.name}', style: context.textStyles.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
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
