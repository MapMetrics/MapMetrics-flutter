import 'package:flutter/material.dart';
import 'package:mapmetrics/mapmetrics.dart';

/// A draggable location marker widget that allows manual position updates
/// on the map by dragging the location icon.
///
/// {@category Widgets}
class DraggableLocationMarker extends StatefulWidget {
  const DraggableLocationMarker({
    super.key,
    required this.controller,
    this.onLocationChanged,
    this.initialPosition,
    this.markerSize = 40.0,
    this.markerColor = Colors.blue,
    this.accuracyCircleColor,
    this.showAccuracyCircle = true,
    this.accuracyRadius = 50.0,
    this.enableDragging = true,
    this.markerWidget,
  });

  /// The map controller to interact with the map
  final MapController controller;

  /// Callback when the location is manually changed by dragging
  final void Function(Position newPosition)? onLocationChanged;

  /// Initial position of the marker
  final Position? initialPosition;

  /// Size of the location marker
  final double markerSize;

  /// Color of the default location marker
  final Color markerColor;

  /// Color of the accuracy circle
  final Color? accuracyCircleColor;

  /// Whether to show an accuracy circle around the marker
  final bool showAccuracyCircle;

  /// Radius of the accuracy circle in meters
  final double accuracyRadius;

  /// Whether dragging is enabled
  final bool enableDragging;

  /// Custom widget to use as the marker instead of default
  final Widget? markerWidget;

  @override
  State<DraggableLocationMarker> createState() =>
      _DraggableLocationMarkerState();
}

class _DraggableLocationMarkerState extends State<DraggableLocationMarker> {
  Position? _currentPosition;
  Offset? _screenPosition;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.initialPosition ?? Position(0, 0);
    _updateScreenPosition();
  }

  Future<void> _updateScreenPosition() async {
    if (_currentPosition != null && mounted) {
      final screenPos = await widget.controller.toScreenLocation(_currentPosition!);
      if (mounted) {
        setState(() {
          _screenPosition = screenPos;
        });
      }
    }
  }

  Future<void> _handleDragUpdate(DragUpdateDetails details) async {
    if (!widget.enableDragging || !_isDragging) return;

    setState(() {
      _screenPosition = details.localPosition;
    });

    // Convert screen position to map coordinates
    final newPosition = await widget.controller.toLngLat(details.localPosition);
    _currentPosition = newPosition;

    // Call the callback with the new position
    widget.onLocationChanged?.call(newPosition);
  }

  Widget _buildDefaultMarker() {
    return Container(
      width: widget.markerSize,
      height: widget.markerSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.markerColor,
        border: Border.all(
          color: Colors.white,
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: widget.markerSize * 0.4,
          height: widget.markerSize * 0.4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }

  Widget _buildAccuracyCircle() {
    if (!widget.showAccuracyCircle) return const SizedBox.shrink();

    return Container(
      width: widget.accuracyRadius * 2,
      height: widget.accuracyRadius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: (widget.accuracyCircleColor ?? widget.markerColor)
            .withValues(alpha: 0.15),
        border: Border.all(
          color: (widget.accuracyCircleColor ?? widget.markerColor)
              .withValues(alpha: 0.3),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_screenPosition == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: _screenPosition!.dx - (widget.markerSize / 2),
      top: _screenPosition!.dy - (widget.markerSize / 2),
      child: GestureDetector(
        onPanStart: widget.enableDragging
            ? (details) {
                setState(() {
                  _isDragging = true;
                });
              }
            : null,
        onPanUpdate: widget.enableDragging ? _handleDragUpdate : null,
        onPanEnd: widget.enableDragging
            ? (details) {
                setState(() {
                  _isDragging = false;
                });
                _updateScreenPosition();
              }
            : null,
        child: AnimatedScale(
          scale: _isDragging ? 1.2 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: Stack(
            alignment: Alignment.center,
            children: [
              _buildAccuracyCircle(),
              widget.markerWidget ?? _buildDefaultMarker(),
            ],
          ),
        ),
      ),
    );
  }

  /// Update the marker position programmatically
  void updatePosition(Position newPosition) {
    setState(() {
      _currentPosition = newPosition;
    });
    _updateScreenPosition();
  }

  /// Get the current position of the marker
  Position? get currentPosition => _currentPosition;
}
