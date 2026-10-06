import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';
import '../services/api.dart';
import '../services/auth.dart';

/// 登录设备管理: 列出所有登录设备, 可下线非当前设备.
class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  bool _loading = true;
  List<dynamic> _devices = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: McText.sans(size: 13)),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            error ? McColors.bear.withValues(alpha: 0.9) : McColors.surfaceContainerHigh,
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await AuthStore.instance.devices();
      if (!mounted) return;
      setState(() => _devices = list);
    } on ApiException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast(tr('update_failed'), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _icon(String platform) {
    switch (platform.toLowerCase()) {
      case 'ios':
        return Icons.phone_iphone;
      case 'android':
        return Icons.phone_android;
      default:
        return Icons.computer;
    }
  }

  String _shortTime(String? s) {
    if (s == null) return '';
    return s.length <= 16 ? s : s.substring(0, 16);
  }

  Future<void> _confirmRemove(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: McColors.surfaceContainerLow,
        title: Text(tr('dev_offline'),
            style: McText.sans(size: 15, weight: FontWeight.w700)),
        content: Text(tr('dev_offline_confirm'),
            style: McText.sans(size: 13, color: McColors.onSurfaceVariant)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('cancel'),
                style: McText.sans(color: McColors.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('dev_offline'),
                style: McText.sans(color: McColors.bear)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AuthStore.instance.removeDevice(d['id'] as int);
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
        title: Text(tr('dev_title'),
            style: McText.sans(size: 15, weight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: McColors.primarySoft),
            )
          : _devices.isEmpty
              ? Center(
                  child: Text(tr('dev_empty'),
                      style: McText.sans(
                          size: 13, color: McColors.onSurfaceVariant)),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: McColors.primarySoft,
                  backgroundColor: McColors.surfaceContainerHigh,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 20, 14, 24),
                    itemCount: _devices.length,
                    separatorBuilder: (_, i) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final d = _devices[i] as Map<String, dynamic>;
                      return _card(d);
                    },
                  ),
                ),
    );
  }

  Widget _card(Map<String, dynamic> d) {
    final platform = (d['platform'] ?? '').toString();
    final name = (d['device_name'] ?? '').toString();
    final ip = (d['ip'] ?? '').toString();
    final lastSeen = (d['last_seen_at'] ?? '').toString();
    final current = d['current'] == true;
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
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: McColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon(platform),
                size: 20, color: McColors.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name.isNotEmpty ? name : platform,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: McText.sans(
                            size: 14,
                            weight: FontWeight.w600,
                            color: Colors.white),
                      ),
                    ),
                    if (current) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: McColors.bull.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(tr('dev_current'),
                            style: McText.sans(
                                size: 12, color: McColors.bull)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(ip,
                    style: McText.mono(
                        size: 12, color: McColors.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text('${tr('dev_last')} ${_shortTime(lastSeen)}',
                    style: McText.sans(
                        size: 12, color: McColors.onSurfaceVariant)),
              ],
            ),
          ),
          if (!current)
            GestureDetector(
              onTap: () => _confirmRemove(d),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Text(tr('dev_offline'),
                    style: McText.sans(
                        size: 13,
                        weight: FontWeight.w600,
                        color: McColors.bear)),
              ),
            ),
        ],
      ),
    );
  }
}
