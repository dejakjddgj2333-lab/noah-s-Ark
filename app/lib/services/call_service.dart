import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'auth.dart';
import 'chat_ws.dart';

/// 通话阶段.
enum CallPhase { idle, outgoing, incoming, connected, ended }

/// 当前通话快照 (UI 用 ValueNotifier 监听).
class CallState {
  const CallState({
    required this.callId,
    required this.peerId,
    required this.peerName,
    required this.phase,
    this.muted = false,
    this.speakerOn = true,
    this.startedAt,
    this.endReason,
  });

  final String callId;
  final int peerId;
  final String peerName;
  final CallPhase phase;
  final bool muted;
  final bool speakerOn;
  final DateTime? startedAt; // 接通时间 (计时起点)
  final String? endReason; // 结束原因提示

  CallState copyWith({
    CallPhase? phase,
    bool? muted,
    bool? speakerOn,
    DateTime? startedAt,
    String? endReason,
  }) =>
      CallState(
        callId: callId,
        peerId: peerId,
        peerName: peerName,
        phase: phase ?? this.phase,
        muted: muted ?? this.muted,
        speakerOn: speakerOn ?? this.speakerOn,
        startedAt: startedAt ?? this.startedAt,
        endReason: endReason ?? this.endReason,
      );
}

/// 1:1 WebRTC 语音通话服务 (单例).
/// 信令走现有聊天 WS (ChatWs.send). 主叫永远发 offer, 被叫应答 (perfect-negotiation-lite).
/// 仅音频: getUserMedia audio-only + echoCancellation/noiseSuppression, 无视频.
class CallService {
  CallService._() {
    // 订阅信令: 按 call_id 过滤, 处理 accept/signal/end/reject/unavailable/error.
    _wsSub = ChatWs.instance.events.listen(_onWsEvent);
  }
  static final CallService instance = CallService._();

  /// 当前通话 (null = 空闲). UI 用 ListenableBuilder 监听.
  final ValueNotifier<CallState?> activeCall = ValueNotifier<CallState?>(null);

  /// 通话阶段变化回调 (main.dart 用来 push/pop CallPage).
  final ValueNotifier<CallPhase> phase = ValueNotifier<CallPhase>(CallPhase.idle);

  /// 一次性提示 (toast). UI 监听后显示并清空.
  final ValueNotifier<String?> notice = ValueNotifier<String?>(null);

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription<Map<String, dynamic>>? _wsSub;
  bool _wsSubscribed = true;

  static const _uuid = Uuid();

  /// 拉取 TURN 配置并合并到 STUN. 失败/未配置时回退仅 STUN.
  Future<Map<String, dynamic>> _buildIceServers() async {
    final servers = <dynamic>[
      {'urls': 'stun:stun.l.google.com:19302'},
    ];
    try {
      final resp = await McApi.get('/api/chat/turn-servers',
          token: AuthStore.instance.token);
      final list = resp['servers'];
      if (list is List) {
        for (final s in list) {
          if (s is Map && s['urls'] != null) {
            servers.add({
              'urls': s['urls'],
              if (s['username'] != null) 'username': s['username'],
              if (s['credential'] != null) 'credential': s['credential'],
            });
          }
        }
      }
    } catch (_) {/* TURN 拉取失败静默回退 STUN */}
    return {'iceServers': servers};
  }

  static const _mediaConstraints = <String, dynamic>{
    'audio': {
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
    },
    'video': false,
  };

  bool get _inCall => activeCall.value != null;

  void _setPhase(CallPhase p) => phase.value = p;

  void _toast(String msg) => notice.value = msg;

  /// WS 是否可用 (断线时不可发起).
  bool get canCall => ChatWs.instance.isConnected;

  // ---------- 主叫 ----------

