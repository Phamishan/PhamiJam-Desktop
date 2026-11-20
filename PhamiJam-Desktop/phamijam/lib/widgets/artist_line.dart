import 'package:flutter/material.dart';
import 'package:phamijam/services/song_artists_service.dart';

final RegExp _bracketedFeat = RegExp(
  r'[\(\[]\s*(?:feat|ft|featuring)\b\.?\s*([^\)\]]+?)\s*[\)\]]',
  caseSensitive: false,
);
final RegExp _trailingFeat = RegExp(
  r'\b(?:feat|ft|featuring)\b\.?\s+([^\(\[\-|]+)',
  caseSensitive: false,
);
final RegExp _topicSuffix = RegExp(r'\s*-\s*topic$', caseSensitive: false);

String _norm(String name) =>
    name.replaceFirst(_topicSuffix, '').trim().toLowerCase();

String? featuredArtistsFromTitle(String title, {String? mainArtist}) {
  final match =
      _bracketedFeat.firstMatch(title) ?? _trailingFeat.firstMatch(title);
  final raw = match?.group(1)?.trim();
  if (raw == null || raw.isEmpty) return null;
  if (mainArtist != null && _norm(raw) == _norm(mainArtist)) return null;
  return raw;
}

bool _isMissingArtist(String artist) {
  final value = artist.trim().toLowerCase();
  return value.isEmpty || value == 'unknown artist';
}

String? featuredFromCredits(List<String> credits, String mainArtist) {
  final main = _norm(mainArtist);
  final others = credits.where((name) {
    final n = _norm(name);
    return n.isNotEmpty && n != main && !main.contains(n);
  }).toList();
  return others.isEmpty ? null : others.join(', ');
}

class ArtistLine extends StatefulWidget {
  const ArtistLine({
    super.key,
    required this.artist,
    required this.title,
    required this.style,
    this.videoId,
    this.onTap,
  });

  final String artist;
  final String title;
  final String? videoId;
  final TextStyle style;
  final VoidCallback? onTap;

  @override
  State<ArtistLine> createState() => _ArtistLineState();
}

class _ArtistLineState extends State<ArtistLine> {
  List<String>? _credits;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  @override
  void didUpdateWidget(ArtistLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      _credits = null;
      _lookup();
    }
  }

  void _lookup() {
    final id = widget.videoId;
    if (!SongArtistsService.isLookupable(id)) return;
    final known = SongArtistsService.cached(id!);
    if (known != null) {
      _credits = known;
      return;
    }
    SongArtistsService.artistsFor(id).then((credits) {
      if (!mounted || widget.videoId != id) return;
      setState(() => _credits = credits);
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final credits = _credits;
    final hasCredits = credits != null && credits.isNotEmpty;
    final mainName = _isMissingArtist(widget.artist) && hasCredits
        ? credits.first
        : widget.artist;
    final featured =
        (hasCredits ? featuredFromCredits(credits, mainName) : null) ??
        featuredArtistsFromTitle(widget.title, mainArtist: mainName);
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: mainName,
            style: widget.onTap == null
                ? null
                : const TextStyle(decoration: TextDecoration.underline),
          ),
          if (featured != null)
            TextSpan(
              text: '  feat. $featured',
              style: TextStyle(
                fontSize: (style.fontSize ?? 14) * 0.88,
                decoration: TextDecoration.none,
                color: style.color?.withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
      style: style.copyWith(decoration: TextDecoration.none),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (widget.onTap == null) return text;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: widget.onTap, child: text),
    );
  }
}
