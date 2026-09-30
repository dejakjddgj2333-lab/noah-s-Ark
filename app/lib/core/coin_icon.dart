import 'package:flutter/material.dart';

import 'theme.dart';

/// 已下载到本地的币种图标 (与 assets/coins/ 对应, 源自 okx 项目).
/// 不在名单内的走 OKX CDN 网络加载, 再失败回退首字母.
const Set<String> kLocalCoins = {
  'btc', 'eth', 'usdt', 'usdc', 'sol', 'xrp', 'doge', 'ada', 'trx', 'ton',
  'avax', 'link', 'dot', 'matic', 'ltc', 'bch', 'shib', 'uni', 'atom', 'etc',
  'fil', 'near', 'apt', 'arb', 'op', 'inj', 'sui', 'sei', 'tia', 'pepe',
  'wif', 'bonk', 'floki', 'rndr', 'imx', 'stx', 'hbar', 'ftm', 'algo',
  'sand', 'mana', 'axs', 'ape', 'chz', 'enj', 'gala', 'lrc', 'crv', 'aave',
  'mkr', 'snx', 'comp', 'yfi', 'sushi', '1inch', 'bat', 'zrx', 'knc', 'lpt',
  'grt', 'skl', 'celr', 'band', 'nmr', 'storj', 'ankr',
};

/// 币种图标: 本地 asset → OKX CDN → 首字母回退 (与 okx 项目一致).
class CoinIcon extends StatelessWidget {
  const CoinIcon(this.baseCcy, {super.key, this.size = 40});

  final String baseCcy;
  final double size;

  String get _symbol => baseCcy.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final Widget image = kLocalCoins.contains(_symbol)
        ? Image.asset(
            'assets/coins/$_symbol.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => _fallback(),
          )
        : Image.network(
            'https://static.okx.com/cdn/oksupport/asset/currency/icon/$_symbol.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => _fallback(),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: image,
    );
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      color: McColors.onSurfaceVariant.withValues(alpha: 0.15),
      child: Text(
        baseCcy.isNotEmpty ? baseCcy.characters.first.toUpperCase() : '?',
        style: McText.mono(
          size: (size * 0.42).clamp(12.0, double.infinity),
          weight: FontWeight.w700,
          color: McColors.onSurfaceVariant,
        ),
      ),
    );
  }
}
