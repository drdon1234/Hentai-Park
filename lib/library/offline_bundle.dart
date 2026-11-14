import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/storage.dart';
import '../core/timed_subtitles.dart';
import '../core/voice.dart';
import '../engine/domains.dart';
import '../engine/media_transport.dart';
import '../engine/media_transport_factory.dart';
import '../engine/native_media.dart';
import '../engine/source_manager.dart';
import '../images/park_image.dart';
import '../images/subscription_cache.dart';
import '../subscriptions/models.dart';
import '../video/local_hls_media.dart';
import '../video/media_download.dart';

/// 正文与附件的持久离线包。清单只保存内容身份、正文和相对文件名。
class OfflineBundle {
  OfflineBundle(this.directory, this.json);
  final Directory directory;
  final Map<String, dynamic> json;
  List<Map<String, dynamic>> get entries => (json['entries'] as List)
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList();
  List<Map<String, dynamic>> get blocks => (json['blocks'] as List? ?? [])
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList();

  static Future<OfflineBundle> read(File manifest) async {
    if (await manifest.length() > 16 * 1024 * 1024) {
      throw SourceError('PARSE', '媒体数据无效');
    }
    final data = jsonDecode(await manifest.readAsString());
    if (data is! Map ||
        data['entries'] is! List ||
        (data['entries'] as List).length > 10000) {
      throw SourceError('PARSE', '媒体数据无效');
    }
    return OfflineBundle(manifest.parent, data.cast<String, dynamic>());
  }

  Future<File?> file(Map entry) async {
    final path = entry['file'];
    if (path is! String ||
        !RegExp(r'^[a-f0-9]{64}\.[a-z0-9]+$').hasMatch(path)) {
      return null;
    }
    final target = File(p.join(directory.path, path));
    if (!await target.exists() ||
        await target.length() != entry['size'] ||
        await target.length() == 0) {
      return null;
    }
    final root = await directory.resolveSymbolicLinks();
    if (!p.isWithin(root, await target.resolveSymbolicLinks())) return null;
    if (path.endsWith('.m3u8')) {
      try {
        await LocalHlsMedia(target).files();
      } on SourceError {
        return null;
      } on FileSystemException {
        return null;
      }
    }
    return target;
  }

  Future<void> _save() async {
    final temporary = File(p.join(directory.path, 'bundle.json.part'));
    final data = utf8.encode(jsonEncode(json));
    if (data.length > 16 * 1024 * 1024) throw SourceError('PARSE', '媒体资源过多');
    await temporary.writeAsBytes(data, flush: true);
    await temporary.rename(p.join(directory.path, 'bundle.json'));
  }

