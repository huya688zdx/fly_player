part of '../../mpv_player_page.dart';

extension _MpvPlayerSettingsVideoInfoMixin on _MpvPlayerPageState {
  Widget _buildPlaybackSettingsVideoInfoPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    final l10n = AppLocalizations.of(context);
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(
        title: l10n.playerDiagnosticsTitle,
        onBack: drawer.popPage,
      ),
      child: FutureBuilder<Map<String, Object?>>(
        future: _controller.getPlaybackDiagnostics(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.playerDiagnosticsLoadFailed('${snapshot.error}'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            );
          }
          final sections = _buildPlaybackDetailSections(
            snapshot.data ?? const <String, Object?>{},
          );
          if (sections.isEmpty) {
            return Center(
              child: Text(
                l10n.playerDiagnosticsEmpty,
                style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 14),
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: sections.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) =>
                PlaybackDetailCard(section: sections[index]),
          );
        },
      ),
    );
  }

  List<PlaybackDetailSection> _buildPlaybackDetailSections(
    Map<String, Object?> diagnostics,
  ) {
    final playback = _diagnosticSection(diagnostics, 'playback');
    final source = _diagnosticSection(diagnostics, 'source');
    final output = _diagnosticSection(diagnostics, 'output');
    final display = _diagnosticSection(diagnostics, 'display');
    final mpv = _diagnosticSection(diagnostics, 'mpv');
    final l10n = AppLocalizations.of(context);

    final sections = <PlaybackDetailSection>[
      PlaybackDetailSection(
        title: l10n.playerDiagnosticsPlaybackSection,
        items: <PlaybackDetailItem>[
          PlaybackDetailItem(
            l10n.playerDiagnosticsStatus,
            _diagnosticString(playback['statusText']),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsPosition,
            _diagnosticDurationMs(playback['positionMs']),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsDuration,
            _diagnosticDurationMs(playback['durationMs']),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsSpeed,
            _diagnosticNumber(playback['playbackSpeed'], suffix: 'x'),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsPaused,
            _diagnosticBool(playback['paused']),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsError,
            _diagnosticString(playback['error']),
          ),
        ],
      ),
      PlaybackDetailSection(
        title: l10n.playerDiagnosticsVideoSection,
        items: <PlaybackDetailItem>[
          PlaybackDetailItem(
            l10n.playerDiagnosticsVideoCodec,
            _diagnosticString(mpv['videoCodec'] ?? _currentVideoCodecName),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsDolbyVision,
            _dolbyVisionStatusLabel(source: source, mpv: mpv),
          ),
          PlaybackDetailItem(
            'DV Profile / Level',
            _dolbyVisionProfileLevelLabel(mpv),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsResolution,
            _joinDetailValues(<String>[
              _diagnosticResolution(mpv['videoParamsW'], mpv['videoParamsH']),
              _currentResolution.trim(),
            ]),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsVideoOutput,
            _diagnosticString(mpv['vo']),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsDecoder,
            _decoderDetailLabelFromDiagnostics(output: output, mpv: mpv),
          ),
        ],
      ),
      PlaybackDetailSection(
        title: l10n.playerDiagnosticsAudioSection,
        items: <PlaybackDetailItem>[
          PlaybackDetailItem(
            l10n.playerDiagnosticsCurrentAudioTrack,
            _currentAudioTrack()?.detailLabel.trim() ?? '',
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsAudioCodec,
            _diagnosticString(mpv['audioCodec']),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsAudioChain,
            _audioOutputChainLabel(mpv: mpv),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsOutputParams,
            _audioOutputParamsLabel(mpv),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsOutputDevice,
            _audioRendererLabel(mpv),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsExternalAudio,
            _diagnosticString(output['connectedAudioSummary']),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsUsbAudio,
            _usbAudioStatusLabel(output),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsSystemDefaultOutput,
            _systemAudioOutputLabel(output),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsCurrentSubtitle,
            _currentSubtitleTrack()?.detailLabel.trim() ?? l10n.mpvOptionOff,
          ),
        ],
      ),
      PlaybackDetailSection(
        title: l10n.playerDiagnosticsOutputDisplaySection,
        items: <PlaybackDetailItem>[
          PlaybackDetailItem(
            l10n.playerDiagnosticsHdrDolbyPipeline,
            _hdrPipelineLabel(source: source, output: output, mpv: mpv),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsColorMode,
            _diagnosticString(output['windowColorMode']),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsDeviceInfo,
            _diagnosticString(
              display['deviceProfileSummary'] ?? display['deviceProfile'],
            ),
          ),
        ],
      ),
      PlaybackDetailSection(
        title: l10n.playerDiagnosticsSourceSection,
        items: <PlaybackDetailItem>[
          PlaybackDetailItem(
            l10n.playerDiagnosticsTitleLabel,
            _currentTitle.trim(),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsMediaId,
            _diagnosticString(source['mediaGuid'] ?? _currentMediaGuid),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsVideoStream,
            _diagnosticString(source['videoGuid'] ?? _currentVideoGuid),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsAudioStream,
            _diagnosticString(source['audioGuid'] ?? _currentAudioGuid),
          ),
          PlaybackDetailItem(
            l10n.playerDiagnosticsSubtitleStream,
            _diagnosticString(source['subtitleGuid'] ?? _currentSubtitleGuid),
          ),
        ],
      ),
    ];

    return sections
        .map(
          (section) => PlaybackDetailSection(
            title: section.title,
            items: section.items
                .where((item) => item.value.trim().isNotEmpty)
                .toList(growable: false),
          ),
        )
        .where((section) => section.items.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, Object?> _diagnosticSection(
    Map<String, Object?> diagnostics,
    String key,
  ) {
    final raw = diagnostics[key];
    if (raw is Map<String, Object?>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, Object?>{};
  }

  String _diagnosticString(Object? value) {
    if (value == null) return '';
    final text = value.toString().trim();
    if (text.isEmpty || text == '-' || text == 'null') return '';
    return text;
  }

  String _diagnosticBool(Object? value) {
    final l10n = AppLocalizations.of(context);
    return value is bool
        ? (value ? l10n.commonYes : l10n.commonNo)
        : _diagnosticString(value);
  }

  String _diagnosticNumber(Object? value, {String suffix = ''}) {
    if (value == null) return '';
    final text = value.toString().trim();
    if (text.isEmpty || text == '0' || text == '0.0') return '';
    return '$text$suffix';
  }

  String _diagnosticDurationMs(Object? value) {
    final raw = int.tryParse('${value ?? ''}');
    if (raw == null || raw <= 0) return '';
    return _formatDuration(Duration(milliseconds: raw));
  }

  String _diagnosticResolution(Object? width, Object? height) {
    final w = int.tryParse('${width ?? ''}') ?? 0;
    final h = int.tryParse('${height ?? ''}') ?? 0;
    if (w <= 0 || h <= 0) return '';
    return '${w}x$h';
  }

  String _joinDetailValues(List<String> values) {
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' / ');
  }

  String _decoderDetailLabelFromDiagnostics({
    required Map<String, Object?> output,
    required Map<String, Object?> mpv,
  }) {
    for (final candidate in <Object?>[
      output['preferredHwdecMode'],
      output['forcedHwdecMode'],
      output['activeHwdecMode'],
      mpv['hwdecCurrent'],
      _decoderMode == _MpvPlayerPageState._decoderModeSoftware ? 'no' : null,
    ]) {
      final label = _decoderDetailLabel(candidate);
      if (label.isNotEmpty) return label;
    }
    return '';
  }

  String _decoderDetailLabel(Object? value) {
    final normalized = _diagnosticString(value).toLowerCase();
    if (normalized.isEmpty) return '';
    if (normalized == 'no') {
      return AppLocalizations.of(context).playerSoftwareDecoderTitle;
    }
    if (normalized.contains('mediacodec')) {
      return AppLocalizations.of(context).playerHardwareDecoderTitle;
    }
    return normalized;
  }

  bool _isDolbyVisionDetected({
    required Map<String, Object?> source,
    required Map<String, Object?> mpv,
  }) {
    final codec = _diagnosticString(
      source['videoCodecName'] ?? mpv['videoCodec'] ?? _currentVideoCodecName,
    ).toLowerCase();
    final profile = _diagnosticString(
      source['videoProfile'] ?? _currentVideoProfile,
    ).toLowerCase();
    final dvProfile = _diagnosticString(
      mpv['dolbyVisionProfile'],
    ).toLowerCase();
    final dvLevel = _diagnosticString(mpv['dolbyVisionLevel']).toLowerCase();
    return codec.contains('dovi') ||
        codec.contains('dvhe') ||
        codec.contains('dvh1') ||
        profile.contains('dolby vision') ||
        profile.contains('dolbyvision') ||
        dvProfile.isNotEmpty ||
        dvLevel.isNotEmpty;
  }

  String _dolbyVisionStatusLabel({
    required Map<String, Object?> source,
    required Map<String, Object?> mpv,
  }) {
    final l10n = AppLocalizations.of(context);
    return _isDolbyVisionDetected(source: source, mpv: mpv)
        ? l10n.playerRecognized
        : l10n.playerUnrecognized;
  }

  String _dolbyVisionProfileLevelLabel(Map<String, Object?> mpv) {
    final profile = _diagnosticString(mpv['dolbyVisionProfile']);
    final level = _diagnosticString(mpv['dolbyVisionLevel']);
    if (profile.isEmpty && level.isEmpty) return '';
    if (profile.isNotEmpty && level.isNotEmpty) {
      return 'Profile $profile / Level $level';
    }
    if (profile.isNotEmpty) return 'Profile $profile';
    return 'Level $level';
  }

  String _hdrPipelineLabel({
    required Map<String, Object?> source,
    required Map<String, Object?> output,
    required Map<String, Object?> mpv,
  }) {
    final pipeline = _diagnosticString(
      output['activeColorPipeline'],
    ).toUpperCase();
    final hdrLikely =
        _diagnosticString(source['hdrLikely']).toLowerCase() == 'true';
    final dvDetected = _isDolbyVisionDetected(source: source, mpv: mpv);
    final l10n = AppLocalizations.of(context);
    final base = dvDetected
        ? l10n.playerDolbyVisionSource
        : (hdrLikely ? l10n.playerHdrSource : l10n.playerSdrSource);
    final mode = switch (pipeline) {
      'HDR_DIRECT' => l10n.playerHdrDirect,
      'HDR_TONEMAP_SDR' => l10n.playerSdrTonemap,
      'SDR' => l10n.playerSdrPipeline,
      _ => _diagnosticString(output['preferredColorPipeline']),
    };
    if (mode.isEmpty) return base;
    return '$base / $mode';
  }

  String _audioOutputChainLabel({required Map<String, Object?> mpv}) {
    final codec = _diagnosticString(mpv['audioCodec']).toLowerCase();
    final ao = _diagnosticString(mpv['ao']).toLowerCase();
    final device = _diagnosticString(mpv['audioDevice']).toLowerCase();
    final directOut =
        ao.contains('spdif') ||
        ao.contains('passthrough') ||
        device.contains('spdif') ||
        device.contains('passthrough');
    if (directOut) {
      return AppLocalizations.of(context).playerAudioPassthrough;
    }
    final dolbyLike =
        codec.contains('truehd') ||
        codec.contains('eac3') ||
        codec.contains('ac3') ||
        codec.contains('atmos');
    final l10n = AppLocalizations.of(context);
    if (dolbyLike) {
      return l10n.playerAudioDecodedNonPassthrough;
    }
    return l10n.playerAudioDecoded;
  }

  String _audioOutputParamsLabel(Map<String, Object?> mpv) {
    final sampleRate = int.tryParse('${mpv['audioOutParamsSamplerate'] ?? ''}');
    final channels = _diagnosticString(mpv['audioOutParamsChannels']);
    final format = _diagnosticString(mpv['audioOutParamsFormat']);
    final inputChannels = _diagnosticString(mpv['audioParamsChannels']);
    final inputFormat = _diagnosticString(mpv['audioParamsFormat']);
    final parts = <String>[
      if (sampleRate != null && sampleRate > 0) '${sampleRate}Hz',
      if (channels.isNotEmpty) channels,
      if (format.isNotEmpty) format,
      if (channels.isEmpty && inputChannels.isNotEmpty) inputChannels,
      if (format.isEmpty && inputFormat.isNotEmpty) inputFormat,
    ];
    return _joinDetailValues(parts);
  }

  String _audioRendererLabel(Map<String, Object?> mpv) {
    return _joinDetailValues(<String>[
      _diagnosticString(mpv['ao']),
      _diagnosticString(mpv['audioDevice']),
    ]);
  }

  String _usbAudioStatusLabel(Map<String, Object?> output) {
    final connected =
        _diagnosticString(output['usbAudioConnected']).toLowerCase() == 'true';
    final summary = _diagnosticString(output['usbAudioSummary']);
    final l10n = AppLocalizations.of(context);
    if (connected && summary.isNotEmpty) {
      return '${l10n.playerConnected} / $summary';
    }
    if (connected) return l10n.playerConnected;
    return l10n.playerNotDetected;
  }

  String _systemAudioOutputLabel(Map<String, Object?> output) {
    final sampleRate = int.tryParse(
      '${output['systemOutputSampleRate'] ?? ''}',
    );
    final framesPerBuffer = int.tryParse(
      '${output['systemOutputFramesPerBuffer'] ?? ''}',
    );
    final parts = <String>[
      if (sampleRate != null && sampleRate > 0) '${sampleRate}Hz',
      if (framesPerBuffer != null && framesPerBuffer > 0)
        'buffer $framesPerBuffer',
    ];
    return _joinDetailValues(parts);
  }
}
