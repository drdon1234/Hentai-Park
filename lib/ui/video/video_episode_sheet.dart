import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/models.dart';
import '../../library/downloads.dart';
import '../../library/library.dart';

class VideoEpisodeSheet extends StatelessWidget {
  const VideoEpisodeSheet({super.key, required this.work, this.currentId});
  final WorkDetail work;
  final String? currentId;

  @override
  Widget build(BuildContext context) {
    final episodes = work.videoEpisodes;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: ListenableBuilder(
          listenable: Listenable.merge([
            Library.instance.work(work.uid),
            DownloadManager.instance,
          ]),
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: SelectionContainer.disabled(
                  child: Text(
                    tr('选集'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: episodes.length,
                  itemBuilder: (context, index) {
                    final episode = episodes[index];
                    final state = Library.instance.chapterState(
                      work.uid,
                      episode.id,
                    );
                    final task = DownloadManager.instance.task(work.uid);
                    final downloaded =
                        task?.completed.contains(episode.id) == true;
                    final queued =
                        task?.chapters.any(
                          (chapter) => chapter.id == episode.id,
                        ) ==
                        true;
                    return ListTile(
                      selected: episode.id == currentId,
                      leading: Icon(
                        episode.id == currentId
                            ? Icons.play_circle_fill_rounded
                            : Icons.play_circle_outline_rounded,
                      ),
                      title: SelectionContainer.disabled(
                        child: Text(episode.title),
                      ),
                      subtitle: state != null && state.position > 0
                          ? SelectionContainer.disabled(
                              child: Text(
                                tr('看到 {value0}:{value1}', {
                                  'value0': state.position ~/ 60,
                                  'value1': (state.position % 60)
                                      .toString()
                                      .padLeft(2, '0'),
                                }),
                              ),
                            )
                          : null,
                      trailing: downloaded || queued
                          ? SelectionContainer.disabled(
                              child: Text(tr(downloaded ? '已下载' : '未完成')),
                            )
                          : null,
                      onTap: () => Navigator.pop(context, episode),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
