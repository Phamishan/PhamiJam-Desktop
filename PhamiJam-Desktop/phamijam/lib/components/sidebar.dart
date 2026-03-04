import 'package:flutter/material.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:provider/provider.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key, required this.onTabSelected, this.videoCover});

  final ValueChanged<String> onTabSelected;
  final Widget? videoCover;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: Colors.white.withAlpha(100), width: 2),
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
              ListTile(
                leading: Icon(Icons.library_music_rounded, color: Colors.white),
                title: Text('Playlists', style: TextStyle(color: Colors.white)),
                onTap: () {
                  onTabSelected('playlists');
                },
              ),
              ListTile(
                leading: Icon(Icons.favorite_rounded, color: Colors.white),
                title: Text('Liked', style: TextStyle(color: Colors.white)),
                onTap: () {
                  onTabSelected('liked');
                },
              ),
              ListTile(
                leading: Icon(Icons.folder_rounded, color: Colors.white),
                title: Text(
                  'Local files',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  onTabSelected('local_files');
                },
              ),
              ListTile(
                leading: Icon(Icons.music_note_rounded, color: Colors.white),
                title: Text('Converter', style: TextStyle(color: Colors.white)),
                onTap: () {
                  onTabSelected('converter');
                },
              ),
              Divider(
                color: Colors.white.withAlpha(100),
                thickness: 5,
                indent: 20,
                endIndent: 20,
                radius: BorderRadius.circular(10),
              ),
            ],
          ),
          Spacer(),
          Consumer<PlaybackModel>(
            builder: (context, playback, child) {
              final coverBytes = playback.coverImageBytes;
              return Container(
                margin: EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                ),
                width: 160,
                height: 160,
                clipBehavior: Clip.antiAlias,
                child:
                    playback.engine == PlaybackEngine.youtube &&
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
                                : AssetImage('assets/images/p-trans.png')
                                      as ImageProvider,
                            fit: BoxFit.cover,
                          ),
                        ),
                        child: const SizedBox.expand(),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}
