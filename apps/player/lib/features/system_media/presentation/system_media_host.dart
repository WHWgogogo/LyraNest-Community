import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/system_media_provider.dart';

class SystemMediaHost extends ConsumerWidget {
  const SystemMediaHost({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(systemMediaControllerProvider);
    return child;
  }
}
