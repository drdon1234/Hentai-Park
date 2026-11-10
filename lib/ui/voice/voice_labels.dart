import '../../core/localization.dart';
import '../../core/voice.dart';

String? voiceFormLabel(VoiceMediaForm form) => switch (form) {
  VoiceMediaForm.audioOnly => tr('纯音频'),
  VoiceMediaForm.videoOnly => tr('带视频'),
  VoiceMediaForm.mixed => tr('音画混合'),
  VoiceMediaForm.unknown => null,
};

String? voiceLanguageLabel(VoiceLanguageStatus status) => switch (status) {
  VoiceLanguageStatus.chineseSpoken => tr('中文配音'),
  VoiceLanguageStatus.chineseSubtitled => tr('中文字幕'),
  VoiceLanguageStatus.foreignOriginal => tr('外语原版'),
  VoiceLanguageStatus.unknown => null,
};
