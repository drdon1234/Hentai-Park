import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Android can report inactive while a split-screen activity remains visible.
bool isAppVisible(AppLifecycleState? state) =>
    state == null ||
    state == AppLifecycleState.resumed ||
    (defaultTargetPlatform == TargetPlatform.android &&
        state == AppLifecycleState.inactive);
