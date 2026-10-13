import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/localization.dart';
import '../../core/settings.dart';
import '../../engine/source_manager.dart';
import '../../images/source_posters.dart';
import 'automatic_posters.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/on_visible.dart';

class SourcePoster extends StatefulWidget {
  const SourcePoster({super.key, required this.source});
  final InstalledSource source;
  @override
  State<SourcePoster> createState() => _SourcePosterState();
}

class _SourcePosterState extends State<SourcePoster> {
  List<String> _urls = [];
  Uint8List? _local;
  int _generation = 0;
  bool _visible = false;
  String get _identity => AutomaticPosters.instance.identity(widget.source);
  late String _previousIdentity;
  @override
  void initState() {
    super.initState();
    _previousIdentity = _identity;
    SourcePosterStore.instance.addListener(_changed);
  }

  void _changed() {
    AutomaticPosters.instance.refresh(widget.source.key);
    if (_visible) unawaited(_load());
  }

  @override
  void didUpdateWidget(SourcePoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_identity != _previousIdentity) {
      _previousIdentity = _identity;
      _urls = [];
      if (_visible) unawaited(_load());
    }
  }

  Future<void> _load() async {
    _visible = true;
    final generation = ++_generation;
    final file = SourcePosterStore.instance.localFile(widget.source.key);
    Uint8List? local;
    try {
      if (await file.exists()) local = await file.readAsBytes();
    } catch (_) {}
    final urls = local != null
        ? <String>[]
        : await AutomaticPosters.instance.load(widget.source);
    if (mounted && generation == _generation) {
      setState(() {
        _local = local;
        _urls = urls;
      });
    }
  }

  @override
  void dispose() {
    _generation++;
    SourcePosterStore.instance.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.source.manifest!.color;
    final local = _local;
    Widget? localImage = local == null
        ? null
        : Image.memory(
            local,
            cacheWidth: 960,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          );
    if (localImage != null && AppSettings.instance.blurCovers) {
      localImage = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: localImage,
      );
    }
    return OnVisible(
      onVisible: (visible) {
        if (visible && !_visible) unawaited(_load());
      },
      child: SizedBox(
        height: 132,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, Color.lerp(color, Colors.black, .55)!],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            ?localImage,
            if (local == null && _urls.isNotEmpty)
              Row(
                children: [
                  for (final url in _urls)
                    Expanded(
                      child: CoverImage(
                        key: ValueKey('$url:$_generation'),
                        source: widget.source.key,
                        url: url,
                        radius: 0,
                      ),
                    ),
                ],
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black12, Colors.black.withValues(alpha: .75)],
                ),
              ),
            ),
            PositionedDirectional(
              start: 14,
              bottom: 14,
              end: 54,
              child: Row(
                children: [
                  SourceAvatar(widget.source.key, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.source.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SourcePosterMenu extends StatefulWidget {
  const SourcePosterMenu({super.key, required this.source});
  final String source;
  @override
  State<SourcePosterMenu> createState() => _SourcePosterMenuState();
}

class _SourcePosterMenuState extends State<SourcePosterMenu> {
  bool _busy = false;
  Future<void> _select(String action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (action == 'automatic') {
        await SourcePosterStore.instance.useAutomatic(widget.source);
      } else {
        final result = await FilePicker.pickFile(type: FileType.image);
        if (result == null) return;
        if (await result.xFile.length() > 20 * 1024 * 1024) {
          throw const FormatException('海报图片无效或超过20MB');
        }
        final bytes = await result.xFile.readAsBytes();
        await SourcePosterStore.instance.importImage(widget.source, bytes);
      }
    } catch (_) {
      if (mounted) context.toast(tr('海报更新失败，请选择可解码且不超过20MB的图片'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _busy
      ? const Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        )
      : PopupMenuButton<String>(
          tooltip: tr('站点海报'),
          icon: const Icon(Icons.photo_outlined, color: Colors.white),
          onSelected: _select,
          itemBuilder: (_) => [
            PopupMenuItem(value: 'upload', child: Text(tr('上传海报'))),
            PopupMenuItem(value: 'automatic', child: Text(tr('自动获取海报'))),
          ],
        );
}
