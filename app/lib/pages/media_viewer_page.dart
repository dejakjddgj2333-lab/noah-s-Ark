import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/theme.dart';

/// 全屏图片查看: 黑底 + 可缩放, 点击退出.
class ImageViewerPage extends StatelessWidget {
  const ImageViewerPage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          color: Colors.black,
          child: Center(
            child: InteractiveViewer(
              maxScale: 5,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(Icons.broken_image,
                    size: 48, color: McColors.onSurfaceVariant),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: McColors.primarySoft),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 全屏视频播放: 黑底自动播放, 点击切换播放/暂停, 右上角关闭.
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.url});

  final String url;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _controller.play();
      }).catchError((_) {
        if (!mounted) return;
        setState(() => _failed = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!_ready) return;
    setState(() {
      _controller.value.isPlaying ? _controller.pause() : _controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: _failed
                ? const Icon(Icons.videocam_off,
                    size: 48, color: McColors.onSurfaceVariant)
                : !_ready
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: McColors.primarySoft),
                      )
                    : GestureDetector(
                        onTap: _toggle,
                        child: AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        ),
                      ),
          ),
          // 暂停时中央大播放键提示.
          if (_ready && !_controller.value.isPlaying)
            Center(
              child: GestureDetector(
                onTap: _toggle,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow,
                      size: 48, color: Colors.white),
                ),
              ),
            ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 26),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
