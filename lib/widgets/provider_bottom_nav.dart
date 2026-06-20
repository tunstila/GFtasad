import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:mediflow/models/user.dart';
import 'package:mediflow/services/auth_service.dart';

class ProviderBottomNav extends StatelessWidget {
  final int currentIndex;
  final int deliveryBadge;

  const ProviderBottomNav({super.key, required this.currentIndex, required this.deliveryBadge});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final role = auth.currentUser?.role;
    final canRecord = role?.canRecordTests ?? false;

    // Supplier UX: only Home, Deliveries, Profile.
    if (role == UserRole.supplier) {
      final idx = currentIndex.clamp(0, 2);
      return Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 1))),
        child: NavigationBar(
          selectedIndex: idx,
          onDestinationSelected: (index) {
            switch (index) {
              case 0:
                context.go('/provider-home');
                break;
              case 1:
                context.go('/deliveries');
                break;
              case 2:
                context.go('/provider-profile');
                break;
            }
          },
          destinations: [
            const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(
              icon: Badge(isLabelVisible: deliveryBadge > 0, label: Text('$deliveryBadge'), child: const Icon(Icons.local_shipping_outlined)),
              selectedIcon: Badge(isLabelVisible: deliveryBadge > 0, label: Text('$deliveryBadge'), child: const Icon(Icons.local_shipping)),
              label: 'Deliveries',
            ),
            const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2), width: 1))),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/provider-home');
              break;
            case 1:
              if (!canRecord) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('View-only access: recording is disabled.')));
                return;
              }
              context.push('/select-program');
              break;
            case 2:
              context.go('/inventory');
              break;
            case 3:
              context.go('/deliveries');
              break;
            case 4:
              context.go('/provider-profile');
              break;
          }
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          const NavigationDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle), label: 'Record'),
          const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Inventory'),
          NavigationDestination(
            icon: Badge(isLabelVisible: deliveryBadge > 0, label: Text('$deliveryBadge'), child: const Icon(Icons.local_shipping_outlined)),
            selectedIcon: Badge(isLabelVisible: deliveryBadge > 0, label: Text('$deliveryBadge'), child: const Icon(Icons.local_shipping)),
            label: 'Deliveries',
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
