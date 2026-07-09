import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/feiniu_api.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/media_info.dart';
import '../providers/nas_provider.dart';
import '../utils/app_exception.dart';
import '../widgets/common/app_error_state.dart';

class MediaInfoScreen extends StatefulWidget {
  const MediaInfoScreen({super.key});

  @override
  State<MediaInfoScreen> createState() => _MediaInfoScreenState();
}

class _MediaInfoScreenState extends State<MediaInfoScreen> {
  final _guidController = TextEditingController();
  MediaInfo? _mediaInfo;
  bool _isLoading = false;
  AppException? _error;

  @override
  void dispose() {
    _guidController.dispose();
    super.dispose();
  }

  Future<void> _fetchMetadata() async {
    final guid = _guidController.text.trim();
    if (guid.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _mediaInfo = null;
    });

    try {
      final api = FeiniuApi(context.read<NasProvider>());
      final info = await api.getStreamMetadata(guid);
      setState(() {
        _mediaInfo = info;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = AppException.from(
          e,
          action: 'stream metadata',
          fallbackKind: AppExceptionKind.transient,
        );
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.mediaInfoViewerTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _guidController,
                    decoration: InputDecoration(
                      labelText: l10n.mediaInfoGuidLabel,
                      hintText: l10n.mediaInfoGuidHint,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _fetchMetadata,
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (_isLoading) const CircularProgressIndicator(),
            if (_error != null)
              Expanded(
                child: AppErrorState(error: _error!, onRetry: _fetchMetadata),
              ),
            if (_mediaInfo != null)
              Expanded(child: _buildInfoList(_mediaInfo!)),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoList(MediaInfo info) {
    final l10n = AppLocalizations.of(context);
    final api = FeiniuApi(context.read<NasProvider>());
    final streamUrl = api.getStreamUrl(_guidController.text.trim());

    return ListView(
      children: [
        ListTile(
          title: Text(l10n.mediaInfoFilename),
          subtitle: Text(info.fileStream?.filename ?? l10n.mediaInfoUnknown),
        ),
        ListTile(
          title: Text(l10n.mediaInfoVideoCodec),
          subtitle: Text(
            '${info.videoStream?.codec} (${info.videoStream?.width}x${info.videoStream?.height})',
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            l10n.mediaInfoAudioStreams,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        ...info.audioStreams.map(
          (s) => ListTile(
            title: Text(l10n.mediaInfoStreamTitle(s.index, s.codec)),
            subtitle: Text(
              l10n.mediaInfoLanguage(s.language ?? l10n.mediaInfoNotAvailable),
            ),
          ),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            l10n.mediaInfoSubtitleStreams,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        ...info.subtitleStreams.map(
          (s) => ListTile(
            title: Text(l10n.mediaInfoStreamTitle(s.index, s.codec)),
            subtitle: Text(
              l10n.mediaInfoLanguage(s.language ?? l10n.mediaInfoNotAvailable),
            ),
          ),
        ),
        const Divider(),
        ListTile(
          title: Text(l10n.mediaInfoStreamUrlGenerated),
          subtitle: Text(streamUrl, style: const TextStyle(fontSize: 12)),
          onTap: () {
            // Future: Copy to clipboard or open in external player
          },
        ),
      ],
    );
  }
}
