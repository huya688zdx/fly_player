part of 'fly_account_screen.dart';

String _backendLabel(Object? kind) => switch (kind) {
  'feiniu' => '飞牛影视',
  'emby' => 'Emby',
  'jellyfin' => 'Jellyfin',
  _ => '媒体服务',
};

String _addressLabel(Object? purpose) => switch (purpose) {
  'client_lan' => '局域网连接',
  'client_remote' => '远程连接（HTTPS）',
  'vpn' => 'VPN 连接',
  _ => '其他连接',
};

class _FlyAccountPage extends StatelessWidget {
  const _FlyAccountPage({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final desktop =
        DesktopEnvironment.isDesktopPlatform &&
        MediaQuery.sizeOf(context).width >= 900;
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildSecondaryHostAppBar(
          context,
          title: Text(
            title,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  desktop ? 28 : 20,
                  16,
                  desktop ? 28 : 20,
                  48,
                ),
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlyLoginPage extends StatelessWidget {
  const _FlyLoginPage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 40).clamp(
                      0,
                      double.infinity,
                    ),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: _FlySurface(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.asset(
                                    'lib/img/app_logo.png',
                                    width: 48,
                                    height: 48,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '飞翔',
                                        style: TextStyle(
                                          color: colors.textPrimary,
                                          fontSize: 25,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        '连接你的媒体，继续你的观看',
                                        style: TextStyle(
                                          color: colors.textMuted,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '登录飞翔账号',
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '使用飞翔管理后台的账号，管理媒体来源和观看记录。',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 13,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 16),
                            child,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FlySurface extends StatelessWidget {
  const _FlySurface({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.selected = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: AppAmbientPage.cardColorOf(
        context,
        selected ? colors.selectionSoft : colors.surface,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _FlySectionTitle extends StatelessWidget {
  const _FlySectionTitle({
    required this.title,
    required this.subtitle,
    this.action,
  });

  final String title, subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AppInfoPopoverAnchor(
                    title: '媒体来源',
                    description:
                        '先登录飞翔，再选择已同步绑定的媒体来源。已绑定的来源无需再次输入媒体账号或地址，播放器会自动尝试可用连接。',
                    detail:
                        '需要指定网络地址时，打开来源设置中的“连接设置”。只有媒体服务要求重新授权时才需要再次登录媒体账号。',
                    child: Tooltip(
                      message: '媒体来源说明',
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class _FlyMessage extends StatelessWidget {
  const _FlyMessage(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Semantics(
      liveRegion: true,
      child: Text(
        message,
        style: TextStyle(
          color: context.appColors.textSecondary,
          fontSize: 13,
          height: 1.5,
        ),
      ),
    ),
  );
}

class _FlySourceCard extends StatelessWidget {
  const _FlySourceCard({
    required this.binding,
    required this.current,
    required this.busy,
    required this.onEnter,
    required this.onReauthorize,
    required this.onAction,
  });

  final Map<String, dynamic> binding;
  final bool current, busy;
  final VoidCallback onEnter, onReauthorize;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final server = binding['server'] as Map? ?? const {};
    final kind = server['kind'];
    final status = binding['status'];
    final available = status == 'active' || status == 'offline';
    final username = binding['remote_username'] as String? ?? '';
    final statusLabel = switch (status) {
      'active' => '可连接',
      'offline' => '暂时离线，可尝试连接',
      'reauth_required' => '需要重新登录媒体账号',
      'unbound' => '已移除，播放历史保留',
      _ => '暂不可用',
    };
    final logo = switch (kind) {
      'feiniu' => 'lib/img/feiniu_Logo.png',
      'emby' => 'lib/img/Emby_logo.png',
      'jellyfin' => 'lib/img/jellyfin_logo.png',
      _ => null,
    };
    return _FlySurface(
      selected: current,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: logo == null
                    ? const Icon(Icons.video_library_outlined)
                    : Image.asset(logo, fit: BoxFit.contain),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      binding['label'] as String? ?? _backendLabel(kind),
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      [
                        _backendLabel(kind),
                        if (username.isNotEmpty) username,
                      ].join(' · '),
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (buttonContext) => IconButton(
                  tooltip: '来源设置',
                  icon: const Icon(Icons.more_horiz_rounded),
                  onPressed: busy
                      ? null
                      : () async {
                          final options = [
                            if (available)
                              const AppActionSheetOption(
                                value: 'address',
                                label: '连接设置',
                              ),
                            const AppActionSheetOption(
                              value: 'reauthorize',
                              label: '重新授权',
                            ),
                            if (status != 'unbound') ...[
                              const AppActionSheetOption(
                                value: 'sync',
                                label: '同步节目资料',
                              ),
                              const AppActionSheetOption(
                                value: 'unbind',
                                label: '移除媒体来源',
                                destructive: true,
                              ),
                            ],
                          ];
                          String? action;
                          if (DesktopEnvironment.isDesktopPlatform) {
                            final box =
                                buttonContext.findRenderObject() as RenderBox;
                            await showDesktopContextMenu(
                              buttonContext,
                              position: box.localToGlobal(
                                Offset(0, box.size.height),
                              ),
                              entries: [
                                for (final option in options)
                                  DesktopContextMenuEntry(
                                    label: option.label,
                                    icon: switch (option.value) {
                                      'address' =>
                                        Icons.settings_ethernet_rounded,
                                      'reauthorize' => Icons.key_rounded,
                                      'sync' => Icons.sync_rounded,
                                      _ => Icons.link_off_rounded,
                                    },
                                    destructive: option.destructive,
                                    onSelected: () => action = option.value,
                                  ),
                              ],
                            );
                          } else {
                            action = await showAppActionSheet<String>(
                              context,
                              title: binding['label'] as String? ?? '来源设置',
                              options: options,
                            );
                          }
                          final selectedAction = action;
                          if (selectedAction != null && context.mounted) {
                            onAction(selectedAction);
                          }
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (current)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.selectionSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '当前来源',
                    style: TextStyle(
                      color: colors.selectionStrong,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Text(
                statusLabel,
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: busy
                  ? null
                  : current || available
                  ? onEnter
                  : onReauthorize,
              icon: Icon(
                current
                    ? Icons.video_library_outlined
                    : available
                    ? Icons.swap_horiz_rounded
                    : Icons.login_rounded,
                size: 18,
              ),
              label: Text(
                current
                    ? '进入媒体库'
                    : available
                    ? '切换到此来源'
                    : '重新授权',
              ),
              style: FilledButton.styleFrom(minimumSize: const Size(156, 42)),
            ),
          ),
        ],
      ),
    );
  }
}
