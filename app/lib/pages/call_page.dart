import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/call_service.dart';

/// 1:1 语音通话全屏页 (深色). 主叫/被叫/通话中/已结束四态.
/// 数据全部来自 CallService.activeCall; 结束后 ~1.5s 自动退出.
class CallPage extends StatefulWidget {
  const CallPage({super.key});

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage> {
  Timer? _timer; // 通话计时
  Timer? _autoPop; // 结束自动退出
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    // 监听阶段变化: 接通开始计时, 结束启动自动退出.
    CallService.instance.activeCall.addListener(_onCallChange);
    _onCallChange();
  }

  void _onCallChange() {
    final call = CallService.instance.activeCall.value;
    if (!mounted) return;
    final phase = call?.phase ?? CallPhase.ended;

    if (phase == CallPhase.connected) {
      _seconds = call?.startedAt == null
          ? 0
          : DateTime.now().difference(call!.startedAt!).inSeconds;
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _seconds++);
      });
    }

    if (phase == CallPhase.ended || call == null) {
      _timer?.cancel();
      _timer = null;
      _autoPop ??= Timer(const Duration(milliseconds: 1500), () {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      setState(() {});
    }
  }

  @override
  void dispose() {
    CallService.instance.activeCall.removeListener(_onCallChange);
    _timer?.cancel();
    _autoPop?.cancel();
    super.dispose();
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  String _statusText(CallState? call) {
    switch (call?.phase) {
      case CallPhase.outgoing:
        return tr('call_ringing');
      case CallPhase.incoming:
        return tr('call_invite');
      case CallPhase.connected:
        return '${tr('call_in_call')} ${_two(_seconds ~/ 60)}:${_two(_seconds % 60)}';
      case CallPhase.ended:
        return call?.endReason ?? tr('call_ended');
      default:
        return tr('call_calling');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CallState?>(
      valueListenable: CallService.instance.activeCall,
      builder: (context, call, _) {
        final phase = call?.phase ?? CallPhase.ended;
        final isIncomingRinging = phase == CallPhase.incoming;
        final name = call?.peerName ?? tr('call_peer');
        return Scaffold(
          backgroundColor: McColors.surfaceContainerLowest,
          body: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                _avatar(name),
                const SizedBox(height: 24),
                Text(
                  name,
                  style: McText.display(size: 24, weight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Text(
                  _statusText(call),
                  style: McText.sans(
                    size: 14,
                    color: phase == CallPhase.connected
                        ? McColors.bull
                        : McColors.onSurfaceVariant,
                  ),
                ),
                const Spacer(flex: 3),
                _controls(call, isIncomingRinging),
                const SizedBox(height: 48),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _avatar(String name) {
    final letter = name.isEmpty ? '?' : name[0].toUpperCase();
    return Container(
      width: 108,
      height: 108,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: McColors.surfaceContainerHigh,
        border: Border.all(
          color: McColors.primaryContainer.withValues(alpha: 0.5),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: McColors.primaryContainer.withValues(alpha: 0.35),
            blurRadius: 32,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: McText.display(
          size: 44,
          weight: FontWeight.w700,
          color: McColors.primary,
        ),
      ),
    );
  }

  Widget _controls(CallState? call, bool isIncomingRinging) {
    if (isIncomingRinging) {
      // 被叫: 拒绝(红) + 接听(绿).
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _circleBtn(
            icon: Icons.call_end,
            color: McColors.bear,
            label: tr('call_reject'),
            onTap: () {
              CallService.instance.reject();
              _popSelf();
            },
          ),
          _circleBtn(
            icon: Icons.call,
            color: McColors.bull,
            label: tr('call_accept'),
            onTap: () => CallService.instance.accept(),
          ),
        ],
      );
    }
    // 主叫/通话中: 静音 + 免提 + 挂断.
    final muted = call?.muted ?? false;
    final speakerOn = call?.speakerOn ?? true;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _smallBtn(
          icon: muted ? Icons.mic_off : Icons.mic,
          label: muted ? tr('call_muted') : tr('call_mute'),
          active: muted,
          onTap: () => CallService.instance.toggleMute(),
        ),
        _circleBtn(
          icon: Icons.call_end,
          color: McColors.bear,
          label: tr('call_hangup'),
          onTap: () {
            CallService.instance.hangup();
            _popSelf();
          },
        ),
        // web 无扬声器切换, 隐藏免提钮.
        if (!kIsWeb)
          _smallBtn(
            icon: speakerOn ? Icons.volume_up : Icons.volume_down,
            label: speakerOn ? tr('call_speaker') : tr('call_earpiece'),
            active: speakerOn,
            onTap: () => CallService.instance.toggleSpeaker(),
          ),
      ],
    );
  }

  void _popSelf() {
    // 本地操作立即退出页面; 服务已异步 teardown.
    _autoPop?.cancel();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Widget _circleBtn({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 20),
              ],
            ),
            child: Icon(icon, size: 30, color: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
      ],
    );
  }

  Widget _smallBtn({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? McColors.surfaceContainerHighest
                  : McColors.surfaceContainer,
              border: Border.all(color: McColors.outlineVariant),
            ),
            child: Icon(icon, size: 24, color: McColors.onSurface),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: McText.sans(size: 12, color: McColors.onSurfaceVariant)),
      ],
    );
  }
}
