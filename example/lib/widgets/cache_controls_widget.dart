import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/tile_cache_viewmodel.dart';

class CacheControlsWidget extends StatelessWidget {
  const CacheControlsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (action) => _handleAction(context, action),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'stats',
          child: Row(
            children: [
              Icon(Icons.analytics),
              SizedBox(width: 8),
              Text('View Stats'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'preload',
          child: Row(
            children: [
              Icon(Icons.download),
              SizedBox(width: 8),
              Text('Preload Area'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'clear',
          child: Row(
            children: [
              Icon(Icons.clear_all),
              SizedBox(width: 8),
              Text('Clear Cache'),
            ],
          ),
        ),
      ],
    );
  }

  void _handleAction(BuildContext context, String action) {
    final viewModel = context.read<TileCacheViewModel>();

    switch (action) {
      case 'stats':
        _showStatsDialog(context, viewModel);
        break;
      case 'preload':
        _preloadCurrentArea(context, viewModel);
        break;
      case 'clear':
        _clearCache(context, viewModel);
        break;
    }
  }

  void _showStatsDialog(BuildContext context, TileCacheViewModel viewModel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cache Statistics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatRow('Hit Rate', '${viewModel.hitRate.toStringAsFixed(1)}%'),
            _buildStatRow('Total Requests', '${viewModel.totalRequests}'),
            _buildStatRow('Cache Hits', '${viewModel.cachedResponses}'),
            _buildStatRow('Network Requests', '${viewModel.networkRequests}'),
            const SizedBox(height: 16),
            const Text(
              'Benefits:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text('• Reduced server load'),
            const Text('• Faster tile loading'),
            const Text('• Better user experience'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  void _preloadCurrentArea(BuildContext context, TileCacheViewModel viewModel) {
    // For simplicity, preload Amsterdam area
    viewModel.preloadArea(
      centerLat: 52.37,
      centerLng: 4.89,
      zoomLevel: 14,
      radiusTiles: 2,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Preloading tiles for current area...'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void _clearCache(BuildContext context, TileCacheViewModel viewModel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text('Are you sure you want to clear all cached tiles?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              viewModel.clearCache();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cache cleared successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}