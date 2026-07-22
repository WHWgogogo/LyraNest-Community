import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/l10n.dart';
import '../data/github_release_checker.dart';

typedef LyraNestReleaseChecker = Future<LyraNestRelease> Function();
typedef LyraNestLinkOpener = Future<bool> Function(Uri uri);

class AboutPage extends StatefulWidget {
  const AboutPage({
    this.releaseChecker,
    this.linkOpener,
    super.key,
  });

  final LyraNestReleaseChecker? releaseChecker;
  final LyraNestLinkOpener? linkOpener;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  var _checkingForUpdates = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Image.asset(
                    'assets/branding/logo.png',
                    width: 136,
                    height: 136,
                    fit: BoxFit.contain,
                    semanticLabel: l10n.appTitle,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.appTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.appVersion(currentLyraNestVersion),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.aboutDescription,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      ListTile(
                        key: const ValueKey('about-check-updates'),
                        leading: _checkingForUpdates
                            ? const SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                ),
                              )
                            : const Icon(Icons.system_update_alt_rounded),
                        title: Text(l10n.checkForUpdates),
                        subtitle: Text(l10n.checkForUpdatesDescription),
                        enabled: !_checkingForUpdates,
                        onTap: _checkingForUpdates ? null : _checkForUpdates,
                      ),
                      const Divider(height: 1),
                      _ExternalLinkTile(
                        key: const ValueKey('about-project-address'),
                        icon: Icons.code_rounded,
                        title: l10n.projectAddress,
                        subtitle: 'github.com/WHWgogogo/LyraNest-Community',
                        onTap: () => _openUri(lyraNestRepositoryUri),
                      ),
                      const Divider(height: 1),
                      _ExternalLinkTile(
                        key: const ValueKey('about-author-homepage'),
                        icon: Icons.person_outline_rounded,
                        title: l10n.authorHomepage,
                        subtitle: 'github.com/WHWgogogo',
                        onTap: () => _openUri(lyraNestAuthorUri),
                      ),
                      const Divider(height: 1),
                      _ExternalLinkTile(
                        key: const ValueKey('about-contact-author'),
                        icon: Icons.mail_outline_rounded,
                        title: l10n.contactAuthor,
                        subtitle: 'whw1377236334@163.com',
                        onTap: () => _openUri(lyraNestContactUri),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _checkForUpdates() async {
    setState(() => _checkingForUpdates = true);
    try {
      final release =
          await (widget.releaseChecker ?? checkLatestLyraNestRelease)();
      if (!mounted) {
        return;
      }
      if (!release.isNewerThanCurrent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.alreadyLatestVersion)),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.updateAvailable),
          content: Text(
            context.l10n.updateAvailableDescription(release.version),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openUri(release.releaseUri);
              },
              child: Text(context.l10n.openDownloadPage),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.updateCheckFailed)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _checkingForUpdates = false);
      }
    }
  }

  Future<void> _openUri(Uri uri) async {
    final opened = await (widget.linkOpener ?? _launchExternalUri)(uri);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.couldNotOpenLink)),
      );
    }
  }
}

Future<bool> _launchExternalUri(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

class _ExternalLinkTile extends StatelessWidget {
  const _ExternalLinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.open_in_new_rounded),
      onTap: onTap,
    );
  }
}
