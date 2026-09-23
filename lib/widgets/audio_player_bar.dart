import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../services/audio_service.dart';

/// 音频播放条(v2.2 听力)。
///
/// 放在阅读器顶部:听力材料(播客/TED)边听边看稿,是"听"这一环的最小闭环。
/// 交互取舍:
/// - **±15 秒** 而不是进度条拖拽(手机上找位置太费劲,听力最常做的是"没听清,退回去");
/// - **倍速循环**切换(0.75 → 1 → 1.25 → 1.5),听不清就降速;
/// - 载入失败给**可读中文原因 + 重试**(音频源被墙/下架都会遇到)。
class AudioPlayerBar extends StatefulWidget {
  final String url;

  /// 标题(如节目名),用于显示
  final String? title;

  const AudioPlayerBar({super.key, required this.url, this.title});

  @override
  State<AudioPlayerBar> createState() => _AudioPlayerBarState();
}

class _AudioPlayerBarState extends State<AudioPlayerBar> {
  final _audio = AudioService.instance;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;

  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  bool _loading = false;
  String? _error;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    _bind();
    _load();
  }

  void _bind() {
    _posSub = _audio.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durSub = _audio.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _stateSub = _audio.stateStream.listen((s) {
      if (!mounted) return;
      setState(() {
        _playing = s.playing;
        // processingState 到 completed 时把按钮复位,否则会出现"显示在播但没声音"
        if (s.processingState == ProcessingState.completed) {
          _playing = false;
        }
      });
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    // 离开阅读器就停:听力材料不该在后台偷偷占用流量
    _audio.pause();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _audio.load(widget.url);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _toggle() async {
    if (_error != null) {
      await _load();
      return;
    }
    try {
      if (_playing) {
        await _audio.pause();
      } else {
        await _audio.play();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final total = _duration ?? Duration.zero;
    final progress = total.inMilliseconds <= 0
        ? 0.0
        : (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Row(
                children: [
                  const Icon(Icons.error_outline, size: 18, color: Colors.red),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(_error!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.red)),
                  ),
                  TextButton(onPressed: _load, child: const Text('重试')),
                ],
              )
            else ...[
              if (widget.title != null && widget.title!.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: muted, fontWeight: FontWeight.w600),
                  ),
                ),
              Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(AudioService.formatDuration(_position),
                        style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: _loading ? null : progress,
                      minHeight: 4,
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      AudioService.formatDuration(_duration),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: '后退 15 秒',
                    onPressed: _loading
                        ? null
                        : () => _audio.skip(seconds: -15),
                    icon: const Icon(Icons.replay),
                  ),
                  IconButton.filled(
                    tooltip: _playing ? '暂停' : '播放',
                    onPressed: _loading ? null : _toggle,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_playing ? Icons.pause : Icons.play_arrow),
                  ),
                  IconButton(
                    tooltip: '前进 15 秒',
                    onPressed: _loading
                        ? null
                        : () => _audio.skip(seconds: 15),
                    icon: const Icon(Icons.fast_forward),
                  ),
                  const SizedBox(width: 8),
                  // 倍速:听力最常用的两个动作之一(另一个是回退 15 秒)
                  ActionChip(
                    avatar: const Icon(Icons.speed, size: 16),
                    label: Text('${_speed}x',
                        style: const TextStyle(fontSize: 12)),
                    onPressed: _loading
                        ? null
                        : () async {
                            final next = AudioService.nextSpeed(_speed);
                            await _audio.setSpeed(next);
                            if (mounted) setState(() => _speed = next);
                          },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
