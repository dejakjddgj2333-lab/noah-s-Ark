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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDetail(e),
      child: McCard(
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
                const Spacer(),
                const Icon(Icons.chevron_right,
                    size: 16, color: McColors.onSurfaceVariant),
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
      ),
    );
  }

  void _openDetail(MacroEventItem e) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: McColors.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _MacroDetailSheet(eventId: e.id, fallbackName: e.name),
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

/// 宏观事件详情弹层: 中文解读 + 历史走势.
class _MacroDetailSheet extends StatefulWidget {
  const _MacroDetailSheet({required this.eventId, required this.fallbackName});

  final int eventId;
  final String fallbackName;

  @override
  State<_MacroDetailSheet> createState() => _MacroDetailSheetState();
}

class _MacroDetailSheetState extends State<_MacroDetailSheet> {
  static const _amber = McColors.goldBright;

  MacroEventDetail? _detail;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await McData.macroEventDetail(widget.eventId);
      if (!mounted) return;
      setState(() => _detail = d);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) {
        if (d == null) {
          return Center(
            child: _error
                ? Text('加载失败',
                    style: McText.sans(
                        size: 13, color: McColors.onSurfaceVariant))
                : const CircularProgressIndicator(),
          );
        }
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: McColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // 标题行
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.name.isEmpty ? widget.fallbackName : d.name,
                        style: McText.sans(
                            size: 16, weight: FontWeight.w700, height: 1.4),
                      ),
                      if (d.nameEn.isNotEmpty && d.nameEn != d.name)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            d.nameEn,
                            style: McText.sans(
                                size: 12,
                                color: McColors.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _stars(d.importance),
              ],
            ),
            const SizedBox(height: 10),
            // 时间/国家/币种
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                McPill(d.eventAt, color: McColors.primarySoft),
                if (d.country.isNotEmpty || d.currency.isNotEmpty)
                  McPill(
                    [d.country, d.currency]
                        .where((s) => s.isNotEmpty)
                        .join(' '),
                    color: McColors.primarySoft,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _values(d),
            // 解读
            if (d.descZh != null && d.descZh!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('指标解读',
                  style: McText.sans(
                      size: 13, weight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: McColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color:
                          McColors.outlineVariant.withValues(alpha: 0.6)),
                ),
                child: Text(
                  d.descZh!,
                  style: McText.sans(
                      size: 13,
                      height: 1.6,
                      color: McColors.onSurface),
                ),
              ),
            ],
            // 历史走势
            if (d.history.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('历史走势 (近 ${d.history.length} 期)',
                  style: McText.sans(
                      size: 13, weight: FontWeight.w700)),
              const SizedBox(height: 8),
              _HistoryChart(points: d.history, unit: d.unit),
              const SizedBox(height: 8),
              for (final p in d.history.reversed) _historyRow(p, d.unit),
            ] else ...[
              const SizedBox(height: 16),
              Text('暂无历史数据',
                  style: McText.sans(
                      size: 12, color: McColors.onSurfaceVariant)),
            ],
          ],
        );
      },
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

  Widget _values(MacroEventDetail d) {
    Widget cell(String label, String? raw, {bool highlight = false}) {
      final has = raw != null && raw.isNotEmpty;
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: McText.sans(
                    size: 12, color: McColors.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(
              has ? raw : '--',
              overflow: TextOverflow.ellipsis,
              style: McText.mono(
                size: 13,
                weight: highlight && has ? FontWeight.w700 : FontWeight.w500,
                color: !has
                    ? McColors.onSurfaceVariant
                    : highlight
                        ? _amber
                        : McColors.onSurface,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        cell('前值', d.previous),
        cell('预期', d.forecast),
        cell('公布', d.actual, highlight: true),
      ],
    );
  }

  Widget _historyRow(MacroHistoryPoint p, String unit) {
    final actualNum = MacroHistoryPoint.parseNum(p.actual);
    final forecastNum = MacroHistoryPoint.parseNum(p.forecast);
    String tag = '';
    Color tagColor = McColors.onSurfaceVariant;
    if (actualNum != null && forecastNum != null) {
      if (actualNum > forecastNum) {
        tag = '高于预期';
        tagColor = const Color(0xFF2EBD85);
      } else if (actualNum < forecastNum) {
        tag = '低于预期';
        tagColor = const Color(0xFFF6465D);
      } else {
        tag = '符合预期';
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(p.date,
                style: McText.mono(
                    size: 12, color: McColors.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
              p.actual?.isNotEmpty == true
                  ? '${p.actual}${unit.isNotEmpty && p.actual!.contains(unit) ? '' : unit}'
                  : '--',
              style: McText.mono(
                  size: 12,
                  weight: FontWeight.w600,
                  color: McColors.onSurface),
            ),
          ),
          if (tag.isNotEmpty)
            Text(tag, style: McText.sans(size: 12, color: tagColor)),
        ],
      ),
    );
  }
}

/// 历史公布值柱状图 (仅能解析数值时绘制).
class _HistoryChart extends StatelessWidget {
  const _HistoryChart({required this.points, required this.unit});

  final List<MacroHistoryPoint> points; // 正序
  final String unit;

  @override
  Widget build(BuildContext context) {
    final values = points
        .map((p) => MacroHistoryPoint.parseNum(p.actual))
        .toList();
    final valid = values.whereType<double>().toList();
    if (valid.length < 2) return const SizedBox.shrink();

    return Container(
      height: 120,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: McColors.surface,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: McColors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: CustomPaint(
        size: Size.infinite,
        painter: _BarsPainter(values: values),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({required this.values});

  final List<double?> values;

  @override
  void paint(Canvas canvas, Size size) {
    final nums = values.whereType<double>().toList();
    if (nums.isEmpty) return;
    var minV = nums.reduce((a, b) => a < b ? a : b);
    var maxV = nums.reduce((a, b) => a > b ? a : b);
    if (minV > 0) minV = 0; // 柱从 0 起更直观
    if (maxV < 0) maxV = 0;
    final range = (maxV - minV).abs() < 1e-12 ? 1.0 : maxV - minV;

    final n = values.length;
    final slot = size.width / n;
    final barW = (slot * 0.55).clamp(2.0, 24.0);
    final zeroY = size.height * (maxV / range);

    final paint = Paint()..color = McColors.goldBright;
    final negPaint = Paint()..color = const Color(0xFFF6465D);

    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) continue;
      final h = size.height * (v.abs() / range);
      final left = i * slot + (slot - barW) / 2;
      final rect = v >= 0
          ? Rect.fromLTWH(left, zeroY - h, barW, h)
          : Rect.fromLTWH(left, zeroY, barW, h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        v >= 0 ? paint : negPaint,
      );
    }

    // 零轴
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = McColors.outlineVariant
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.values != values;
}
