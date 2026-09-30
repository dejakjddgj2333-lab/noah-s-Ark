import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/api.dart';
import '../services/data.dart';

/// 宏观日历 — 北京时间宏观事件列表 (按日期切换 / 拉刷新).
class MacroCalendarPage extends StatefulWidget {
  const MacroCalendarPage({super.key});

  @override
  State<MacroCalendarPage> createState() => _MacroCalendarPageState();
}

class _MacroCalendarPageState extends State<MacroCalendarPage> {
  static const _amber = McColors.goldBright;

  List<MacroEventItem> _items = const [];
  bool _loading = true;
  bool _error = false;

  // 当前查看的北京时间日期 (只用到日, 时分秒忽略).
  late DateTime _date = _today();

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _dateStr {
    final y = _date.year.toString().padLeft(4, '0');
    final m = _date.month.toString().padLeft(2, '0');
    final d = _date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String get _dateLabel {
    const weeks = ['一', '二', '三', '四', '五', '六', '日'];
    return '$_dateStr 星期${weeks[_date.weekday - 1]}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final items = await McData.macroCalendar(date: _dateStr);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  void _shift(int days) {
    setState(() => _date = _date.add(Duration(days: days)));
    _load();
  }

  void _resetToday() {
    if (_date == _today()) return;
    setState(() => _date = _today());
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surface,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: McColors.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('宏观日历',
            style: McText.display(size: 16, weight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _dateNav(),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: _amber,
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  // ‹ 前一天 | 今天日期 (tap 回今天) | 后一天 ›
  Widget _dateNav() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          _navBtn(Icons.chevron_left, () => _shift(-1)),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _resetToday,
              child: Column(
                children: [
                  Text(
                    _dateLabel,
                    textAlign: TextAlign.center,
                    style: McText.mono(
                        size: 13,
                        weight: FontWeight.w700,
                        color: McColors.onSurface),
                  ),
                  if (_date == _today())
                    Text(
                      '今天',
                      style: McText.sans(size: 12, color: _amber),
                    ),
                ],
              ),
            ),
          ),
          _navBtn(Icons.chevron_right, () => _shift(1)),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: McColors.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: McColors.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Icon(icon, size: 20, color: McColors.onSurfaceVariant),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      // keep scrollable so RefreshIndicator works during load
      return ListView(
        children: const [
          SizedBox(height: 220),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          const SizedBox(height: 160),
          Center(child: _errorCard()),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 200),
          Center(
            child: Text(
              '当日无宏观事件',
              style: McText.sans(size: 13, color: McColors.onSurfaceVariant),
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
      itemCount: _items.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _eventCard(_items[i]),
      ),
    );
  }

  Widget _errorCard() {
    return McCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('加载失败',
              style: McText.sans(size: 13, color: McColors.onSurfaceVariant)),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _load,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              decoration: BoxDecoration(
                color: McColors.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '重试',
                style: McText.mono(
                    size: 12,
                    weight: FontWeight.w700,
                    color: const Color(0xFFFFFFFF)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _eventCard(MacroEventItem e) {
    return McCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // time
              Text(
                e.eventAt.isEmpty ? '--:--' : e.eventAt,
                style: McText.mono(
                    size: 13,
                    weight: FontWeight.w700,
                    color: McColors.onSurface),
              ),
              const SizedBox(width: 10),
              // country + currency chip
              if (e.country.isNotEmpty || e.currency.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: McPill(
                    [e.country, e.currency]
                        .where((s) => s.isNotEmpty)
                        .join(' '),
                    color: McColors.primarySoft,
                  ),
                ),
              const SizedBox(width: 8),
              // importance stars
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _stars(e.importance),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // name (wraps 2 lines)
          Text(
            e.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: McText.sans(
                size: 13, weight: FontWeight.w600, height: 1.4),
          ),
          const SizedBox(height: 8),
          _valuesRow(e),
        ],
      ),
    );
  }

  Widget _stars(int importance) {
    final n = importance.clamp(1, 3);
    final label = importance >= 3 ? '高' : importance == 2 ? '中' : '低';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < n; i++)
          const Text('★', style: TextStyle(fontSize: 12, color: _amber)),
        const SizedBox(width: 4),
        Text(label, style: McText.mono(size: 12, color: _amber)),
      ],
    );
  }

  // 前值 X · 预期 Y · 公布 Z
  Widget _valuesRow(MacroEventItem e) {
    return Row(
      children: [
        Expanded(child: _value('前值', e.previous, muted: true)),
        Expanded(child: _value('预期', e.forecast, muted: true)),
        Expanded(child: _value('公布', e.actual, highlight: true)),
      ],
    );
  }

  Widget _value(String label, String? raw,
      {bool muted = false, bool highlight = false}) {
    final has = raw != null && raw.isNotEmpty;
    final color = !has
        ? McColors.onSurfaceVariant
        : highlight
            ? _amber
            : McColors.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                McText.sans(size: 12, color: McColors.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          has ? raw : '--',
          overflow: TextOverflow.ellipsis,
          style: McText.mono(
            size: 12,
            weight: highlight && has ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}
