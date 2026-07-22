import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/l10n.dart';
import '../../player/presentation/player_bar.dart';

enum PlayerNavigationDestination {
  tracks('/tracks', Icons.library_music_outlined, Icons.library_music_rounded);

  const PlayerNavigationDestination(this.path, this.icon, this.selectedIcon);

  final String path;
  final IconData icon;
  final IconData selectedIcon;

  String label(AppLocalizations l10n) {
    return l10n.navigationTracks;
  }
}

class PlayerNavigationScaffold extends StatelessWidget {
  const PlayerNavigationScaffold({
    required this.destination,
    required this.child,
    this.onDestinationSelected,
    this.playerBar,
    super.key,
  });

  final PlayerNavigationDestination destination;
  final Widget child;
  final ValueChanged<PlayerNavigationDestination>? onDestinationSelected;
  final Widget? playerBar;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 960;
        final controls = playerBar ?? const PlayerBar();

        if (desktop) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  _NavigationRail(
                    destination: destination,
                    onDestinationSelected: _selectDestination,
                  ),
                  VerticalDivider(
                    width: 1,
                    color: Colors.white.withValues(alpha: .08),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        _TopBar(
                          destination: destination,
                          onDestinationSelected: _selectDestination,
                          showDestinations: true,
                        ),
                        Expanded(child: child),
                        controls,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _TopBar(
                  destination: destination,
                  onDestinationSelected: _selectDestination,
                ),
                Expanded(child: child),
                controls,
                _BottomNavigation(
                  destination: destination,
                  onDestinationSelected: _selectDestination,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _selectDestination(
    BuildContext context,
    PlayerNavigationDestination selected,
  ) {
    if (selected == destination) {
      return;
    }
    final callback = onDestinationSelected;
    if (callback != null) {
      callback(selected);
      return;
    }
    context.go(selected.path);
  }
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail({
    required this.destination,
    required this.onDestinationSelected,
  });

  final PlayerNavigationDestination destination;
  final void Function(BuildContext, PlayerNavigationDestination)
      onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return SizedBox(
      width: 236,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Brand(),
            const SizedBox(height: 34),
            for (final item in PlayerNavigationDestination.values) ...[
              _RailItem(
                item: item,
                selected: item == destination,
                label: item.label(l10n),
                onTap: () => onDestinationSelected(context, item),
              ),
              const SizedBox(height: 6),
            ],
            const Spacer(),
            _RailUtilityItem(
              icon: Icons.library_music_outlined,
              label: l10n.managementTooltip,
              onTap: () => context.push('/management'),
            ),
            const SizedBox(height: 6),
            _RailUtilityItem(
              icon: Icons.settings_outlined,
              label: l10n.serverSettingsTooltip,
              onTap: () => context.push('/settings'),
            ),
            const SizedBox(height: 14),
            Text(
              context.l10n.appTitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant.withValues(alpha: .7),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailUtilityItem extends StatelessWidget {
  const _RailUtilityItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colors.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: const BorderRadius.all(Radius.circular(14)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            'assets/branding/logo.png',
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            context.l10n.appTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.3,
                ),
          ),
        ),
      ],
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.item,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final PlayerNavigationDestination item;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground =
        selected ? colors.onPrimaryContainer : colors.onSurfaceVariant;

    return Material(
      color: selected
          ? colors.primaryContainer.withValues(alpha: .62)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          child: Row(
            children: [
              Icon(
                selected ? item.selectedIcon : item.icon,
                color: foreground,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: foreground,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.destination,
    required this.onDestinationSelected,
    this.showDestinations = false,
  });

  final PlayerNavigationDestination destination;
  final void Function(BuildContext, PlayerNavigationDestination)
      onDestinationSelected;
  final bool showDestinations;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 14, 8),
      child: Row(
        children: [
          if (!showDestinations) ...[
            const _CompactBrand(),
            const Spacer(),
          ] else ...[
            Expanded(
              child: Wrap(
                spacing: 6,
                children: [
                  for (final item in PlayerNavigationDestination.values)
                    ChoiceChip(
                      selected: item == destination,
                      showCheckmark: false,
                      avatar: Icon(
                        item == destination ? item.selectedIcon : item.icon,
                        size: 18,
                      ),
                      label: Text(item.label(l10n)),
                      onSelected: (_) => onDestinationSelected(context, item),
                    ),
                ],
              ),
            ),
          ],
          IconButton(
            tooltip: l10n.managementTooltip,
            onPressed: () => context.push('/management'),
            icon: const Icon(Icons.library_music_outlined),
          ),
          IconButton(
            tooltip: l10n.serverSettingsTooltip,
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }
}

class _CompactBrand extends StatelessWidget {
  const _CompactBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: const BorderRadius.all(Radius.circular(10)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            'assets/branding/logo.png',
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          context.l10n.appTitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({
    required this.destination,
    required this.onDestinationSelected,
  });

  final PlayerNavigationDestination destination;
  final void Function(BuildContext, PlayerNavigationDestination)
      onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return NavigationBar(
      selectedIndex: destination.index,
      onDestinationSelected: (index) {
        onDestinationSelected(
          context,
          PlayerNavigationDestination.values[index],
        );
      },
      destinations: [
        for (final item in PlayerNavigationDestination.values)
          NavigationDestination(
            icon: Icon(item.icon),
            selectedIcon: Icon(item.selectedIcon),
            label: item.label(l10n),
          ),
      ],
    );
  }
}
