import 'package:flutter/material.dart';

class LikedPage extends StatefulWidget {
  const LikedPage({super.key});

  @override
  State<LikedPage> createState() => _LikedPageState();
}

class _LikedPageState extends State<LikedPage> {
  final String _likedTitle = 'Liked Songs';

  Widget _buildLikedContent() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _likedTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Expanded(
          child: Center(
            child: Text(
              'Your liked songs will appear here.',
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: _buildLikedContent(),
    );
  }
}