  /// 发起呼叫. 返回是否成功进入 ringing (失败已 toast).
  Future<bool> startCall(int peerUserId, String peerName,
      {int? conversationId}) async {
    if (_inCall) {
      _toast('正在通话中');
      return false;
    }
    if (!ChatWs.instance.isConnected) {
      _toast('连接已断开, 请稍后重试');
      return false;
    }
    final callId = _uuid.v4();
    activeCall.value = CallState(
      callId: callId,
      peerId: peerUserId,
      peerName: peerName,
      phase: CallPhase.outgoing,
    );
    _setPhase(CallPhase.outgoing);

    final ok = await _setupPeerConnection(isCaller: true);
    if (!ok) {
      _teardown();
      _toast('无法访问麦克风');
      return false;
    }

    // 先邀请 (带 conversation_id 可选), 再发 SDP offer.
    ChatWs.instance.send({
      'type': 'call_invite',
      'call_id': callId,
      'to_user_id': peerUserId,
      'conversation_id': ?conversationId,
    });

    try {
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);
      _sendSignal(peerUserId, {
        'type': 'sdp',
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
      });
    } catch (_) {
      _teardown();
      _toast('呼叫失败');
      return false;
    }
    return true;
  }

  // ---------- 被叫 ----------

  /// 收到来电邀请 (main.dart 转发). 已在通话则自动拒绝.
  void ringIncoming(String callId, int fromUserId, String fromName) {
    if (_inCall) {
      // 占线: 静默拒绝第二通来电.
      ChatWs.instance.send({
        'type': 'call_reject',
        'call_id': callId,
        'to_user_id': fromUserId,
      });
      return;
    }
    activeCall.value = CallState(
      callId: callId,
      peerId: fromUserId,
      peerName: fromName,
      phase: CallPhase.incoming,
    );
    _setPhase(CallPhase.incoming);
  }

  /// 接听.
  Future<void> accept() async {
    final call = activeCall.value;
    if (call == null || call.phase != CallPhase.incoming) return;
    ChatWs.instance.send({
      'type': 'call_accept',
      'call_id': call.callId,
      'to_user_id': call.peerId,
    });
    final ok = await _setupPeerConnection(isCaller: false);
    if (!ok) {
      _sendControl('call_end');
      _teardown();
      _toast('无法访问麦克风');
    }
    // 远端 offer 会在 call_signal 中到达, 在 _onRemoteSdp 里应答.
  }

  /// 拒接 (被叫) / 取消 (主叫 ringing).
  void reject() {
    final call = activeCall.value;
    if (call == null) return;
    ChatWs.instance.send({
      'type': 'call_reject',
      'call_id': call.callId,
      'to_user_id': call.peerId,
    });
    _teardown();
  }

  /// 挂断 (通话中或任一阶段通用).
  void hangup() {
    final call = activeCall.value;
    if (call == null) return;
    _sendControl('call_end');
    _teardown();
  }

  // ---------- 通话中控制 ----------

  Future<void> toggleMute() async {
    final call = activeCall.value;
    if (call == null) return;
    final muted = !call.muted;
    final tracks = _localStream?.getAudioTracks() ?? [];
    for (final t in tracks) {
      t.enabled = !muted;
    }
    activeCall.value = call.copyWith(muted: muted);
  }

  Future<void> toggleSpeaker() async {
    final call = activeCall.value;
    if (call == null) return;
    final on = !call.speakerOn;
    try {
      await Helper.setSpeakerphoneOn(on);
    } catch (_) {/* web/桌面无扬声器切换, 静默 */}
    activeCall.value = call.copyWith(speakerOn: on);
  }

  // ---------- 信令处理 ----------

  void _sendControl(String type) {
    final call = activeCall.value;
    if (call == null) return;
    ChatWs.instance.send({
      'type': type,
      'call_id': call.callId,
      'to_user_id': call.peerId,
    });
  }

  void _sendSignal(int toUserId, Map<String, dynamic> data) {
    final call = activeCall.value;
    if (call == null) return;
    ChatWs.instance.send({
      'type': 'call_signal',
      'call_id': call.callId,
      'to_user_id': toUserId,
      'data': data,
    });
  }

  void _onWsEvent(Map<String, dynamic> e) {
    final call = activeCall.value;
    if (call == null) return;
    final type = e['type'];
    // 只关心本通话的信令 (invite 由 main.dart 转发, 这里不处理).
    if (e['call_id'] != call.callId) return;

    switch (type) {
      case 'call_accept':
        _onAccepted();
      case 'call_signal':
        final data = e['data'];
        if (data is Map) _onSignal(Map<String, dynamic>.from(data));
      case 'call_reject':
        _endByRemote('对方已拒绝');
      case 'call_end':
        _endByRemote('通话已结束');
      case 'call_unavailable':
        _endByRemote('对方不在线');
      case 'call_error':
        _endByRemote((e['reason'] ?? '呼叫失败').toString());
    }
  }

  Future<void> _onAccepted() async {
    final call = activeCall.value;
    if (call == null || call.phase != CallPhase.outgoing) return;
    final now = DateTime.now();
    activeCall.value = call.copyWith(phase: CallPhase.connected, startedAt: now);
    _setPhase(CallPhase.connected);
  }

  Future<void> _onSignal(Map<String, dynamic> data) async {
    final pc = _pc;
    if (pc == null) return;
    final kind = data['type'];
    try {
      if (kind == 'sdp') {
        final sdp = data['sdp'];
        if (sdp is! Map) return;
        await _onRemoteSdp(pc, sdp['type']?.toString(), sdp['sdp']?.toString());
      } else if (kind == 'candidate') {
        final cand = data['candidate'];
        if (cand is! Map) return;
        await pc.addCandidate(RTCIceCandidate(
          cand['candidate']?.toString(),
          cand['sdpMid']?.toString(),
          _asInt(cand['sdpMLineIndex']),
        ));
      }
    } catch (_) {/* 单条信令失败不影响通话 */}
  }

  Future<void> _onRemoteSdp(
      RTCPeerConnection pc, String? type, String? sdp) async {
    if (type == null || sdp == null) return;
    final desc = RTCSessionDescription(sdp, type);
    if (type == 'offer') {
      // 我是被叫: 收到 offer → set remote → 应答.
      await pc.setRemoteDescription(desc);
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      final call = activeCall.value;
      if (call != null) {
        _sendSignal(call.peerId, {
          'type': 'sdp',
          'sdp': {'type': answer.type, 'sdp': answer.sdp},
        });
        final now = DateTime.now();
        activeCall.value =
            call.copyWith(phase: CallPhase.connected, startedAt: now);
        _setPhase(CallPhase.connected);
      }
    } else if (type == 'answer') {
      // 我是主叫: 收到 answer.
      await pc.setRemoteDescription(desc);
    }
  }

  void _endByRemote(String reason) {
    final call = activeCall.value;
    if (call == null) return;
    activeCall.value = call.copyWith(phase: CallPhase.ended, endReason: reason);
    _setPhase(CallPhase.ended);
    _cleanupRtc();
  }

  // ---------- RTC 生命周期 ----------

  Future<bool> _setupPeerConnection({required bool isCaller}) async {
    try {
      _localStream = await navigator.mediaDevices
          .getUserMedia(_mediaConstraints);
      final iceServers = await _buildIceServers();
      _pc = await createPeerConnection(iceServers);

      // 本地音轨全部加入.
      for (final track in _localStream!.getAudioTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }

      // Trickle ICE: 每个候选即时发出.
      _pc!.onIceCandidate = (RTCIceCandidate c) {
        final call = activeCall.value;
        if (call == null || c.candidate == null) return;
        _sendSignal(call.peerId, {
          'type': 'candidate',
          'candidate': {
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          },
        });
      };

      // 远端音频: flutter_webrtc 自动播放, 无需渲染器.
      _pc!.onTrack = (RTCTrackEvent event) {
        // 音频轨道自动输出到扬声器/听筒 (由 setSpeakerphoneOn 控制).
      };

      _pc!.onConnectionState = (RTCPeerConnectionState s) {
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
            s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          // 连接中断: 仅在通话中才判结束 (ringing 阶段可能是瞬态).
          if (activeCall.value?.phase == CallPhase.connected &&
              s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
            _endByRemote('连接已断开');
          }
        }
      };

      return true;
    } catch (_) {
      return false;
    }
  }

  void _cleanupRtc() {
    final pc = _pc;
    _pc = null;
    pc?.close();
    final stream = _localStream;
    _localStream = null;
    if (stream != null) {
      for (final t in stream.getTracks()) {
        t.stop();
      }
      stream.dispose();
    }
  }

  /// 本地结束 (hangup/reject 后): 直接清空回 idle.
  void _teardown() {
    _cleanupRtc();
    activeCall.value = null;
    _setPhase(CallPhase.idle);
  }

  /// 应用退出/登出清理.
  void dispose() {
    if (_wsSubscribed) {
      _wsSub?.cancel();
      _wsSubscribed = false;
    }
    _teardown();
  }
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? 0;
}
