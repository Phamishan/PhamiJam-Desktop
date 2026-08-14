import 'package:flutter/material.dart';
import 'package:phamijam/services/listening_history_service.dart';
import 'package:phamijam/services/wrapped_stats.dart';
import 'package:phamijam/theme/app_theme.dart';

class JamstatsPage extends StatefulWidget {
  const JamstatsPage({super.key});

  @override
  State<JamstatsPage> createState() => _JamstatsPageState();
}

class _JamstatsPageState extends State<JamstatsPage> {
  WrappedStats? _stats;
  int _slideIndex = 0;
  int _year = DateTime.now().year;
  int _earliestYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadEarliestYear();
  }

  Future<void> _loadEarliestYear() async {
    final year = await ListeningHistoryService.earliestEventYear();
    if (!mounted) return;
    setState(() => _earliestYear = year);
  }

  Future<void> _loadStats() async {
    setState(() => _stats = null);
    final events = await ListeningHistoryService.eventsSince(
      DateTime(_year),
      until: DateTime(_year + 1),
    );
    if (!mounted) return;
    setState(() => _stats = WrappedStats.fromEvents(events));
  }

  void _selectYear(int year) {
    if (year == _year) return;
    setState(() {
      _year = year;
      _slideIndex = 0;
    });
    _loadStats();
  }

  List<int> get _availableYears => [
    for (var y = DateTime.now().year; y >= _earliestYear; y--) y,
  ];

  List<Widget> _buildSlides(WrappedStats stats) {
    return [
      _IntroSlide(year: _year),
      _MinutesSlide(stats: stats),
      if (stats.topTracks.isNotEmpty) _TopTrackSlide(stats: stats),
      if (stats.topTracks.length > 1)
        _TopListSlide(
          title: 'Your top tracks',
          entries: stats.topTracks,
          square: true,
        ),
      if (stats.topArtists.isNotEmpty) _TopArtistSlide(stats: stats),
      if (stats.topArtists.length > 1)
        _TopListSlide(
          title: 'Your top artists',
          entries: stats.topArtists,
          square: false,
        ),
      _HabitsSlide(stats: stats),
      _SummarySlide(stats: stats, year: _year),
    ];
  }

  void _advance(int delta, int slideCount) {
    final next = (_slideIndex + delta).clamp(0, slideCount - 1).toInt();
    if (next == _slideIndex && delta > 0) {
      Navigator.of(context).maybePop();
      return;
    }
    if (next != _slideIndex) setState(() => _slideIndex = next);
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;

    Widget body;
    if (stats == null) {
      body = const Center(child: CircularProgressIndicator(color: kBrandGold));
    } else if (stats.isEmpty) {
      body = Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _EmptyState(year: _year),
        ),
      );
    } else {
      final slides = _buildSlides(stats);
      body = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final width = MediaQuery.of(context).size.width;
          _advance(
            details.globalPosition.dx < width / 3 ? -1 : 1,
            slides.length,
          );
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOutCubic,
                child: KeyedSubtree(
                  key: ValueKey(_slideIndex),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: slides[_slideIndex],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Row(
                    children: List.generate(slides.length, (i) {
                      return Expanded(
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: i <= _slideIndex
                                ? kBrandGold
                                : Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF16130D),
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.6),
                  radius: 1.4,
                  colors: [Color(0xFF3A2E12), Color(0xFF16130D)],
                ),
              ),
            ),
          ),
          body,
          if (_availableYears.length > 1)
            Positioned(
              top: 16,
              left: 16,
              child: _YearPicker(
                year: _year,
                years: _availableYears,
                onSelected: _selectYear,
              ),
            ),
          Positioned(
            top: 16,
            right: 16,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _YearPicker extends StatelessWidget {
  final int year;
  final List<int> years;
  final ValueChanged<int> onSelected;

  const _YearPicker({
    required this.year,
    required this.years,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      initialValue: year,
      onSelected: onSelected,
      color: const Color(0xFF2A2210),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: kBrandGold.withValues(alpha: 0.3)),
      ),
      itemBuilder: (context) => [
        for (final y in years)
          PopupMenuItem(
            value: y,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 18,
                  child: y == year
                      ? Icon(Icons.check_rounded, color: kBrandGold, size: 18)
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  '$y',
                  style: TextStyle(
                    color: y == year ? kBrandGold : Colors.white,
                    fontWeight: y == year ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kBrandGold.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$year',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.expand_more_rounded,
              color: Colors.white,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String url;
  final double size;
  final BorderRadius borderRadius;

  const _Thumb({
    required this.url,
    required this.size,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: size,
      height: size,
      color: Colors.white.withValues(alpha: 0.08),
      alignment: Alignment.center,
      child: Icon(
        Icons.music_note_rounded,
        size: size / 2.5,
        color: Colors.white.withValues(alpha: 0.5),
      ),
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: url.isEmpty
          ? placeholder
          : Image.network(
              url,
              width: size,
              height: size,
              cacheWidth: (size * 2).round(),
              cacheHeight: (size * 2).round(),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => placeholder,
            ),
    );
  }
}

class _SlideScaffold extends StatelessWidget {
  final List<Widget> children;

  const _SlideScaffold({required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 64, 28, 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

TextStyle _kicker(BuildContext context) => Theme.of(
  context,
).textTheme.titleMedium!.copyWith(color: Colors.white.withValues(alpha: 0.7));

TextStyle _hero(BuildContext context) => Theme.of(context)
    .textTheme
    .displayMedium!
    .copyWith(color: kBrandGold, fontWeight: FontWeight.w700, height: 1.05);

TextStyle _body(BuildContext context) => Theme.of(context).textTheme.titleLarge!
    .copyWith(color: Colors.white, fontWeight: FontWeight.w500);

class _IntroSlide extends StatelessWidget {
  final int year;

  const _IntroSlide({required this.year});

  @override
  Widget build(BuildContext context) {
    return _SlideScaffold(
      children: [
        Text('$year', style: _kicker(context)),
        const SizedBox(height: 8),
        Text('Jamstats ✨', style: _hero(context)),
        const SizedBox(height: 16),
        Text(
          'Your year in PhamiJam.\nClick to see the sound through your eyes ✨',
          style: _body(context),
        ),
      ],
    );
  }
}

class _MinutesSlide extends StatelessWidget {
  final WrappedStats stats;

  const _MinutesSlide({required this.stats});

  @override
  Widget build(BuildContext context) {
    return _SlideScaffold(
      children: [
        Text('You spent', style: _kicker(context)),
        const SizedBox(height: 8),
        TweenAnimationBuilder<int>(
          tween: IntTween(begin: 0, end: stats.totalMinutes),
          duration: const Duration(milliseconds: 1200),
          curve: Curves.easeOutCubic,
          builder: (context, value, _) =>
              Text('$value minutes', style: _hero(context)),
        ),
        const SizedBox(height: 16),
        Text(
          'jamming across ${stats.totalPlays} plays '
          'and ${stats.uniqueTracks} different tracks.',
          style: _body(context),
        ),
      ],
    );
  }
}

class _TopTrackSlide extends StatelessWidget {
  final WrappedStats stats;

  const _TopTrackSlide({required this.stats});

  @override
  Widget build(BuildContext context) {
    final top = stats.topTracks.first;
    return _SlideScaffold(
      children: [
        Text('Your #1 track', style: _kicker(context)),
        const SizedBox(height: 20),
        Center(
          child: _Thumb(
            url: top.thumbnailUrl,
            size: 200,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          top.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _hero(context).copyWith(fontSize: 32),
        ),
        const SizedBox(height: 8),
        Text(
          '${top.subtitle.isNotEmpty ? '${top.subtitle} · ' : ''}'
          '${top.plays} plays · ${top.minutes} minutes',
          style: _body(context),
        ),
      ],
    );
  }
}

class _TopArtistSlide extends StatelessWidget {
  final WrappedStats stats;

  const _TopArtistSlide({required this.stats});

  @override
  Widget build(BuildContext context) {
    final top = stats.topArtists.first;
    return _SlideScaffold(
      children: [
        Text('Your #1 artist', style: _kicker(context)),
        const SizedBox(height: 8),
        Text(
          top.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: _hero(context),
        ),
        const SizedBox(height: 16),
        Text(
          'They soundtracked ${stats.topArtistPercent}% of your '
          'listening this year.',
          style: _body(context),
        ),
      ],
    );
  }
}

class _TopListSlide extends StatelessWidget {
  final String title;
  final List<WrappedEntry> entries;
  final bool square;

  const _TopListSlide({
    required this.title,
    required this.entries,
    required this.square,
  });

  @override
  Widget build(BuildContext context) {
    return _SlideScaffold(
      children: [
        Text(title, style: _kicker(context)),
        const SizedBox(height: 20),
        for (var i = 0; i < entries.length; i++) ...[
          Row(
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  '${i + 1}',
                  style: _hero(context).copyWith(fontSize: 24),
                ),
              ),
              _Thumb(
                url: entries[i].thumbnailUrl,
                size: 48,
                borderRadius: BorderRadius.circular(square ? 8 : 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entries[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _body(context).copyWith(fontSize: 17),
                    ),
                    Text(
                      entries[i].subtitle.isNotEmpty
                          ? entries[i].subtitle
                          : '${entries[i].plays} plays',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _kicker(context).copyWith(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _HabitsSlide extends StatelessWidget {
  final WrappedStats stats;

  const _HabitsSlide({required this.stats});

  @override
  Widget build(BuildContext context) {
    return _SlideScaffold(
      children: [
        Text('Your listening habits', style: _kicker(context)),
        const SizedBox(height: 20),
        _HabitRow(
          icon: Icons.calendar_today_rounded,
          label: 'Busiest day',
          value: stats.busiestDay,
        ),
        _HabitRow(
          icon: Icons.schedule_rounded,
          label: 'Prime jam hour',
          value: stats.busiestHour,
        ),
        _HabitRow(
          icon: Icons.local_fire_department_rounded,
          label: 'Longest streak',
          value:
              '${stats.longestStreakDays} day${stats.longestStreakDays == 1 ? '' : 's'}',
        ),
        _HabitRow(
          icon: Icons.people_rounded,
          label: 'Artists explored',
          value: '${stats.uniqueArtists}',
        ),
      ],
    );
  }
}

class _HabitRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _HabitRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Icon(icon, color: kBrandGold, size: 28),
          const SizedBox(width: 16),
          Expanded(child: Text(label, style: _body(context))),
          Text(
            value,
            style: _body(
              context,
            ).copyWith(color: kBrandGold, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _SummarySlide extends StatelessWidget {
  final WrappedStats stats;
  final int year;

  const _SummarySlide({required this.stats, required this.year});

  @override
  Widget build(BuildContext context) {
    Widget column(String title, List<WrappedEntry> entries) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _kicker(context).copyWith(fontSize: 13)),
            const SizedBox(height: 8),
            for (var i = 0; i < entries.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${i + 1}. ${entries[i].name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _body(context).copyWith(fontSize: 14),
                ),
              ),
          ],
        ),
      );
    }

    return _SlideScaffold(
      children: [
        Text('Jamstats ✨ $year', style: _hero(context).copyWith(fontSize: 30)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kBrandGold.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  column('TOP TRACKS', stats.topTracks),
                  const SizedBox(width: 16),
                  column('TOP ARTISTS', stats.topArtists),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Minutes listened',
                style: _kicker(context).copyWith(fontSize: 13),
              ),
              Text(
                '${stats.totalMinutes}',
                style: _hero(context).copyWith(fontSize: 36),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Screenshot it. Share it. Jam on. ✨', style: _kicker(context)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final int year;

  const _EmptyState({required this.year});

  @override
  Widget build(BuildContext context) {
    final isCurrentYear = year == DateTime.now().year;
    return _SlideScaffold(
      children: [
        Text('Jamstats ✨ $year', style: _hero(context).copyWith(fontSize: 32)),
        const SizedBox(height: 16),
        Text(
          isCurrentYear
              ? "Nothing to wrap yet — PhamiJam starts counting your plays "
                    "from now on. Go jam for a bit and check back!"
              : "No listening logged for $year.",
          style: _body(context),
        ),
      ],
    );
  }
}
