import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../theme.dart';

/// 币种图标: 自有服务端缓存图 (服务端代取 OKX 并落盘, 国内直连 OKX CDN 不稳)
/// → 加载失败回退首字母圆 (与 web/app 端一致)。
/// 传 instId 或裸币种都行: BTC-USDT-SWAP / BTCUSDT / BTC 均可。
class CoinIcon extends StatelessWidget {
  const CoinIcon(this.symbol, {super.key, this.size = 24});

  final String symbol;
  final double size;

  static String baseOf(String s) {
    final v = s.trim().toUpperCase();
    if (v.contains('-')) return v.split('-').first;
    return v.replaceFirst(RegExp(r'USDT?$'), '');
  }

  String get _base => baseOf(symbol);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        color: Mc.surface,
        child: Stack(fit: StackFit.expand, children: [
          // 字母占位: 图加载成功后盖住
          Center(
            child: Text(
              _base.isEmpty ? '?' : _base.substring(0, 1),
              style: Mc.mono((size * 0.4).clamp(9.0, 16.0),
                  w: FontWeight.w700, color: Mc.muted),
            ),
          ),
          Image.network(
            '${ApiClient.apiBase}/coin-icon/${_base.toLowerCase()}.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
            // 加载中透明, 露出字母占位; 失败回退字母
            opacity: const AlwaysStoppedAnimation(1),
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
            loadingBuilder: (_, child, progress) =>
                progress == null ? child : const SizedBox.shrink(),
          ),
        ]),
      ),
    );
  }
}
