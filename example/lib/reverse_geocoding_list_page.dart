import 'package:flutter/material.dart';
import 'models/poi_feature.dart';
import 'services/mvt_poi_service.dart';

/// Reverse Geocoding List Page - Displays nearby restrooms from MVT tiles
class ReverseGeocoadingListPage extends StatefulWidget {
  const ReverseGeocoadingListPage({
    required this.latitude,
    required this.longitude,
    super.key,
  });

  static const String route = '/reverse-geocoading';

  final double latitude;
  final double longitude;

  @override
  State<ReverseGeocoadingListPage> createState() => _ReverseGeocoadingListPageState();
}

class _ReverseGeocoadingListPageState extends State<ReverseGeocoadingListPage> {
  final _service = MvtPoiService();
  List<PoiFeature> _restrooms = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchRestrooms();
  }

  /// Fetch nearby restrooms from MVT tiles
  Future<void> _fetchRestrooms() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final restrooms = await _service.fetchNearbyRestrooms(
        lat: widget.latitude,
        lon: widget.longitude,
        zoom: 14,  // Fetch at zoom 14 for good detail
        radiusKm: 7.0,
      );

      setState(() {
        _restrooms = restrooms;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error fetching restrooms: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Restrooms'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchRestrooms,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchRestrooms,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading nearby restrooms...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Failed to load restrooms',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _fetchRestrooms,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_restrooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No restrooms found nearby',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try refreshing or moving to a different location',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _fetchRestrooms,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _restrooms.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final poi = _restrooms[index];
        return _buildPoiTile(poi);
      },
    );
  }

  Widget _buildPoiTile(PoiFeature poi) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          poi.icon,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(
        poi.name,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.category, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                poi.displayType,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(width: 12),
              Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                poi.formattedDistance,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          if (poi.formattedAddress != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.home, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    poi.formattedAddress!,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showPoiDetails(poi),
    );
  }

  void _showPoiDetails(PoiFeature poi) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(poi.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Type', poi.displayType),
              _buildDetailRow('Distance', poi.formattedDistance),
              if (poi.formattedAddress != null)
                _buildDetailRow('Address', poi.formattedAddress),
              if (poi.phone != null)
                _buildDetailRow('Phone', poi.phone),
              if (poi.website != null)
                _buildDetailRow('Website', poi.website),
              if (poi.openingHours != null)
                _buildDetailRow('Hours', poi.openingHours),
              if (poi.cuisine != null)
                _buildDetailRow('Cuisine', poi.cuisine),
              if (poi.toilets != null)
                _buildDetailRow('Toilets', poi.toilets),
              if (poi.wheelchair != null)
                _buildDetailRow('Wheelchair', poi.wheelchair),
              const Divider(),
              Text(
                'ID: ${poi.id}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Text(
                'Coordinates: ${poi.lat.toStringAsFixed(6)}, ${poi.lon.toStringAsFixed(6)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
