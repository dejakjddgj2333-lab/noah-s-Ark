import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/kit.dart';

/// AI K线分析弹窗 (对齐 web MarketDetail 弹窗):
/// 趋势/形态/关键位/量能/信号 五段, 后端按周期缓存。
/// 用法: showAiKlineReport(context, 'BTC-USDT', '1H')
Future<void> showAiKlineReport(BuildContext context, String instId, String bar) {
  return showDialog(
    context: context,
    builder: (_) => _AiKlineDialog(instId: instId, bar: bar),
  );
}

class _AiKlineDialog extends StatefulWidget {
  const _AiKlineDialog({required this.instId, required this.bar});
  final String instId;
  final String bar;

  @override
  State<_AiKlineDialog> createState() => _AiKlineDialogState();
}

class _AiKlineDialogState extends State<_AiKlineDialog> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _report;
  bool _cached = false;

  static const _dirs = {
    'bullish': ('看多', Mc.bull),
    'bearish': ('看空', Mc.bear),
    'neutral': ('震荡', Mc.amber),
  };
  static const _actions = {
    'buy': ('做多 BUY', Mc.bull),
    'sell': ('做空 SELL', Mc.bear),
    'hold': ('观望 HOLD', Mc.amber),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _report = null;
    });
    try {
      final res = await ApiClient.I
          .aiKlineAnalysis(widget.instId, bar: widget.bar);
      if (res is Map && res['ok'] == true) {
        _report = Map<String, dynamic>.from(res['report'] as Map);
        _cached = res['cached'] == true;
      } else {
        _error = res is Map && res['error'] == 'insufficient_data'
            ? 'K线数据不足, 换个周期试试'
            : 'AI 暂时不可用, 稍后再试';
      }
    } catch (e) {
      _error = e is ApiException ? e.message : 'AI 请求失败';
    }
    if (mounted) setState(() => _loading = false);
  }

  String get _coin => widget.instId.split('-').first;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 520,
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: BoxDecoration(
          color: Mc.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Mc.hairline),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // 头部
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: Mc.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Mc.hairline)),
            ),
            child: Row(children: [
              const Icon(Icons.smart_toy_outlined,
                  size: 16, color: Mc.cobaltSoft),
              const SizedBox(width: 8),
              Text('$_coin/USDT AI 技术分析', style: Mc.display(13)),
              const SizedBox(width: 8),
              Text(widget.bar, style: Mc.mono(10, color: Mc.muted)),
              const Spacer(),
              if (_cached && _report != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: McBadge('周期内缓存', color: Mc.muted),
                ),
              InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: Mc.muted),
                ),
              ),
            ]),
          ),
          // 内容
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _loading
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                          child: Text('AI 分析中, 约 10~20 秒…',
                              style: Mc.mono(12, color: Mc.muted))))
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Column(children: [
                            Text(_error!,
                                style: Mc.body(13, color: Mc.bear)),
                            const SizedBox(height: 12),
                            McButton('重试',
                                kind: McBtnKind.ghost,
                                height: 32,
                                onPressed: _load),
                          ]),
                        )
                      : _reportBody(),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _reportBody() {
    final r = _report!;
    final trend = r['trend'] is Map ? r['trend'] as Map : null;
    final patterns = r['patterns'] is List ? r['patterns'] as List : null;
    final levels = r['key_levels'] is Map ? r['key_levels'] as Map : null;
    final volume = r['volume'] is Map ? r['volume'] as Map : null;
    final signal = r['signal'] is Map ? r['signal'] as Map : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (trend != null) _trendCard(trend),
      if (patterns != null && patterns.isNotEmpty) _patternsCard(patterns),
      if (levels != null) _levelsCard(levels),
      if (volume != null) _volumeCard(volume),
      if (signal != null) _signalCard(signal),
      const SizedBox(height: 4),
      Center(
        child: Text('AI 技术分析仅供参考, 不构成投资建议',
            style: Mc.mono(11, color: Mc.muted.withValues(alpha: 0.6))),
      ),
    ]);
  }

  Widget _card(String tag, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Mc.canvas,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Mc.hairline),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        McTag(tag),
        const SizedBox(height: 8),
        ...children,
      ]),
    );
  }

  Widget _trendCard(Map trend) {
    final dir = _dirs[trend['direction']] ?? _dirs['neutral']!;
    final conf = Fmt.toNum(trend['confidence']);
    return _card('趋势 TREND', [
      Row(children: [
        McBadge(dir.$1, color: dir.$2),
        if (conf != null) ...[
          const Spacer(),
          Text('置信度 ${conf.toInt()}%',
              style: Mc.mono(11, color: Mc.muted)),
        ],
      ]),
      if (conf != null) ...[
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: (conf.clamp(0, 100)) / 100,
            minHeight: 4,
            backgroundColor: Mc.surface,
            valueColor: AlwaysStoppedAnimation(dir.$2),
          ),
        ),
      ],
      if (trend['ma_status'] != null) ...[
        const SizedBox(height: 8),
        Text(trend['ma_status'].toString(), style: Mc.body(13)),
      ],
      if (trend['reason'] != null) ...[
        const SizedBox(height: 4),
        Text(trend['reason'].toString(),
            style: Mc.body(13, color: Mc.muted)),
      ],
    ]);
  }

  Widget _patternsCard(List patterns) {
    return _card('形态 PATTERNS', [
      for (final p in patterns)
        if (p is Map)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              McBadge(p['name']?.toString() ?? '', color: Mc.cobaltSoft),
              const SizedBox(width: 8),
              Text(
                '${p['type'] ?? ''} · ${p['validity'] ?? ''}',
                style: Mc.mono(11, color: Mc.muted),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(p['description']?.toString() ?? '',
                    style: Mc.body(12, color: Mc.muted)),
              ),
            ]),
          ),
    ]);
  }

  Widget _levelsCard(Map levels) {
    final supports = levels['supports'] is List ? levels['supports'] as List : [];
    final resistances =
        levels['resistances'] is List ? levels['resistances'] as List : [];
    return _card('关键位 KEY LEVELS', [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('支撑位', style: Mc.body(11, color: Mc.bull)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in supports)
                McBadge(Fmt.num_(s), color: Mc.bull),
            ]),
          ]),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('阻力位', style: Mc.body(11, color: Mc.bear)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final r in resistances)
                McBadge(Fmt.num_(r), color: Mc.bear),
            ]),
          ]),
        ),
      ]),
      if (levels['breakout'] != null) ...[
        const SizedBox(height: 8),
        Text(levels['breakout'].toString(), style: Mc.body(13)),
      ],
      if (levels['description'] != null) ...[
        const SizedBox(height: 4),
        Text(levels['description'].toString(),
            style: Mc.body(13, color: Mc.muted)),
      ],
    ]);
  }

  Widget _volumeCard(Map volume) {
    final divergence = volume['divergence']?.toString();
    return _card('量能 VOLUME', [
      Row(children: [
        if (volume['state'] != null)
          Text(volume['state'].toString(), style: Mc.body(12)),
        if (divergence != null && divergence.isNotEmpty && divergence != '无') ...[
          const SizedBox(width: 8),
          McBadge(divergence, color: Mc.amber),
        ],
      ]),
      if (volume['description'] != null) ...[
        const SizedBox(height: 4),
        Text(volume['description'].toString(),
            style: Mc.body(13, color: Mc.muted)),
      ],
    ]);
  }

  Widget _signalCard(Map signal) {
    final act = _actions[signal['action']] ?? _actions['hold']!;
    final sl = Fmt.toNum(signal['stop_loss']);
    final tp = Fmt.toNum(signal['take_profit']);
    final risks = signal['risks'] is List ? signal['risks'] as List : [];
    return _card('信号 SIGNAL', [
      McBadge(act.$1, color: act.$2),
      if (sl != null || tp != null) ...[
        const SizedBox(height: 8),
        Row(children: [
          if (sl != null)
            Expanded(child: _slTpTile('止损', Fmt.num_(sl), Mc.bear)),
          if (sl != null && tp != null) const SizedBox(width: 8),
          if (tp != null)
            Expanded(child: _slTpTile('止盈', Fmt.num_(tp), Mc.bull)),
        ]),
      ],
      if (signal['summary'] != null) ...[
        const SizedBox(height: 8),
        Text(signal['summary'].toString(),
            style: Mc.body(13, color: Mc.muted)),
      ],
      if (risks.isNotEmpty) ...[
        const SizedBox(height: 6),
        for (final r in risks)
          Text('· ${r.toString()}',
              style: Mc.body(12, color: Mc.muted.withValues(alpha: 0.8))),
      ],
    ]);
  }

  Widget _slTpTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Mc.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        Text(label, style: Mc.mono(11, color: Mc.muted)),
        const Spacer(),
        Text(value, style: Mc.mono(13, w: FontWeight.w600, color: color)),
      ]),
    );
  }
}
