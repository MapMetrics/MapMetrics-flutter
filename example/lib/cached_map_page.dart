import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mapmetrics/mapmetrics.dart';
import 'viewmodels/tile_cache_viewmodel.dart';
import 'widgets/cache_stats_widget.dart';
import 'widgets/cache_controls_widget.dart';

@immutable
class CachedMapPage extends StatefulWidget {
  const CachedMapPage({super.key});

  static const String route = '/cached-map';

  @override
  State<CachedMapPage> createState() => _CachedMapPageState();
}

class _CachedMapPageState extends State<CachedMapPage> {
  MapController? _mapController;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => TileCacheViewModel()..initialize(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cached Map Demo'),
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
          actions: const [
            CacheControlsWidget(),
          ],
        ),
        body: Consumer<TileCacheViewModel>(
          builder: (context, viewModel, child) {
            if (!viewModel.isInitialized) {
              return const _LoadingWidget();
            }

            return Stack(
              children: [
                _buildMap(viewModel),
                const Positioned(
                  top: 16,
                  right: 16,
                  child: CacheStatsWidget(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMap(TileCacheViewModel viewModel) {
    return MapLibreMap(
      options: MapOptions(
        initCenter: Position(4.89, 52.37), // Amsterdam
        initZoom: 14,
        initStyle: viewModel.proxyStyleUrl,
      ),
      onMapCreated: (controller) {
        _mapController = controller;
      },
      children: const [
        MapControlButtons(
          showZoomInOutButton: true,
          showTrackLocation: true,
        )
      ],
      onEvent: (event) {
        if (event is MapEventLongClick) {
          _handleLongPress(event.point);
        }
      },
    );
  }

  void _handleLongPress(Position point) {
    final viewModel = context.read<TileCacheViewModel>();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Cache Stats: ${viewModel.cachedResponses} hits, '
          '${viewModel.networkRequests} network requests'
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _LoadingWidget extends StatelessWidget {
  const _LoadingWidget();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('🚀 Starting tile cache system...'),
          SizedBox(height: 8),
          Text('This will cache map tiles to reduce server load'),
        ],
      ),
    );
  }
}