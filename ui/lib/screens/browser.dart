import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

// Reuse theme colors from main.dart (duplicated here for standalone usage if needed, 
// but ideally should be in a shared theme file. For now we use hardcoded or pass them).
const kCyberBlack = Color(0xFF0B1220);
const kCyberDark = Color(0xFF121A2B);
const kCyberPanel = Color(0xFF1A2336);
const kNeonCyan = Color(0xFF14B8A6);
const kNeonPink = Color(0xFFF25F5C);
const kNeonYellow = Color(0xFFF6C453);
const kNeonBlue = Color(0xFF6BA6FF);
const kMutedText = Color(0xFF9AA7BD);

class CyberBrowser extends StatefulWidget {
  final Function(String url) onDownloadRequest;

  const CyberBrowser({super.key, required this.onDownloadRequest});

  @override
  State<CyberBrowser> createState() => _CyberBrowserState();
}

class _CyberBrowserState extends State<CyberBrowser> {
  late final WebViewController _controller;
  final TextEditingController _urlController = TextEditingController();
  double _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(kCyberBlack)
      ..addJavaScriptChannel(
        'IDMDownload',
        onMessageReceived: (message) {
          final url = message.message.trim();
          if (url.isEmpty) return;
          final parsed = Uri.tryParse(url);
          if (parsed == null) return;
          final scheme = parsed.scheme.toLowerCase();
          if (scheme != 'http' && scheme != 'https' && scheme != 'magnet') {
            return;
          }
          widget.onDownloadRequest(url);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            setState(() {
              _progress = progress / 100;
            });
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _urlController.text = url;
            });
            _checkNavigation();
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
              _progress = 0;
            });
            _checkNavigation();
            _injectDownloadSniffer();
            _maybePromptDirectDownload(url);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('Web Resource Error: ${error.description}');
          },
          onNavigationRequest: (NavigationRequest request) {
            if (_isDownloadable(request.url)) {
              widget.onDownloadRequest(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse('https://www.google.com'));
  }

  void _checkNavigation() async {
    final back = await _controller.canGoBack();
    final fwd = await _controller.canGoForward();
    if (mounted) {
      setState(() {
        _canGoBack = back;
        _canGoForward = fwd;
      });
    }
  }

  bool _isDownloadable(String url) {
    final lower = url.toLowerCase();
    // Basic extension check - can be expanded
    const exts = [
      '.mp4', '.mkv', '.webm', '.avi', '.mov', // Video
      '.mp3', '.wav', '.flac', '.m4a', // Audio
      '.zip', '.rar', '.7z', '.tar', '.gz', // Archive
      '.apk', '.exe', '.msi', '.dmg', '.iso', // App/Disk
      '.pdf', '.doc', '.docx', '.xls', // Doc
      '.torrent', '.magnet', // Torrent
      '.m3u8' // HLS
    ];
    
    // Check if it ends with extension (ignoring query params for simple check)
    final uri = Uri.parse(url);
    final path = uri.path.toLowerCase();
    
    for (final ext in exts) {
      if (path.endsWith(ext)) return true;
    }
    return false;
  }

  void _maybePromptDirectDownload(String url) {
    if (_isDownloadable(url)) {
      widget.onDownloadRequest(url);
    }
  }

  void _injectDownloadSniffer() {
    const js = r'''
(function() {
  if (window.__idmDownloadHooked) return;
  window.__idmDownloadHooked = true;

  function isDownloadable(url) {
    var lower = (url || '').toLowerCase();
    var exts = [
      '.mp4', '.mkv', '.webm', '.avi', '.mov',
      '.mp3', '.wav', '.flac', '.m4a',
      '.zip', '.rar', '.7z', '.tar', '.gz',
      '.apk', '.exe', '.msi', '.dmg', '.iso',
      '.pdf', '.doc', '.docx', '.xls',
      '.torrent', '.magnet',
      '.m3u8'
    ];
    for (var i = 0; i < exts.length; i++) {
      if (lower.endsWith(exts[i])) return true;
    }
    return false;
  }

  document.addEventListener('click', function(e) {
    var el = e.target;
    while (el && el.tagName !== 'A') {
      el = el.parentElement;
    }
    if (!el) return;
    var href = el.getAttribute('href');
    if (!href) return;
    var absolute = null;
    try {
      absolute = new URL(href, window.location.href).toString();
    } catch (err) {
      return;
    }
    var hasDownloadAttr = el.hasAttribute('download');
    if (hasDownloadAttr || isDownloadable(absolute)) {
      if (window.IDMDownload && window.IDMDownload.postMessage) {
        window.IDMDownload.postMessage(absolute);
        e.preventDefault();
        e.stopPropagation();
      }
    }
  }, true);
})();
''';
    _controller.runJavaScript(js);
  }

  void _loadUrl(String url) {
    if (!url.startsWith('http')) {
      if (url.contains('.')) {
        url = 'https://$url';
      } else {
        url = 'https://www.google.com/search?q=$url';
      }
    }
    _controller.loadRequest(Uri.parse(url));
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildAddressBar(),
        if (_isLoading)
          LinearProgressIndicator(
            value: _progress,
            backgroundColor: kCyberBlack,
            color: kNeonCyan,
            minHeight: 2,
          ),
        Expanded(
          child: WebViewWidget(controller: _controller),
        ),
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildAddressBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: kCyberDark,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.home, color: kNeonCyan),
            onPressed: () => _loadUrl('https://www.google.com'),
          ),
          Expanded(
            child: TextField(
              controller: _urlController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search or enter URL',
                hintStyle: TextStyle(color: kMutedText),
                filled: true,
                fillColor: kCyberPanel,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.search, color: kMutedText, size: 20),
              ),
              onSubmitted: _loadUrl,
            ),
          ),
          IconButton(
            icon: Icon(_isLoading ? Icons.close : Icons.refresh, color: kNeonCyan),
            onPressed: () {
              if (_isLoading) {
                _controller.runJavaScript('window.stop();');
              } else {
                _controller.reload();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      color: kCyberDark,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back_ios, size: 20, color: _canGoBack ? kNeonBlue : kMutedText),
            onPressed: _canGoBack ? () => _controller.goBack() : null,
          ),
          IconButton(
            icon: Icon(Icons.arrow_forward_ios, size: 20, color: _canGoForward ? kNeonBlue : kMutedText),
            onPressed: _canGoForward ? () => _controller.goForward() : null,
          ),
          IconButton(
            icon: const Icon(Icons.add, color: kNeonCyan),
            onPressed: () => _buildMenu(context),
          ),
           IconButton(
            icon: const Icon(Icons.history, color: kMutedText),
            onPressed: () {}, // TODO: Implement History
          ),
        ],
      ),
    );
  }
  
  void _buildMenu(BuildContext context) {
    // Placeholder for menu
  }
}
