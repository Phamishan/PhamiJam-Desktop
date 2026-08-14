import 'package:flutter/material.dart';
import 'package:phamijam/services/changelog_service.dart';

Future<void> showChangelogDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const _ChangelogDialog(),
  );
}

class _ChangelogDialog extends StatelessWidget {
  const _ChangelogDialog();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Version History'),
      content: SizedBox(
        width: double.maxFinite,
        height: 420,
        child: FutureBuilder<List<ChangelogEntry>>(
          future: ChangelogService.load(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final entries = snapshot.data ?? const [];
            if (entries.isEmpty) {
              return Center(
                child: Text(
                  "Couldn't load version history.",
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              );
            }
            return ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 24),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.date.isEmpty
                          ? entry.version
                          : '${entry.version} — ${entry.date}',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    for (final change in entry.changes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '•  ',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                change,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
