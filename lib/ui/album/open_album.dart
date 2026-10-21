import 'package:flutter/material.dart';

import '../../engine/source_manager.dart';
import '../detail/detail_page.dart';
import '../nav.dart';
import '../subscriptions/subscription_posts_page.dart';
import 'media_album_page.dart';

Future<void> openMediaAlbum(
  BuildContext context, {
  required String source,
  required String title,
  required Map<String, Object?> scope,
  SourceManager? sources,
}) {
  final manager = sources ?? SourceManager.instance;
  final snapshot = Map<String, Object?>.of(scope);
  if (snapshot['options'] case final Map options) {
    snapshot['options'] = Map<String, Object?>.from(options);
  }
  return Nav.push(
    context,
    MediaAlbumPage(
      source: source,
      title: title,
      loader: (page, cursor, token) => manager.subscriptionAlbum(
        source,
        snapshot,
        page: page,
        cursor: cursor,
        cancelToken: token,
      ),
      onOpen: (context, entry) => Nav.push(
        context,
        entry.work.isSubscriptionPost
            ? SubscriptionWorkPage(item: entry.work)
            : DetailPage(
                sourceManager: manager,
                source: source,
                id: entry.work.id,
                preview: entry.work,
              ),
      ),
    ),
  );
}
