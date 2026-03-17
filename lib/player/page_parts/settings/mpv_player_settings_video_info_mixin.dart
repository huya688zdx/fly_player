part of mpv_player_page;

extension _MpvPlayerSettingsVideoInfoMixin on _MpvPlayerPageState {
  Widget _buildPlaybackSettingsVideoInfoPage(
    BuildContext context,
    PlayerNestedSheetController<void> drawer,
  ) {
    return PlayerNestedSheetScaffold(
      header: PlayerNestedSheetHeader(title: '播放诊断', onBack: drawer.popPage),
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
                  '读取播放诊断失败：${snapshot.error}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            );
          }
          final sections = _buildPlaybackDetailSections(
            snapshot.data ?? const <String, Object?>{},
          );
          if (sections.isEmpty) {
            return const Center(
              child: Text(
                '暂时没有可显示的播放信息',
                style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 14),
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

    final sections = <PlaybackDetailSection>[
      PlaybackDetailSection(
        title: '播放信息',
        items: <PlaybackDetailItem>[
          PlaybackDetailItem('状态', _diagnosticString(playback['statusText'])),
          PlaybackDetailItem(
            '当前位置',
            _diagnosticDurationMs(playback['positionMs']),
          ),
          PlaybackDetailItem(
            '总时长',
            _diagnosticDurationMs(playback['durationMs']),
          ),
          PlaybackDetailItem(
            '播放速度',
            _diagnosticNumber(playback['playbackSpeed'], suffix: 'x'),
          ),
          PlaybackDetailItem('已暂停', _diagnosticBool(playback['paused'])),
          PlaybackDetailItem('错误', _diagnosticString(playback['error'])),
        ],
      ),
      PlaybackDetailSection(
        title: '视频',
        items: <PlaybackDetailItem>[
          PlaybackDetailItem(
            '视频编码',
            _diagnosticString(mpv['videoCodec'] ?? _currentVideoCodecName),
          ),
          PlaybackDetailItem(
            '杜比视界',
            _dolbyVisionStatusLabel(source: source, mpv: mpv),
          ),
          PlaybackDetailItem(
            'DV Profile / Level',
            _dolbyVisionProfileLevelLabel(mpv),
          ),
          PlaybackDetailItem(
            '分辨率',
            _joinDetailValues(<String>[
              _diagnosticResolution(mpv['videoParamsW'], mpv['videoParamsH']),
              _currentResolution.trim(),
            ]),
          ),
          PlaybackDetailItem('视频输出', _diagnosticString(mpv['vo'])),
          PlaybackDetailItem(
            '解码方式',
            _decoderDetailLabelFromDiagnostics(output: output, mpv: mpv),
          ),
        ],
      ),
      PlaybackDetailSection(
        title: '音频',
        items: <PlaybackDetailItem>[
          PlaybackDetailItem(
            '当前音轨',
            _currentAudioTrack()?.detailLabel.trim() ?? '',
          ),
          PlaybackDetailItem('音频编码', _diagnosticString(mpv['audioCodec'])),
          PlaybackDetailItem('音频链路', _audioOutputChainLabel(mpv: mpv)),
          PlaybackDetailItem('输出参数', _audioOutputParamsLabel(mpv)),
          PlaybackDetailItem('输出设备', _audioRendererLabel(mpv)),
          PlaybackDetailItem(
            '已接入外接音频',
            _diagnosticString(output['connectedAudioSummary']),
          ),
          PlaybackDetailItem('USB / 小尾巴', _usbAudioStatusLabel(output)),
          PlaybackDetailItem('系统默认输出', _systemAudioOutputLabel(output)),
          PlaybackDetailItem(
            '当前字幕',
            _currentSubtitleTrack()?.detailLabel.trim() ?? '关闭',
          ),
        ],
      ),
      PlaybackDetailSection(
        title: '输出与显示',
        items: <PlaybackDetailItem>[
          PlaybackDetailItem(
            'HDR / 杜比链路',
            _hdrPipelineLabel(source: source, output: output, mpv: mpv),
          ),
          PlaybackDetailItem(
            '色彩模式',
            _diagnosticString(output['windowColorMode']),
          ),
          PlaybackDetailItem(
            '设备信息',
            _diagnosticString(
              display['deviceProfileSummary'] ?? display['deviceProfile'],
            ),
          ),
        ],
      ),
      PlaybackDetailSection(
        title: '片源',
        items: <PlaybackDetailItem>[
          PlaybackDetailItem('标题', _currentTitle.trim()),
          PlaybackDetailItem(
            '媒体标识',
            _diagnosticString(source['mediaGuid'] ?? _currentMediaGuid),
          ),
          PlaybackDetailItem(
            '视频流',
            _diagnosticString(source['videoGuid'] ?? _currentVideoGuid),
          ),
          PlaybackDetailItem(
            '音频流',
            _diagnosticString(source['audioGuid'] ?? _currentAudioGuid),
          ),
          PlaybackDetailItem(
            '字幕流',
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
    return value is bool ? (value ? '是' : '否') : _diagnosticString(value);
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
    if (normalized == 'no') return '软解码';
    if (normalized.contains('mediacodec')) return '硬解码';
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
    return _isDolbyVisionDetected(source: source, mpv: mpv) ? '已识别' : '未识别';
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
    final base = dvDetected ? '杜比视界片源' : (hdrLikely ? 'HDR片源' : 'SDR片源');
    final mode = switch (pipeline) {
      'HDR_DIRECT' => 'HDR直出',
      'HDR_TONEMAP_SDR' => 'SDR映射',
      'SDR' => 'SDR链路',
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
      return '直通输出';
    }
    final dolbyLike =
        codec.contains('truehd') ||
        codec.contains('eac3') ||
        codec.contains('ac3') ||
        codec.contains('atmos');
    if (dolbyLike) {
      return '解码播放（非直通）';
    }
    return '解码播放';
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
    if (connected && summary.isNotEmpty) return '已接入 / $summary';
    if (connected) return '已接入';
    return '未检测到';
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
