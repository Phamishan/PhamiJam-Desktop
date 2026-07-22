import 'package:flutter/material.dart';

class RemoteControlBadge extends StatelessWidget {
  final String deviceName;
  final double size;

  const RemoteControlBadge({
    super.key,
    required this.deviceName,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    final icon = deviceName.toLowerCase().contains('phone')
        ? Icons.phone_iphone_rounded
        : Icons.desktop_windows_rounded;
    return Tooltip(
      message: 'Controlling $deviceName',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Icon(icon, size: size * 0.6, color: Colors.white),
      ),
    );
  }
}
