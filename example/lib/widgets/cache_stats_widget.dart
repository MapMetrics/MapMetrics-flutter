import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/tile_cache_viewmodel.dart';

class CacheStatsWidget extends StatelessWidget {
  const CacheStatsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TileCacheViewModel>(
      builder: (context, viewModel, child) {
        if (viewModel.stats.isEmpty) {
          return const SizedBox.shrink();
        }

        return Card(
          color: Colors.black.withOpacity(0.8),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cache Performance',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                
                // Tile proxy stats
                const Text(
                  'Tile Cache',
                  style: TextStyle(
                    color: Colors.yellow,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Hit Rate: ${viewModel.hitRate.toStringAsFixed(1)}%',
                  style: const TextStyle(color: Colors.green, fontSize: 10),
                ),
                Text(
                  'Requests: ${viewModel.totalRequests} | Cached: ${viewModel.cachedResponses}',
                  style: const TextStyle(color: Colors.white, fontSize: 9),
                ),
                
                if (viewModel.proxyUrl != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Proxy: ${_getProxyHost(viewModel.proxyUrl!)}',
                    style: const TextStyle(color: Colors.cyan, fontSize: 8),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _getProxyHost(String proxyUrl) {
    final uri = Uri.parse(proxyUrl);
    return '${uri.host}:${uri.port}';
  }
}