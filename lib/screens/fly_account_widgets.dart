part of 'fly_account_screen.dart';

String _backendLabel(BuildContext context, Object? kind) => switch (kind) {
  'feiniu' => AppLocalizations.of(context).connectionFeiniuMedia,
  'emby' => 'Emby',
  'jellyfin' => 'Jellyfin',
  _ => AppLocalizations.of(context).flyAccountMediaService,
};

class _FlyAccountPage extends StatelessWidget {
  const _FlyAccountPage({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final inset = ((constraints.maxWidth - 760) / 2).clamp(
                20.0,
                double.infinity,
              );
              return ListView(
                padding: EdgeInsets.fromLTRB(inset, 16, inset, 32),
                children: children,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FlyLoginPage extends StatelessWidget {
  const _FlyLoginPage({required this.child});

  final Widget child;

  Widget _form(BuildContext context) {
    final colors = context.appColors;
    return LoginFormPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppLocalizations.of(context).flyAccountLoginTitle,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
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
                          child: LoginLogoHeader(
                            title: AppLocalizations.of(
                              context,
                            ).connectionAppName,
                          ),
                        ),
                        const SizedBox(width: 32),
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
                            child: LoginLogoHeader(
                              title: AppLocalizations.of(
                                context,
                              ).connectionAppName,
                            ),
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
  });

  final Map<String, dynamic> binding;
  final bool current, busy;
  final VoidCallback onEnter;

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
    return Semantics(
      enabled: !busy && available,
      child: AppOptionListTile(
        tileKey: ValueKey('fly-source-${binding['id']}'),
        title: binding['label'] as String? ?? _backendLabel(context, kind),
        subtitle: [
          [
            _backendLabel(context, kind),
            if (username.isNotEmpty) username,
          ].join(' · '),
          current
              ? AppLocalizations.of(context).flyAccountCurrentSource
              : statusLabel,
          if (!available)
            AppLocalizations.of(context).flyAccountSourceHelpDetail,
        ].join('\n'),
        selected: current,
        outlined: true,
        trailing: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: logo == null
              ? Icon(Icons.video_library_outlined, color: colors.textMuted)
              : Image.asset(logo, width: 32, height: 32, fit: BoxFit.contain),
        ),
        onTap: () {
          if (!busy && available) onEnter();
        },
      ),
    );
  }
}
