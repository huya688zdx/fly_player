part of 'fly_account_screen.dart';

String _backendLabel(BuildContext context, Object? kind) => switch (kind) {
  'feiniu' => AppLocalizations.of(context).connectionFeiniuMedia,
  'emby' => 'Emby',
  'jellyfin' => 'Jellyfin',
  _ => AppLocalizations.of(context).flyAccountMediaService,
};

String _addressLabel(BuildContext context, Object? purpose) =>
    switch (purpose) {
      'client_lan' => AppLocalizations.of(context).flyAccountLanConnection,
      'client_remote' => AppLocalizations.of(
        context,
      ).flyAccountRemoteConnection,
      'vpn' => AppLocalizations.of(context).flyAccountVpnConnection,
      _ => AppLocalizations.of(context).flyAccountOtherConnection,
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

  Widget _brand(BuildContext context, {required bool desktop}) {
    final colors = context.appColors;
    final logo = ClipRRect(
      borderRadius: BorderRadius.circular(desktop ? 22 : 14),
      child: Image.asset(
        'lib/img/app_logo.png',
        width: desktop ? 80 : 48,
        height: desktop ? 80 : 48,
      ),
    );
    final title = Text(
      AppLocalizations.of(context).flyAccountBrand,
      style: TextStyle(
        color: colors.textPrimary,
        fontSize: desktop ? 36 : 25,
        fontWeight: FontWeight.w800,
      ),
    );
    if (!desktop) {
      return Row(
        children: [
          logo,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                Text(
                  AppLocalizations.of(context).flyAccountTagline,
                  style: TextStyle(color: colors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        const SizedBox(height: 24),
        title,
        const SizedBox(height: 12),
        Text(
          AppLocalizations.of(
            context,
          ).flyAccountTagline.replaceFirst('，', '，\n'),
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 24,
            height: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final colors = context.appColors;
    return _FlySurface(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppLocalizations.of(context).flyAccountLoginTitle,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop =
                  DesktopEnvironment.isDesktopPlatform &&
                  constraints.maxWidth >= 900;
              final content = desktop
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          key: const Key('flyLoginDesktopBrand'),
                          width: 280,
                          child: _brand(context, desktop: true),
                        ),
                        const SizedBox(width: 56),
                        SizedBox(
                          key: const Key('flyLoginDesktopForm'),
                          width: 460,
                          child: _form(context),
                        ),
                      ],
                    )
                  : ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: _brand(context, desktop: false),
                          ),
                          const SizedBox(height: 24),
                          _form(context),
                        ],
                      ),
                    );
              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.all(desktop ? 32 : 20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - (desktop ? 64 : 40))
                        .clamp(0, double.infinity),
                  ),
                  child: Center(child: content),
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
                    title: AppLocalizations.of(context).flySourceMediaSources,
                    description: AppLocalizations.of(
                      context,
                    ).flyAccountSourceHelpDescription,
                    detail: AppLocalizations.of(
                      context,
                    ).flyAccountSourceHelpDetail,
                    child: Tooltip(
                      message: AppLocalizations.of(
                        context,
                      ).flyAccountSourceHelp,
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
      'active' => AppLocalizations.of(context).flyAccountStatusConnectable,
      'offline' => AppLocalizations.of(context).flyAccountStatusOffline,
      'reauth_required' => AppLocalizations.of(
        context,
      ).flyAccountStatusReauthRequired,
      'unbound' => AppLocalizations.of(context).flyAccountStatusUnbound,
      _ => AppLocalizations.of(context).flyAccountStatusUnavailable,
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
                      binding['label'] as String? ??
                          _backendLabel(context, kind),
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      [
                        _backendLabel(context, kind),
                        if (username.isNotEmpty) username,
                      ].join(' · '),
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (buttonContext) => IconButton(
                  tooltip: AppLocalizations.of(
                    context,
                  ).flyAccountSourceSettings,
                  icon: const Icon(Icons.more_horiz_rounded),
                  onPressed: busy
                      ? null
                      : () async {
                          final options = [
                            if (available)
                              AppActionSheetOption(
                                value: 'address',
                                label: AppLocalizations.of(
                                  context,
                                ).flyAccountConnectionSettings,
                              ),
                            AppActionSheetOption(
                              value: 'reauthorize',
                              label: AppLocalizations.of(
                                context,
                              ).flyAccountReauthorize,
                            ),
                            if (status != 'unbound') ...[
                              AppActionSheetOption(
                                value: 'sync',
                                label: AppLocalizations.of(
                                  context,
                                ).flyAccountSyncCatalog,
                              ),
                              AppActionSheetOption(
                                value: 'unbind',
                                label: AppLocalizations.of(
                                  context,
                                ).flyAccountRemoveSourceTitle,
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
                              title:
                                  binding['label'] as String? ??
                                  AppLocalizations.of(
                                    context,
                                  ).flyAccountSourceSettings,
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
                    AppLocalizations.of(context).flyAccountCurrentSource,
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
                    ? AppLocalizations.of(context).flyAccountEnterLibrary
                    : available
                    ? AppLocalizations.of(context).flyAccountSwitchSource
                    : AppLocalizations.of(context).flyAccountReauthorize,
              ),
              style: FilledButton.styleFrom(minimumSize: const Size(156, 42)),
            ),
          ),
        ],
      ),
    );
  }
}