  static Future<void> download(
    WorkItem item,
    Directory directory, {
    Map<String, dynamic>? node,
    SourceManager? sourceManager,
    required CancelToken cancelToken,
    required void Function(int done, int total, int bytes) onProgress,
  }) async {
    void check() {
      if (cancelToken.cancelError case final error?) throw error;
    }

    final manager = sourceManager ?? SourceManager.instance;
    final manifest = manager.manifest(item.source);
    if (manifest == null) throw SourceError('CONFIG', '视频站点未加载');
    final detail = manifest.can('detail')
        ? await manager.detail(
            item.source,
            item.id,
            preview: item,
            cancelToken: cancelToken,
          )
        : await manager.downloadPost(item, cancelToken: cancelToken);
    check();
    final entries = <Map<String, dynamic>>[];
    final blocks = <Map<String, dynamic>>[];
    final assets = <String, _BundleAsset>{};
    void add(Map<String, dynamic> entry, _BundleAsset asset) {
      final id = entry['id'] as String;
      if (assets.containsKey(id)) return;
      if (entries.length >= 10000) throw SourceError('PARSE', '媒体资源过多');
      assets[id] = asset;
      entries.add(entry);
    }

    if (item.mediaKind == MediaKind.voice || manifest.kind == MediaKind.voice) {
      final visited = <String>{};
      Future<void> visit(VoiceNode node, String? parent, int depth) async {
        check();
        if (depth > 64 || visited.length >= 10000) {
          throw SourceError('PARSE', '媒体资源过多');
        }
        if (!visited.add(node.id)) throw SourceError('PARSE', '媒体数据无效');
        if (node.kind == VoiceNodeKind.directory) {
          entries.add({
            'id': node.id,
            'name': node.name,
            'type': 'directory',
            'parent': parent,
          });
          final children = <VoiceNode>[];
          final seen = <String>{};
          if (node.childrenComplete) {
            children.addAll(node.children);
          } else {
            var ended = false;
            for (var page = 1; page <= 1000; page++) {
              final result = await manager.voiceDirectory(
                item.source,
                item.id,
                node.id,
                page: page,
                cancelToken: cancelToken,
              );
              check();
              final fresh = result.items
                  .where((entry) => seen.add(entry.id))
                  .toList();
              if (result.hasNext && fresh.isEmpty) {
                throw SourceError('PARSE', '媒体数据无效');
              }
              children.addAll(fresh);
              if (children.length > 10000) throw SourceError('PARSE', '媒体资源过多');
              if (!result.hasNext) {
                ended = true;
                break;
              }
            }
            if (!ended) throw SourceError('PARSE', '媒体资源过多');
          }
          final subtitles = matchVoiceSubtitles(children);
          for (final child in children) {
            await visit(child, node.id, depth + 1);
            if (subtitles[child.id] case final linked?) {
              final entry = entries
                  .where((e) => e['id'] == child.id)
                  .firstOrNull;
              entry?['subtitleIds'] = linked.map((e) => e.id).toList();
            }
          }
        } else {
          add({
            'id': node.id,
            'name': node.name,
            'type': node.kind.name,
            'parent': parent,
            if (node.subtitleIds.isNotEmpty) 'subtitleIds': node.subtitleIds,
          }, _BundleAsset(voiceId: node.id, playable: node.playable));
        }
      }

      final rawRoot = node?.isNotEmpty == true
          ? node
          : detail.json['voiceRoot'];
      if (rawRoot is Map) {
        final root = VoiceNode.fromJson(rawRoot.cast<String, dynamic>());
        await visit(root, null, 0);
        if (root.playable) {
          for (final id in root.subtitleIds) {
            if (!assets.containsKey(id)) {
              add({
                'id': id,
                'name': id,
                'type': 'subtitle',
              }, _BundleAsset(voiceId: id));
            }
          }
        }
      } else {
        for (final track in detail.videoEpisodes) {
          add({
            'id': track.id,
            'name': track.title,
            'type':
                (detail.json['voiceTrackKinds'] as Map?)?[track.id] ??
                (detail.voiceMediaForm == VoiceMediaForm.videoOnly
                    ? 'video'
                    : 'audio'),
            'subtitleIds': detail.voiceSubtitles[track.id] ?? [],
          }, _BundleAsset(episode: track.id, playable: true));
          for (final id in detail.voiceSubtitles[track.id] ?? <String>[]) {
            add({
              'id': id,
              'name': id,
              'type': 'subtitle',
            }, _BundleAsset(voiceId: id));
          }
        }
      }
    } else {
      final article = manifest.isArticle;
      final media = article
          ? (detail.json['blocks'] as List)
          : (detail.json['media'] as List? ?? []);
      if (!article &&
          (detail.json['text'] ?? detail.description).toString().isNotEmpty) {
        blocks.add({
          'type': 'text',
          'text': (detail.json['text'] ?? detail.description).toString(),
        });
      }
      for (var index = 0; index < media.length; index++) {
        final raw = Map<String, dynamic>.from(media[index] as Map);
        if (raw['type'] == 'text') {
          blocks.add({'type': 'text', 'text': raw['text']});
          continue;
        }
        if (!{'image', 'video', 'audio'}.contains(raw['type'])) {
          throw SourceError('UNSUPPORTED', '媒体数据无效');
        }
        final id = article
            ? '${raw['type']}:${raw['id'] ?? index}'
            : 'media:$index';
        final episode =
            raw['episodeId']?.toString() ??
            (article && raw['type'] == 'video' ? raw['id']?.toString() : null);
        final rawUrl = Uri.tryParse(raw['url']?.toString() ?? '');
        if (rawUrl != null &&
            rawUrl.hasScheme &&
            !httpsDomainAddressAllowed(rawUrl, [rawUrl.host])) {
          throw SourceError('PARSE', '媒体数据无效');
        }
        add(
          {
            'id': id,
            'name': raw['name']?.toString() ?? '${detail.title} ${index + 1}',
            'type': raw['type'],
            'identity': safeFileName(
              jsonEncode([
                (raw['resource'] is Map
                        ? {
                            'cacheKey': (raw['resource'] as Map)['cacheKey'],
                            'size': (raw['resource'] as Map)['size'],
                          }
                        : null) ??
                    (rawUrl == null ? null : '${rawUrl.host}${rawUrl.path}'),
                episode,
              ]),
            ),
            if (raw['previewOnly'] == true) 'previewOnly': true,
          },
          _BundleAsset(
            media: SubscriptionMedia(raw),
            episode: episode,
            playable: raw['type'] != 'image',
          ),
        );
        blocks.add({'type': raw['type'], 'asset': id});
      }
    }
    check();
    if (assets.isEmpty && blocks.isEmpty) {
      throw SourceError('NOT_FOUND', '暂无内容');
    }
    await directory.create(recursive: true);
    final stored = File(p.join(directory.path, 'bundle.json'));
    final previous = await stored.exists() ? await read(stored) : null;
    final bundle = OfflineBundle(directory, {
      'kind': item.mediaKind == MediaKind.voice ? 'voice' : manifest.kind.name,
      'title': detail.title,
      'entries': entries,
      'blocks': blocks,
      'complete': false,
      'previewOnly':
          detail.json['locked'] == true ||
          entries.any((e) => e['previewOnly'] == true),
    });
    // 首次保存前合并已有文件，中途取消仍保留后续附件的恢复信息。
    for (final entry in entries) {
      final old = previous?.entries
          .where(
            (e) =>
                e['id'] == entry['id'] &&
                e['type'] == entry['type'] &&
                e['identity'] == entry['identity'],
          )
          .firstOrNull;
      if (old != null && await previous!.file(old) != null) {
        entry.addAll({
          'file': old['file'],
          'size': old['size'],
          'format': old['format'],
        });
      }
    }
    var done = 0;
    var bytes = 0;
    final total = assets.length + 1;
    await bundle._save();
    for (final entry in entries.where((e) => e['type'] != 'directory')) {
      check();
      final id = entry['id'] as String;
      final asset = assets[id]!;
      final existing = await bundle.file(entry);
      if (existing != null) {
        bytes += await offlineMediaBytes(existing);
      } else {
        final stem = safeFileName(id);
        File output;
        String format;
        if (asset.media?.needsDownload == true) {
          final cached = await manager.subscriptionMediaFile(
            item.source,
            asset.media!,
            cancelToken: cancelToken,
            onProgress: (received, length) =>
                onProgress(done, total, bytes + received),
          );
          try {
            format = entry['type'] == 'image' ? 'img' : 'mp4';
            output = File(p.join(directory.path, '$stem.$format'));
            final part = File('${output.path}.part');
            await cached.copy(part.path);
            check();
            await part.rename(output.path);
          } finally {
            SubscriptionCache.instance.release(cached);
          }
        } else if (asset.playable) {
          final List<VideoSource> sources;
          if (asset.media?.url.isNotEmpty == true && asset.episode == null) {
            sources = await manager.resolveVideoSources(item.source, [
              VideoSource({
                'url': asset.media!.url,
                'format':
                    asset.media!.json['format'] ??
                    (asset.media!.url.contains('.m3u8') ? 'hls' : 'mp4'),
                'headers': asset.media!.json['headers'] ?? {},
                'preferred': true,
              }),
            ], cancelToken: cancelToken);
          } else {
            sources = await manager.videos(
              item.source,
              item.id,
              episodeId: asset.episode ?? asset.voiceId,
              cancelToken: cancelToken,
            );
          }
          if (sources.isEmpty) throw SourceError('NOT_FOUND', '此影片暂无可用播放地址');
          final source = sources.firstWhere(
            (s) => s.preferred,
            orElse: () => sources.first,
          );
          format = downloadMediaExtension(source, keepPlaylist: true);
          output = File(p.join(directory.path, '$stem.$format'));
          await downloadMedia(
            manifest,
            source,
            output,
            keepPlaylist: true,
            cancelToken: cancelToken,
            onProgress: (current, count, size) => onProgress(
              done * 1000 + (count > 0 ? current * 1000 ~/ count : 0),
              total * 1000,
              bytes + size,
            ),
          );
        } else if (asset.voiceId != null && entry['type'] == 'other') {
          final resource = await manager.voiceResource(
            item.source,
            item.id,
            asset.voiceId!,
            cancelToken: cancelToken,
          );
          format = RegExp(r'^[a-z0-9]{1,10}$').hasMatch(resource.format)
              ? resource.format
              : 'bin';
          output = File(p.join(directory.path, '$stem.$format'));
          final part = File('${output.path}.part');
          final transport = NativeMedia(
            MediaPolicy.fromManifest(manifest, initialUrl: resource.url),
          );
          try {
            await transport.download(
              resource.url,
              part,
              cancelToken: cancelToken,
              onProgress: (received, length) =>
                  onProgress(done, total, bytes + received),
            );
            check();
            await part.rename(output.path);
          } finally {
            await transport.close();
          }
        } else {
          final List<int> data;
          if (asset.voiceId != null) {
            final resource = await manager.voiceResource(
              item.source,
              item.id,
              asset.voiceId!,
              cancelToken: cancelToken,
            );
            format = RegExp(r'^[a-z0-9]{1,10}$').hasMatch(resource.format)
                ? resource.format
                : 'bin';
            final transport = createMediaTransport(
              manifest,
              initialUrl: resource.url,
              foregroundRecovery: false,
            );
            try {
              data = (await transport.fetch(
                resource.url,
                maxBytes: 32 * 1024 * 1024,
                cancelToken: cancelToken,
              )).bytes;
            } finally {
              await transport.close();
            }
          } else {
            format = 'img';
            data = await ParkImage.url(
              item.source,
              asset.media!.url,
              headers: (asset.media!.json['headers'] as Map?)?.map(
                (k, v) => MapEntry(k.toString(), v.toString()),
              ),
            ).loadBytes(cancelToken: cancelToken);
          }
          if (data.isEmpty) throw SourceError('PARSE', '媒体数据无效');
          output = File(p.join(directory.path, '$stem.$format'));
          final part = File('${output.path}.part');
          await part.writeAsBytes(data, flush: true);
          check();
          await part.rename(output.path);
        }
        check();
        if (entry['type'] == 'image') {
          if (await output.length() > 32 * 1024 * 1024) {
            throw SourceError('PARSE', '媒体资源过大');
          }
          try {
            final codec = await ui.instantiateImageCodec(
              await output.readAsBytes(),
              targetWidth: 1,
              targetHeight: 1,
            );
            try {
              (await codec.getNextFrame()).image.dispose();
            } finally {
              codec.dispose();
            }
          } catch (_) {
            throw SourceError('PARSE', '图片加载失败');
          }
        } else if (entry['type'] == 'subtitle') {
          if (await output.length() > 2 * 1024 * 1024) {
            throw SourceError('PARSE', '媒体资源过大');
          }
          if (TimedSubtitles.parse(
            await output.readAsString(),
            format: format,
          ).cues.isEmpty) {
            throw SourceError('PARSE', '媒体数据无效');
          }
        }
        check();
        entry.addAll({
          'file': p.basename(output.path),
          'size': await output.length(),
          'format': format,
        });
        bytes += await offlineMediaBytes(output);
      }
      done++;
      await bundle._save();
      onProgress(done, total, bytes);
    }
    check();
    bundle.json['complete'] = true;
    await bundle._save();
    onProgress(total, total, bytes);
  }
}

class _BundleAsset {
  _BundleAsset({this.voiceId, this.episode, this.media, this.playable = false});
  final String? voiceId, episode;
  final SubscriptionMedia? media;
  final bool playable;
}
