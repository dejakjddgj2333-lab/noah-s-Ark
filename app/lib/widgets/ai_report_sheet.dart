import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/ai_api.dart';
import '../services/api.dart';
import '../services/auth.dart';

/// AI K线分析底部弹层 (对齐 web MarketDetail 弹窗 / desktop ai_report):
/// 趋势/形态/关键位/量能/信号 五段, 后端按周期缓存。
/// 用法: showAiKlineReport(context, 'BTC-USDT', '1H')
Future<void> showAiKlineReport(BuildContext context, String instId, String bar) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AiKlineSheet(instId: instId, bar: bar),
  );
}

class _AiKlineSheet extends StatefulWidget {
  const _AiKlineSheet({required this.instId, required this.bar});
  final String instId;
  final String bar;

  @override
  State<_AiKlineSheet> createState() => _AiKlineSheetState();
}

class _AiKlineSheetState extends State<_AiKlineSheet> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _report;
  bool _cached = false;

  Map<String, (String, Color)> get _dirs => {
        'bullish': (tr('ai_dir_bullish'), McColors.bull),
        'bearish': (tr('ai_dir_bearish'), McColors.bear),
        'neutral': (tr('ai_dir_neutral'), McColors.goldBright),
      };
  Map<String, (String, Color)> get _actions => {
        'buy': (tr('ai_act_buy'), McColors.bull),
        'sell': (tr('ai_act_sell'), McColors.bear),
        'hold': (tr('ai_act_hold'), McColors.goldBright),
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
      final res = await AiApi.klineAnalysis(
          AuthStore.instance.token ?? '', widget.instId,
          bar: widget.bar);
      if (res['ok'] == true && res['report'] is Map) {
        _report = Map<String, dynamic>.from(res['report'] as Map);
        _cached = res['cached'] == true;
      } else {
        _error = res['error'] == 'insufficient_data'
            ? tr('ai_insufficient')
            : tr('ai_unavailable');
      }
    } catch (e) {
      _error = e is ApiException ? e.message : tr('ai_unavailable');
    }
    if (mounted) setState(() => _loading = false);
  }

  String get _coin => widget.instId.split('-').first;

  static String _num(dynamic v) {
    if (v is num) {
      final s = v.toStringAsFixed(6);
      // 去掉多余尾零, 至少 2 位小数
      var t = s.replaceAll(RegExp(r'0+$'), '');
      if (t.endsWith('.')) t += '00';
      final dot = t.indexOf('.');
      if (dot >= 0 && t.length - dot - 1 < 2) t = t.padRight(dot + 3, '0');
      return t;
    }
    return v?.toString() ?? '--';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(
        color: McColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: McColors.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // 头部
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
          child: Row(children: [
            const Icon(Icons.smart_toy_outlined,
                size: 16, color: McColors.primarySoft),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$_coin/USDT ${tr('ai_report_title')} · ${widget.bar}',
                style: McText.sans(
                    size: 14,
                    weight: FontWeight.w700,
                    color: McColors.onSurface),
              ),
            ),
            if (_cached && _report != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _badge(tr('ai_cached_badge'), McColors.onSurfaceVariant),
              ),
            IconButton(
              icon: const Icon(Icons.close,
                  size: 18, color: McColors.onSurfaceVariant),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ]),
        ),
        const Divider(height: 1, color: McColors.outlineVariant),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, 16 + MediaQuery.of(context).padding.bottom),
            child: _loading
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                        child: Text(tr('ai_analyzing'),
                            style: McText.mono(
                                size: 12,
                                color: McColors.onSurfaceVariant))))
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Column(children: [
                          Text(_error!,
                              style: McText.sans(
                                  size: 13, color: McColors.bear)),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _load,
                            child: Text(tr('ai_retry'),
                                style: McText.sans(
                                    size: 13,
                                    weight: FontWeight.w700,
                                    color: McColors.primarySoft)),
                          ),
                        ]),
                      )
                    : _reportBody(),
          ),
        ),
      ]),
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
        child: Text(tr('ai_disclaimer'),
            style: McText.mono(
                size: 10,
                color: McColors.onSurfaceVariant.withValues(alpha: 0.6))),
      ),
    ]);
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(text,
          style: McText.sans(size: 10, weight: FontWeight.w700, color: color)),
    );
  }

  Widget _card(String tag, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: McColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tag,
            style: McText.mono(
                size: 10,
                weight: FontWeight.w700,
                letterSpacing: 1,
                color: McColors.primarySoft)),
        const SizedBox(height: 8),
        ...children,
      ]),
    );
  }

  Widget _trendCard(Map trend) {
    final dir = _dirs[trend['direction']] ?? _dirs['neutral']!;
    final conf = trend['confidence'] is num
        ? (trend['confidence'] as num).toDouble()
        : null;
    return _card(tr('ai_sec_trend'), [
      Row(children: [
        _badge(dir.$1, dir.$2),
        if (conf != null) ...[
          const Spacer(),
          Text(tr('ai_confidence').replaceAll('{v}', conf.toInt().toString()),
              style:
                  McText.mono(size: 11, color: McColors.onSurfaceVariant)),
        ],
      ]),
      if (conf != null) ...[
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: (conf.clamp(0, 100)) / 100,
            minHeight: 4,
            backgroundColor: McColors.surfaceContainerHigh,
            valueColor: AlwaysStoppedAnimation(dir.$2),
          ),
        ),
      ],
      if (trend['ma_status'] != null) ...[
        const SizedBox(height: 8),
        Text(trend['ma_status'].toString(),
            style: McText.sans(size: 13, color: McColors.onSurface)),
      ],
      if (trend['reason'] != null) ...[
        const SizedBox(height: 4),
        Text(trend['reason'].toString(),
            style: McText.sans(
                size: 12, height: 1.5, color: McColors.onSurfaceVariant)),
      ],
    ]);
  }

  Widget _patternsCard(List patterns) {
    return _card(tr('ai_sec_patterns'), [
      for (final p in patterns)
        if (p is Map)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _badge(p['name']?.toString() ?? '', McColors.primarySoft),
                const SizedBox(width: 8),
                Text('${p['type'] ?? ''} · ${p['validity'] ?? ''}',
                    style: McText.mono(
                        size: 10, color: McColors.onSurfaceVariant)),
              ]),
              if (p['description'] != null) ...[
                const SizedBox(height: 4),
                Text(p['description'].toString(),
                    style: McText.sans(
                        size: 12,
                        height: 1.5,
                        color: McColors.onSurfaceVariant)),
              ],
            ]),
          ),
    ]);
  }

  Widget _levelsCard(Map levels) {
    final supports = levels['supports'] is List ? levels['supports'] as List : [];
    final resistances =
        levels['resistances'] is List ? levels['resistances'] as List : [];
    return _card(tr('ai_sec_levels'), [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('ai_support'),
                style: McText.sans(size: 11, color: McColors.bull)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in supports) _badge(_num(s), McColors.bull),
            ]),
          ]),
        ),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('ai_resistance'),
                style: McText.sans(size: 11, color: McColors.bear)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final r in resistances) _badge(_num(r), McColors.bear),
            ]),
          ]),
        ),
      ]),
      if (levels['breakout'] != null) ...[
        const SizedBox(height: 8),
        Text(levels['breakout'].toString(),
            style: McText.sans(size: 13, color: McColors.onSurface)),
      ],
      if (levels['description'] != null) ...[
        const SizedBox(height: 4),
        Text(levels['description'].toString(),
            style: McText.sans(
                size: 12, height: 1.5, color: McColors.onSurfaceVariant)),
      ],
    ]);
  }

  Widget _volumeCard(Map volume) {
    final divergence = volume['divergence']?.toString();
    return _card(tr('ai_sec_volume'), [
      Row(children: [
        if (volume['state'] != null)
          Text(volume['state'].toString(),
              style: McText.sans(size: 12, color: McColors.onSurface)),
        if (divergence != null &&
            divergence.isNotEmpty &&
            divergence != '无') ...[
          const SizedBox(width: 8),
          _badge(divergence, McColors.goldBright),
        ],
      ]),
      if (volume['description'] != null) ...[
        const SizedBox(height: 4),
        Text(volume['description'].toString(),
            style: McText.sans(
                size: 12, height: 1.5, color: McColors.onSurfaceVariant)),
      ],
    ]);
  }

  Widget _signalCard(Map signal) {
    final act = _actions[signal['action']] ?? _actions['hold']!;
    final sl = signal['stop_loss'];
    final tp = signal['take_profit'];
    final risks = signal['risks'] is List ? signal['risks'] as List : [];
    return _card(tr('ai_sec_signal'), [
      _badge(act.$1, act.$2),
      if (sl != null || tp != null) ...[
        const SizedBox(height: 8),
        Row(children: [
          if (sl != null)
            Expanded(
                child: _slTpTile(tr('ai_stop_loss'), _num(sl), McColors.bear)),
          if (sl != null && tp != null) const SizedBox(width: 8),
          if (tp != null)
            Expanded(
                child:
                    _slTpTile(tr('ai_take_profit'), _num(tp), McColors.bull)),
        ]),
      ],
      if (signal['summary'] != null) ...[
        const SizedBox(height: 8),
        Text(signal['summary'].toString(),
            style: McText.sans(
                size: 12, height: 1.5, color: McColors.onSurfaceVariant)),
      ],
      if (risks.isNotEmpty) ...[
        const SizedBox(height: 6),
        for (final r in risks)
          Text('· ${r.toString()}',
              style: McText.sans(
                  size: 12,
                  height: 1.5,
                  color: McColors.onSurfaceVariant.withValues(alpha: 0.8))),
      ],
    ]);
  }

  Widget _slTpTile(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        Text(label,
            style: McText.mono(size: 10, color: McColors.onSurfaceVariant)),
        const Spacer(),
        Text(value,
            style:
                McText.mono(size: 13, weight: FontWeight.w600, color: color)),
      ]),
    );
  }
}
