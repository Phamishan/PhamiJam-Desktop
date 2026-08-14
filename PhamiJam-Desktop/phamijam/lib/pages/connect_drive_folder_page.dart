import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phamijam/services/drive_folder_service.dart';
import 'package:phamijam/services/google_drive_auth_service.dart';
import 'package:phamijam/services/google_drive_service.dart';
import 'package:webview_windows/webview_windows.dart';

const String _pickerUrl =
    'https://phamijam-share.phamijam.workers.dev/drive-picker';

enum _ConnectMode { chooser, pastedLink, oauth }

Future<bool?> showConnectDriveFolderDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const ConnectDriveFolderPage(),
  );
}

class ConnectDriveFolderPage extends StatefulWidget {
  const ConnectDriveFolderPage({super.key});

  @override
  State<ConnectDriveFolderPage> createState() => _ConnectDriveFolderPageState();
}

class _ConnectDriveFolderPageState extends State<ConnectDriveFolderPage> {
  final WebviewController _controller = WebviewController();
  StreamSubscription<dynamic>? _webMessageSub;
  StreamSubscription<String>? _urlSub;
  _ConnectMode _mode = _ConnectMode.chooser;
  bool _isWebviewReady = false;
  bool _exchangingCode = false;
  String? _errorMessage;
  String? _lastHandledRedirect;

  final TextEditingController _linkController = TextEditingController();
  bool _connectingByLink = false;
  String? _linkError;

  void _startOAuthFlow() {
    setState(() {
      _mode = _ConnectMode.oauth;
      _errorMessage = null;
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (!Platform.isWindows) {
      setState(
        () => _errorMessage = 'Connecting a Drive folder needs Windows.',
      );
      return;
    }

    try {
      await _controller.initialize();
      await _controller.setBackgroundColor(Colors.transparent);
      await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
      _webMessageSub = _controller.webMessage.listen((message) {
        if (message is String && message.isNotEmpty) {
          _handleFolderPicked(message);
        }
      });
      _urlSub = _controller.url.listen(_handleUrlChanged);
      await _controller.loadUrl(
        GoogleDriveAuthService.buildAuthorizationUrl().toString(),
      );

      if (!mounted) return;
      setState(() => _isWebviewReady = true);
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _errorMessage = "Couldn't connect to Google Drive: $error",
      );
    }
  }

  void _handleUrlChanged(String url) {
    if (!url.startsWith(GoogleDriveAuthService.redirectUri)) return;
    if (_lastHandledRedirect == url) return;
    _lastHandledRedirect = url;

    final uri = Uri.parse(url);
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      final error = uri.queryParameters['error'];
      setState(
        () => _errorMessage =
            'Google sign-in was cancelled${error != null ? ': $error' : '.'}',
      );
      return;
    }
    unawaited(_handleAuthCode(code));
  }

  Future<void> _handleAuthCode(String code) async {
    setState(() => _exchangingCode = true);
    final ok = await GoogleDriveAuthService.exchangeCodeForTokens(code);
    final token = GoogleDriveAuthService.accessToken;
    if (!mounted) return;
    if (!ok || token == null || token.isEmpty) {
      setState(() {
        _errorMessage = "Couldn't complete Google sign-in.";
        _exchangingCode = false;
      });
      return;
    }

    setState(() => _exchangingCode = false);
    await _controller.loadUrl(
      '$_pickerUrl#token=${Uri.encodeComponent(token)}',
    );
  }

  Future<void> _handleFolderPicked(String folderId) async {
    await DriveFolderService.setFolderId(folderId);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _connectByLink() async {
    final folderId = DriveFolderService.extractFolderId(_linkController.text);
    if (folderId == null) {
      setState(
        () => _linkError = "That doesn't look like a Drive folder link.",
      );
      return;
    }

    setState(() {
      _connectingByLink = true;
      _linkError = null;
    });

    final accessible = await GoogleDriveService.canAccessFolder(folderId);
    if (!mounted) return;
    if (!accessible) {
      setState(() {
        _connectingByLink = false;
        _linkError =
            'Couldn\'t access that folder. Make sure it\'s shared as '
            '"Anyone with the link".';
      });
      return;
    }

    await DriveFolderService.setFolderId(folderId);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _webMessageSub?.cancel();
    _urlSub?.cancel();
    _controller.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Widget _buildChooser() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_shared_rounded,
              size: 48,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Connect a Google Drive folder',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pick a folder from your Drive, or paste a share link if '
              "you've already connected one on another device.",
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 280,
              child: FilledButton.icon(
                onPressed: _startOAuthFlow,
                icon: const Icon(Icons.add_to_drive_rounded),
                label: const Text('Choose a folder'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 280,
              child: OutlinedButton.icon(
                onPressed: () =>
                    setState(() => _mode = _ConnectMode.pastedLink),
                icon: const Icon(Icons.link_rounded),
                label: const Text('I already have a share link'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPastedLink() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Paste the share link for a folder you've already "
                'connected to PhamiJam, or its folder ID.',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _linkController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Drive folder link',
                  border: const OutlineInputBorder(),
                  errorText: _linkError,
                ),
                onSubmitted: (_) {
                  if (!_connectingByLink) _connectByLink();
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _connectingByLink ? null : _connectByLink,
                child: _connectingByLink
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Connect'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _connectingByLink
                    ? null
                    : () => setState(() {
                        _mode = _ConnectMode.chooser;
                        _linkError = null;
                      }),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOAuthFlow() {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        if (_errorMessage != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colorScheme.error),
              ),
            ),
          )
        else if (!_isWebviewReady)
          const Center(child: CircularProgressIndicator())
        else
          Webview(_controller),
        if (_exchangingCode) const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(40),
      child: SizedBox(
        width: 640,
        height: 640,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Connect Google Drive folder',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: Icon(
                      Icons.close_rounded,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: switch (_mode) {
                  _ConnectMode.chooser => _buildChooser(),
                  _ConnectMode.pastedLink => _buildPastedLink(),
                  _ConnectMode.oauth => _buildOAuthFlow(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
