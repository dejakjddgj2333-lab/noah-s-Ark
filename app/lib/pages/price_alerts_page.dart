import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';

/// 行情预警: 新建 (交易对/方向/目标价) + 我的预警列表, 可调删除.
class PriceAlertsPage extends StatefulWidget {
  const PriceAlertsPage({super.key});

  @override
  State<PriceAlertsPage> createState() => _PriceAlertsPageState();
}

class _PriceAlertsPageState extends State<PriceAlertsPage> {
  final _symbolCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  bool _up = true; // true=涨破 up, false=跌破 down

  bool _loading = true;
  bool _busy = false;
  List<dynamic> _alerts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _symbolCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: McText.sans(size: 13)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error
            ? McColors.bear.withValues(alpha: 0.9)
            : McColors.surfaceContainerHigh,
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list =
          await McApi.getList('/api/price-alerts', token: AuthStore.instance.token);
      if (!mounted) return;
      setState(() => _alerts = list);
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast(tr('update_failed'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    if (_busy) return;
    final symbol = _symbolCtrl.text.trim().toUpperCase();
    final price = double.tryParse(_targetCtrl.text.trim());
    if (symbol.isEmpty) {
      _toast(tr('pa_err_symbol'), error: true);
      return;
    }
    if (price == null || price <= 0) {
      _toast(tr('pa_err_price'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await McApi.post('/api/price-alerts', {
        'symbol': symbol,
        'direction': _up ? 'up' : 'down',
        'target_price': price,
      }, token: AuthStore.instance.token);
      if (!mounted) return;
      _symbolCtrl.clear();
      _targetCtrl.clear();
      _toast(tr('pa_added'));
      await _load();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast(tr('update_failed'), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: McColors.surfaceContainerLow,
        title: Text(tr('pref_price_alert'),
            style: McText.sans(size: 15, weight: FontWeight.w700)),
        content: Text(tr('pa_del_confirm'),
            style: McText.sans(size: 13, color: McColors.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel'),
                style: McText.sans(color: McColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('pa_del_ok'),
                style: McText.sans(color: McColors.bear)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await McApi.del('/api/price-alerts/${a['id']}',
          token: AuthStore.instance.token);
      await _load();
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast(tr('update_failed'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: McColors.onSurface),
        title: Text(tr('pref_price_alert'),
            style: McText.sans(size: 15, weight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: McColors.primarySoft,
        backgroundColor: McColors.surfaceContainerHigh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 20, 14, 24),
          children: [
            _newCard(),
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: McColors.primarySoft),
                ),
              )
            else if (_alerts.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(
                  child: Text(tr('pa_empty'),
                      style: McText.sans(
                          size: 13, color: McColors.onSurfaceVariant)),
                ),
              )
            else
              ..._alerts.map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _alertCard(a as Map<String, dynamic>),
                  )),
          ],
        ),
      ),
    );
  }

  // ---------------- 新建卡片 ----------------
  Widget _newCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: McColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('pa_new'),
              style: McText.sans(
                  size: 13,
                  weight: FontWeight.w600,
                  color: McColors.onSurfaceVariant,
                  letterSpacing: 0.5)),
          const SizedBox(height: 14),
          _symbolField(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _dirChip(true)),
              const SizedBox(width: 10),
              Expanded(child: _dirChip(false)),
            ],
          ),
          const SizedBox(height: 12),
          _targetField(),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _busy ? null : _add,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: _busy
                    ? McColors.surfaceContainerHigh
                    : McColors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: McColors.primarySoft),
                    )
                  : Text(tr('pa_add'),
                      style: McText.sans(
                          size: 14,
                          weight: FontWeight.w700,
                          color: McColors.onPrimaryContainer)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _symbolField() {
    return TextField(
      controller: _symbolCtrl,
      textCapitalization: TextCapitalization.characters,
      style: McText.mono(size: 13),
      decoration: InputDecoration(
        hintText: tr('pa_symbol'),
        hintStyle: McText.sans(size: 13, color: McColors.onSurfaceVariant),
        prefixIcon: const Icon(Icons.currency_bitcoin,
            size: 18, color: McColors.onSurfaceVariant),
        filled: true,
        fillColor: McColors.surfaceContainerLowest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: McColors.outlineVariant.withValues(alpha: 0.6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: McColors.outlineVariant.withValues(alpha: 0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: McColors.primaryContainer, width: 1.5),
        ),
      ),
    );
  }

  Widget _targetField() {
    return TextField(
      controller: _targetCtrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: McText.mono(size: 13),
      decoration: InputDecoration(
        hintText: tr('pa_target'),
        hintStyle: McText.sans(size: 13, color: McColors.onSurfaceVariant),
        prefixIcon: const Icon(Icons.price_change_outlined,
            size: 18, color: McColors.onSurfaceVariant),
        filled: true,
        fillColor: McColors.surfaceContainerLowest,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: McColors.outlineVariant.withValues(alpha: 0.6)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: McColors.outlineVariant.withValues(alpha: 0.6)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: McColors.primaryContainer, width: 1.5),
        ),
      ),
    );
  }

  Widget _dirChip(bool up) {
    final sel = _up == up;
    final color = up ? McColors.bull : McColors.bear;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _up = up),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: sel
              ? McColors.primaryContainer.withValues(alpha: 0.18)
              : McColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: sel
                ? McColors.primary.withValues(alpha: 0.7)
                : McColors.outlineVariant.withValues(alpha: 0.6),
            width: sel ? 1.5 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(up ? Icons.trending_up : Icons.trending_down,
                size: 16, color: sel ? color : McColors.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              up ? tr('pa_up') : tr('pa_down'),
              style: McText.sans(
                size: 13,
                weight: sel ? FontWeight.w700 : FontWeight.w500,
                color: sel ? Colors.white : McColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 列表项 ----------------
  Widget _alertCard(Map<String, dynamic> a) {
    final symbol = (a['symbol'] ?? '').toString();
    final up = (a['direction'] ?? 'up').toString() == 'up';
    final triggered = a['triggered'] == true;
    final price = a['target_price'];
    final priceStr =
        price is num ? price.toString() : (price ?? '').toString();
    final dirColor = up ? McColors.bull : McColors.bear;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: McColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: McColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        symbol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: McText.sans(
                            size: 16,
                            weight: FontWeight.w700,
                            color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: dirColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(up ? tr('pa_up') : tr('pa_down'),
                          style: McText.sans(size: 12, color: dirColor)),
                    ),
                    if (triggered) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: McColors.onSurfaceVariant
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(tr('pa_triggered'),
                            style: McText.sans(
                                size: 12,
                                color: McColors.onSurfaceVariant)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${tr('pa_target')} $priceStr',
                  style: McText.mono(size: 12, color: McColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _confirmDelete(a),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.delete_outline,
                  size: 20, color: McColors.bear),
            ),
          ),
        ],
      ),
    );
  }
}
