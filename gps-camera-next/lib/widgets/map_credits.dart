import 'package:flutter/material.dart';

import '../services/native.dart';
import '../core/design/tokens.dart';
import '../models/map_kind.dart';
import '../services/map_attribution.dart';

/// Cached credits render synchronously in capture frames. A new style/retry
/// gets a new snapshot, so the previous layer's credits cannot authorize it.
class MapCreditsBuilder extends StatelessWidget {
  const MapCreditsBuilder({
    super.key,
    required this.kind,
    required this.builder,
  });
  final MapKind kind;
  final Widget Function(BuildContext, String?) builder;

  @override
  Widget build(BuildContext context) {
    final service = MapAttribution.instance;
    final future = service.forKind(kind);
    return FutureBuilder<String>(
      key: ObjectKey(future),
      future: future,
      initialData: service.cached(kind),
      builder: (context, snapshot) => builder(context, snapshot.data),
    );
  }
}

/// Full credits stay reachable without a clipped two-line provider list.
class MapCreditsButton extends StatelessWidget {
  const MapCreditsButton({super.key, required this.credits, this.onRetry});
  final String? credits;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black87,
    shape: Corners.shape(Corners.xs),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Map credits'),
          content: SingleChildScrollView(
            child: SelectableText(
              credits ??
                  'Map credits are unavailable. Retry the map when connected.',
            ),
          ),
          actions: [
            if (onRetry != null)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  onRetry!();
                },
                child: const Text('Refresh credits'),
              ),
            TextButton(
              onPressed: () async {
                try {
                  await Native.openWebPage('https://www.esri.com/');
                } catch (_) {}
              },
              child: const Text('Esri'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          'Powered by Esri · Map credits',
          style: TextStyle(fontSize: 11, color: Colors.white),
        ),
      ),
    ),
  );
}
