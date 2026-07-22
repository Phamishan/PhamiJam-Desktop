import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:phamijam/components/remote_control_badge.dart';
import 'package:provider/provider.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.onTabSelected, this.videoCover});

  final ValueChanged<String> onTabSelected;
  final Widget? videoCover;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: colorScheme.onSurface.withAlpha(100),
            width: 2,
          ),
        ),
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        //color: Color(0xFFe2b661),
      ),
      width: 200,
      height: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(height: 20),
          ListView(
            shrinkWrap: true,
            children: [
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  leading: Icon(
                    Icons.library_music_rounded,
                    color: colorScheme.onSurface,
                  ),
                  title: Text(
                    'Playlists',
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  onTap: () {
                    onTabSelected('playlists');
                  },
                ),
              ),
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  leading: Icon(
                    Icons.favorite_rounded,
                    color: colorScheme.onSurface,
                  ),
                  title: Text(
                    'Liked',
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  onTap: () {
                    onTabSelected('liked');
                  },
                ),
              ),
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  leading: Icon(
                    Icons.folder_rounded,
                    color: colorScheme.onSurface,
                  ),
                  title: Text(
                    'Local files',
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  onTap: () {
                    onTabSelected('local_files');
                  },
                ),
              ),
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  leading: Icon(
                    Icons.music_note_rounded,
                    color: colorScheme.onSurface,
                  ),
                  title: Text(
                    'Converter',
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  onTap: () {
                    onTabSelected('converter');
                  },
                ),
              ),
              Divider(
                color: colorScheme.onSurface.withAlpha(100),
                thickness: 5,
                indent: 20,
                endIndent: 20,
                radius: BorderRadius.circular(10),
              ),
            ],
          ),
          Spacer(),
          Selector<PlaybackModel, (Uint8List?, PlaybackEngine, bool, String?)>(
            selector: (context, playback) => (
              playback.coverImageBytes,
              playback.engine,
              playback.isRemoteControlling,
              playback.remoteSession?.deviceName,
            ),
            builder: (context, data, child) {
              final coverBytes = data.$1;
              final engine = data.$2;
              final isRemoteControlling = data.$3;
              final remoteDeviceName = data.$4;
              return Container(
                margin: EdgeInsets.only(bottom: 10),
                width: 160,
                height: 160,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: SizedBox(
                        width: 160,
                        height: 160,
                        child:
                            engine == PlaybackEngine.youtube &&
                                videoCover != null
                            ? FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: 284,
                                  height: 160,
                                  child: videoCover!,
                                ),
                              )
                            : DecoratedBox(
                                decoration: BoxDecoration(
                                  image: DecorationImage(
                                    image: coverBytes != null
                                        ? MemoryImage(coverBytes)
                                        : AssetImage(
                                                'assets/images/p-trans.png',
                                              )
                                              as ImageProvider,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                child: const SizedBox.expand(),
                              ),
                      ),
                    ),
                    if (isRemoteControlling)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: RemoteControlBadge(
                          deviceName: remoteDeviceName ?? 'device',
                          size: 28,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
