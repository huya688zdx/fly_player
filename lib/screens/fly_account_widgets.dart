part of 'fly_account_screen.dart';

String _backendLabel(BuildContext context, Object? kind) => switch (kind) {
  'feiniu' => AppLocalizations.of(context).connectionFeiniuMedia,
  'emby' => 'Emby',
  'jellyfin' => 'Jellyfin',
  _ => AppLocalizations.of(context).flyAccountMediaService,
};

class _FlyAccountPage extends StatelessWidget {
  const _FlyAccountPage({
    required this.title,
    required this.identityBuilder,
    required this.children,
  });

  final String title;
  final Widget Function(bool desktop) identityBuilder;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: buildSecondaryHostAppBar(
          context,
          title: Text(AppLocalizations.of(context).connectionAppName),
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop =
                  DesktopEnvironment.isDesktopPlatform &&
                  constraints.maxWidth >= 900;
              final inset = ((constraints.maxWidth - 1184) / 2).clamp(
                20.0,
                double.infinity,
              );
              final sources = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              );
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  inset,
                  desktop ? 32 : 20,
                  inset,
                  32,
                ),
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: desktop ? 32 : 25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppLocalizations.of(context).flyAccountChooseSourceSubtitle,
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  SizedBox(height: desktop ? 32 : 24),
                  if (desktop)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 260, child: identityBuilder(true)),
                        const SizedBox(width: 34),
                        Expanded(child: sources),
                      ],
                    )
                  else ...[
                    identityBuilder(false),
                    const SizedBox(height: 28),
                    sources,
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FlyLoginPage extends StatelessWidget {
  const _FlyLoginPage({
    required this.child,
    required this.onSwitch,
    required this.onEditDeviceName,
  });

  final Widget child;
  final VoidCallback? onSwitch;
  final VoidCallback? onEditDeviceName;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    return AppAmbientPage(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: LoginPageShell(
            flyMode: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LoginConnectionModeBar(flyMode: true, onSwitch: onSwitch),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.flyAccountLoginTitle,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.flyAccountCurrentDeviceName,
                      onPressed: onEditDeviceName,
                      icon: Icon(
                        Icons.settings_outlined,
                        size: 20,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.flyAccountLoginSubtitle,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FlyAccountIdentity extends StatelessWidget {
  const _FlyAccountIdentity({
    required this.desktop,
    required this.username,
    required this.serverUrl,
    required this.deviceName,
    required this.onLogout,
  });

  final bool desktop;
  final String username, serverUrl, deviceName;
  final VoidCallback? onLogout;

  Widget _connectionDetails(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.flyAccountServiceAddress,
          style: TextStyle(color: colors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        SelectableText(
          serverUrl,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          l10n.flyAccountCurrentDeviceName,
          style: TextStyle(color: colors.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 6),
        SelectableText(
          deviceName,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final avatar = Container(
      width: desktop ? 52 : 40,
      height: desktop ? 52 : 40,
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.person_outline_rounded, color: colors.accent, size: 26),
    );
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.flyAccountUsername,
          style: TextStyle(color: colors.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 5),
        Text(
          username,
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: desktop ? 20 : 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.flyAccountLoggedIn,
          style: TextStyle(color: colors.success, fontSize: 12),
        ),
      ],
    );
    final logout = TextButton.icon(
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        minimumSize: const Size(0, 48),
        foregroundColor: colors.textMuted,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      onPressed: onLogout,
      icon: const Icon(Icons.logout_rounded, size: 17),
      label: Text(l10n.flyAccountLogout, style: const TextStyle(fontSize: 12)),
    );
    return Container(
      padding: EdgeInsets.all(desktop ? 24 : 16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.borderSubtle),
        borderRadius: BorderRadius.circular(18),
      ),
      child: desktop
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(alignment: Alignment.centerLeft, child: avatar),
                const SizedBox(height: 20),
                identity,
                const SizedBox(height: 12),
                Text(
                  l10n.flyAccountAdminSharedSubtitle,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(height: 1),
                ),
                _connectionDetails(context),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(height: 1),
                ),
                logout,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      avatar,
                      const SizedBox(width: 12),
                      Expanded(child: identity),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(width: 112, child: logout),
              ],
            ),
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
    required this.hasCurrentSource,
    required this.busy,
    required this.connecting,
    required this.onEnter,
  });

  final Map<String, dynamic> binding;
  final bool current, hasCurrentSource, busy, connecting;
  final VoidCallback onEnter;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final server = binding['server'] as Map? ?? const {};
    final kind = server['kind'];
    final status = binding['status'];
    final available = status == 'active' || status == 'offline';
    final username = binding['remote_username'] as String? ?? '';
    final statusLabel = switch (status) {
      'active' => l10n.flyAccountStatusConnectable,
      'offline' => l10n.flyAccountStatusOffline,
      'reauth_required' => l10n.flyAccountStatusReauthRequired,
      'unbound' => l10n.flyAccountStatusUnbound,
      _ => l10n.flyAccountStatusUnavailable,
    };
    final logo = switch (kind) {
      'feiniu' => 'lib/img/feiniu_Logo.png',
      'emby' => 'lib/img/Emby_logo.png',
      'jellyfin' => 'lib/img/jellyfin_logo.png',
      _ => null,
    };
    final buttonLabel = connecting
        ? l10n.flyAccountConnecting
        : !available
        ? statusLabel
        : status == 'offline'
        ? l10n.flyAccountTryConnect
        : current || !hasCurrentSource
        ? l10n.flyAccountEnterLibrary
        : l10n.flyAccountSwitchAndEnter;
    final buttonColor = colors.accentStrong;
    final buttonForeground =
        ThemeData.estimateBrightnessForColor(buttonColor) == Brightness.dark
        ? Colors.white
        : Colors.black;

    Widget badge(String label, {bool selected = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? colors.accentSoft : colors.surfaceSubtle,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? colors.accentStrong : colors.textSecondary,
          fontSize: 11,
          height: 1.3,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 600;
        final details = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: current ? 56 : 46,
              height: current ? 56 : 46,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: current ? colors.accentSoft : colors.surfaceSubtle,
                border: Border.all(color: colors.borderSubtle),
                borderRadius: BorderRadius.circular(13),
              ),
              child: logo == null
                  ? Icon(Icons.video_library_outlined, color: colors.textMuted)
                  : Image.asset(logo, fit: BoxFit.contain),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    binding['label'] as String? ?? _backendLabel(context, kind),
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: current ? 23 : 16,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    [
                      _backendLabel(context, kind),
                      if (username.isNotEmpty) username,
                    ].join(' · '),
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  if (!current) ...[
                    const SizedBox(height: 8),
                    badge(statusLabel),
                  ],
                ],
              ),
            ),
          ],
        );
        final buttonChild = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (connecting) ...[
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: current ? buttonForeground : colors.accent,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(child: Text(buttonLabel, textAlign: TextAlign.center)),
            if (!connecting && available) ...[
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, size: 18),
            ],
          ],
        );
        final button = current
            ? FilledButton(
                key: ValueKey('fly-source-enter-${binding['id']}'),
                onPressed: !busy && available ? onEnter : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  backgroundColor: buttonColor,
                  foregroundColor: buttonForeground,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                child: buttonChild,
              )
            : OutlinedButton(
                key: ValueKey('fly-source-enter-${binding['id']}'),
                onPressed: !busy && available ? onEnter : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  foregroundColor: colors.textPrimary,
                  side: BorderSide(color: colors.borderStrong),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                child: buttonChild,
              );
        return Container(
          key: ValueKey('fly-source-${binding['id']}'),
          padding: EdgeInsets.all(horizontal ? 26 : 20),
          decoration: BoxDecoration(
            color: current ? null : colors.surface,
            gradient: current
                ? LinearGradient(colors: [colors.accentSoft, colors.surface])
                : null,
            border: Border.all(
              color: current
                  ? colors.accent.withValues(alpha: .5)
                  : colors.borderSubtle,
            ),
            borderRadius: BorderRadius.circular(horizontal ? 18 : 15),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (current) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    badge(l10n.flyAccountCurrentSource, selected: true),
                    if (status != 'active') badge(statusLabel),
                  ],
                ),
                const SizedBox(height: 24),
              ],
              if (horizontal)
                Row(
                  children: [
                    Expanded(child: details),
                    const SizedBox(width: 20),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * .38,
                      ),
                      child: button,
                    ),
                  ],
                )
              else ...[
                details,
                const SizedBox(height: 22),
                button,
              ],
              if (current || !available) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Divider(height: 1),
                ),
                Text(
                  available
                      ? l10n.flyAccountReuseAuthorization
                      : l10n.flyAccountSourceHelpDetail,
                  style: TextStyle(
                    color: colors.textMuted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
