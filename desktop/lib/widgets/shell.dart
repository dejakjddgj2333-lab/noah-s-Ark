import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../pages/deposit_page.dart';
import '../pages/news_page.dart';
import '../pages/profile_page.dart';
import '../pages/search_results.dart';
import '../pages/withdraw_page.dart';
import '../state/auth_store.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/kit.dart';

class NavItem {
  const NavItem(this.icon, this.label, this.tag, this.page);
  final IconData icon;
  final String label;
  final String tag;
  final Widget page;

  /// 红色 ALERT 角标 (对齐 web 侧栏): 爆仓监控项为 true。
  /// main.dart 构造 NavItem 不可改, 故按 tag 判定。
  bool get alert => tag == 'LIQUIDATION';
}

/// Overlay router for drill-in pages that are not sidebar destinations
/// (deposit, withdraw, market detail...). Push replaces the content area
/// with a back-afforded page; pop returns to the sidebar stack.
class ShellRouter extends ChangeNotifier {
  ShellRouter._();
  static final ShellRouter I = ShellRouter._();

  final List<({String title, String tag, Widget page})> _stack = [];

  ({String title, String tag, Widget page})? get current =>
      _stack.isEmpty ? null : _stack.last;

  void push(String title, String tag, Widget page) {
    _stack.add((title: title, tag: tag, page: page));
    notifyListeners();
  }

  void pop() {
    if (_stack.isEmpty) return;
    _stack.removeLast();
    notifyListeners();
  }

  /// Drop all overlays, e.g. when a sidebar destination is selected.
  void clear() {
    if (_stack.isEmpty) return;
    _stack.clear();
    notifyListeners();
  }
}

/// Desktop shell: 240px sidebar + 56px topbar + content.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.items});
  final List<NavItem> items;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(children: [
        _Sidebar(
          items: widget.items,
          index: _index,
          onSelect: (i) {
            ShellRouter.I.clear(); // sidebar switch drops any drill-in page
            setState(() => _index = i);
          },
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: ShellRouter.I,
            builder: (context, _) {
              final overlay = ShellRouter.I.current;
              final title = overlay?.title ?? widget.items[_index].label;
              final tag = overlay?.tag ?? widget.items[_index].tag;
              return Column(children: [
                _Topbar(
                    title: title,
                    tag: tag,
                    onBack: overlay != null ? ShellRouter.I.pop : null),
                const Divider(height: 1, color: Mc.hairline),
                Expanded(
                  // KeyedSubtree 按涨跌配色方案换 key: 切换方案时强制页面子树
                  // 重建 (IndexedStack 里 const 页面默认不重绘, Mc.up/down 不生效)。
                  child: overlay != null
                      ? KeyedSubtree(
                          key: ValueKey('overlay-${Mc.cnScheme}'),
                          child: overlay.page)
                      : IndexedStack(
                          index: _index,
                          children: [
                            for (var i = 0; i < widget.items.length; i++)
                              KeyedSubtree(
                                  key: ValueKey('page$i-${Mc.cnScheme}'),
                                  child: widget.items[i].page),
                          ],
                        ),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar(
      {required this.items, required this.index, required this.onSelect});
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: Mc.sidebarWidth,
      color: Mc.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Logo: 固定高度 = 顶栏 56px, 与右侧顶栏底部分隔线对齐
        Container(
          height: Mc.topbarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/logo.png',
                  width: 30, height: 30, fit: BoxFit.cover),
            ),
            const SizedBox(width: 10),
            // mainAxisSize.min: 收缩到内容高度, Row 才能将其垂直居中
            Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Text('明策', style: Mc.display(14, w: FontWeight.w700)),
                const SizedBox(width: 4),
                Text('MINGCE',
                    style: Mc.display(12, w: FontWeight.w700, color: Mc.cobaltSoft)),
              ]),
              Text('TERMINAL', style: Mc.tag(color: Mc.cobaltSoft)),
            ]),
          ]),
        ),
        const Divider(height: 1, color: Mc.hairline),
        const SizedBox(height: 8),
        // Nav
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: items.length,
            itemBuilder: (context, i) => _NavTile(
              item: items[i],
              selected: i == index,
              onTap: () => onSelect(i),
            ),
          ),
        ),
        const Divider(height: 1, color: Mc.hairline),
        _UserBlock(),
      ]),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile(
      {required this.item, required this.selected, required this.onTap});
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Mc.ink : Mc.muted;
    final iconColor = selected
        ? Mc.cobaltSoft
        : item.alert
            ? Mc.bear.withValues(alpha: 0.8)
            : color;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? Mc.cardHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: Mc.cardHigh.withValues(alpha: 0.5),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Icon(item.icon, size: 17, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(item.label,
                    style: Mc.body(13,
                        w: selected ? FontWeight.w600 : FontWeight.w400,
                        color: color)),
              ),
              // 红色 ALERT 角标 (对齐 web: bear 20% 底 + bear 文字 + 40% 描边)
              if (item.alert)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Mc.bear.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: Mc.bear.withValues(alpha: 0.4)),
                  ),
                  child: Text('ALERT',
                      style: Mc.tag(color: Mc.bear)
                          .copyWith(fontSize: 9, letterSpacing: 1)),
                )
              else if (selected)
                Container(width: 3, height: 16, color: Mc.cobalt),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 侧栏底部操作员卡 (对齐 web 结构): 头像 + 操作员名 + OPERATOR 徽标 +
/// 终端 ID + 延迟 + 加密环境 tag。登出入口已移到顶栏「断开终端」。
class _UserBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthStore.I,
      builder: (context, _) {
        final name = AuthStore.I.displayName;
        final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Mc.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Mc.hairline),
          ),
          child: Column(children: [
            // 行1: 头像 + 操作员名 + OPERATOR 徽标
            Row(children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: Mc.cardHigh,
                child: Text(initial,
                    style: Mc.mono(10,
                        w: FontWeight.w700, color: Mc.cobaltSoft)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('操作员: ${name.isEmpty ? '--' : name}',
                    style: Mc.body(12, w: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Mc.cobalt.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border:
                      Border.all(color: Mc.cobalt.withValues(alpha: 0.4)),
                ),
                child: Text('OPERATOR',
                    style: Mc.tag(color: Mc.cobaltSoft)
                        .copyWith(fontSize: 9, letterSpacing: 1)),
              ),
            ]),
            const SizedBox(height: 8),
            // 行2: 终端 ID + 延迟
            Row(children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                    color: Mc.bull, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text('HK-CENTRAL-01',
                    style: Mc.mono(10, color: Mc.muted)),
              ),
              const Icon(Icons.wifi_tethering, size: 12, color: Mc.bull),
              const SizedBox(width: 3),
              Text('12ms', style: Mc.mono(10, color: Mc.bull)),
            ]),
            const SizedBox(height: 6),
            // 行3: 加密环境 tag
            Align(
              alignment: Alignment.centerLeft,
              child: Text('AES-256 GCM · ZERO LOG',
                  style: Mc.mono(9,
                      color: Mc.muted.withValues(alpha: 0.6))
                      .copyWith(letterSpacing: 1)),
            ),
          ]),
        );
      },
    );
  }
}

class _Topbar extends StatelessWidget {
  const _Topbar({required this.title, required this.tag, this.onBack});
  final String title;
  final String tag;
  final VoidCallback? onBack;  @override
  Widget build(BuildContext context) {
    return Container(
      height: Mc.topbarHeight,
      color: Mc.canvas,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(children: [
        if (onBack != null)
          IconButton(
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back, size: 18, color: Mc.muted),
            onPressed: onBack,
          ),
        // 标题区可压缩, 防顶栏整体溢出 (黄黑斜纹 overflow);
        // 注意必须用 Expanded(tight): Flutter 3.44 RenderFlex 对 loose
        // Flexible 的空余空间分配有 bug, 会把 Spacer 挤短导致右侧留空白
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tag,
                  style: Mc.tag(color: Mc.cobaltSoft),
                  overflow: TextOverflow.ellipsis),
              Text(title,
                  style: Mc.display(15), overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // STATUS: LIVE FEED 徽标 (对齐 web 顶栏标题旁状态片), 窄窗隐藏
        if (MediaQuery.of(context).size.width >= 1320) const _StatusChip(),
        const Spacer(),
        const SizedBox(width: 200, child: _SearchBox()),
        // 市场活跃度 chip (对齐 web: 静态 HIGH), 窄窗隐藏
        if (MediaQuery.of(context).size.width >= 1500) ...[
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Mc.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Mc.hairline),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                    color: Mc.bull, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text('市场活跃度', style: Mc.mono(11, color: Mc.muted)),
              const SizedBox(width: 6),
              Text('HIGH',
                  style: Mc.mono(11, w: FontWeight.w700, color: Mc.bull)),
            ]),
          ),
          const SizedBox(width: 12),
          // SSL 状态 chip (对齐 web: 静态)
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.speed, size: 15, color: Mc.bull),
            const SizedBox(width: 4),
            Text('SSL 256-BIT · 14ms', style: Mc.mono(11, color: Mc.muted)),
          ]),
        ],
        const SizedBox(width: 12),
        const _NotifBell(),
        const SizedBox(width: 10),
        McButton('充值',
            kind: McBtnKind.primary,
            height: 32,
            icon: Icons.arrow_downward,
            onPressed: () =>
                ShellRouter.I.push('充值', 'DEPOSIT', const DepositPage())),
        const SizedBox(width: 8),
        McButton('提现',
            kind: McBtnKind.ghost,
            height: 32,
            icon: Icons.arrow_upward,
            onPressed: () =>
                ShellRouter.I.push('提现', 'WITHDRAW', const WithdrawPage())),
        const SizedBox(width: 8),
        // 断开终端 = 登出 (对齐 web 顶栏右侧按钮), 图标化防顶栏溢出
        IconButton(
          tooltip: '断开终端 (退出登录)',
          icon: const Icon(Icons.logout, size: 16, color: Mc.muted),
          onPressed: () => AuthStore.I.logout(),
        ),
        const SizedBox(width: 4),
        // 头像 (点击进「我的」), 左侧 1px 分隔线
        Container(width: 1, height: 24, color: Mc.hairline),
        const SizedBox(width: 12),
          const _AvatarButton(),
        ]),
      );
  }
}

/// 顶栏标题旁 STATUS: LIVE FEED 状态片 (对齐 web)。
class _StatusChip extends StatelessWidget {
  const _StatusChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Mc.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Mc.hairline),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
              color: Mc.bull, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('STATUS: LIVE FEED', style: Mc.mono(11, color: Mc.muted)),
      ]),
    );
  }
}

/// 顶栏右侧头像: 方形圆角 + 姓名前两字符, 点击推入「我的」覆盖页。
class _AvatarButton extends StatelessWidget {
  const _AvatarButton();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthStore.I,
      builder: (context, _) {
        final name = AuthStore.I.displayName;
        final text = name.isEmpty
            ? 'M'
            : name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
        return Tooltip(
          message: name.isEmpty ? '我的' : name,
          child: InkWell(
            onTap: () =>
                ShellRouter.I.push('我的', 'PROFILE', const ProfilePage()),
            borderRadius: BorderRadius.circular(6),
            hoverColor: Mc.cardHigh,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Mc.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Mc.hairline),
              ),
              child: Text(text,
                  style: Mc.mono(12,
                      w: FontWeight.w700, color: Mc.cobaltSoft)),
            ),
          ),
        );
      },
    );
  }
}

/// 顶栏通知铃铛 + 红点 + 下拉面板 (对齐 web 通知待办):
/// ApiClient.I.newsList({'limit': 6}) 取前 6 条, 首次打开才拉取;
/// 下拉用 OverlayEntry, 点击遮罩 (面板外部) 关闭;
/// 点条目推入 NewsArticleOverlay 全屏文章页, 「查看全部」推入资讯页。
class _NotifBell extends StatefulWidget {
  const _NotifBell();

  @override
  State<_NotifBell> createState() => _NotifBellState();
}

class _NotifBellState extends State<_NotifBell> {
  final _link = LayerLink();
  OverlayEntry? _entry;
  List<dynamic> _items = [];
  bool _loading = false;
  bool _loaded = false;
  String? _error;

  void _toggle() {
    if (_entry != null) {
      _close();
      return;
    }
    if (!_loaded && !_loading) _load();
    _entry = _buildEntry();
    Overlay.of(context).insert(_entry!);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  Future<void> _load() async {
    _loading = true;
    _error = null;
    _entry?.markNeedsBuild();
    try {
      final res = await ApiClient.I.newsList({'limit': 6});
      final list = res is Map
          ? (res['items'] ?? res['data'])
          : (res is List ? res : null);
      _items = list is List ? list : [];
      _loaded = true;
    } catch (e) {
      _error = e is ApiException ? e.message : '通知加载失败';
    }
    _loading = false;
    if (mounted) setState(() {});
    _entry?.markNeedsBuild();
  }

  void _openItem(Map n) {
    final id = Fmt.toNum(n['id'])?.toInt();
    _close();
    if (id != null) {
      ShellRouter.I.push('资讯', 'NEWS', NewsArticleOverlay(id: id));
    }
  }

  void _goAllNews() {
    _close();
    ShellRouter.I.push('资讯', 'NEWS', const NewsPage());
  }

  OverlayEntry _buildEntry() {
    return OverlayEntry(builder: (context) {
      return Stack(children: [
        // 全屏透明遮罩: 点击面板外部关闭
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
          ),
        ),
        CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, 10),
          child: Material(
            color: Colors.transparent,
            child: _buildPanel(),
          ),
        ),
      ]);
    });
  }

  Widget _buildPanel() {
    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: Mc.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Mc.hairline),
        boxShadow: const [
          BoxShadow(
              color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // 头部: 标题 + 刷新
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: const BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: Mc.hairline, width: 1))),
          child: Row(children: [
            const Icon(Icons.notifications_outlined,
                size: 16, color: Mc.cobaltSoft),
            const SizedBox(width: 6),
            Text('通知待办', style: Mc.display(13)),
            const Spacer(),
            InkWell(
              onTap: _load,
              borderRadius: BorderRadius.circular(6),
              hoverColor: Mc.cardHigh,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.refresh, size: 15, color: Mc.muted),
              ),
            ),
          ]),
        ),
        // 列表 (限高滚动)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 288),
          child: _loading
              ? _panelMsg('加载中…', Mc.muted)
              : _error != null
                  ? _panelMsg(_error!, Mc.bear)
                  : _items.isEmpty
                      ? _panelMsg('暂无通知', Mc.muted)
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _items.length,
                          separatorBuilder: (_, _) => const Divider(
                              height: 1,
                              color: Mc.hairline,
                              indent: 12,
                              endIndent: 12),
                          itemBuilder: (_, i) =>
                              _notifTile(_items[i] as Map),
                        ),
        ),
        // 底部: 查看全部
        InkWell(
          onTap: _goAllNews,
          hoverColor: Mc.cardHigh,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: const BoxDecoration(
                border:
                    Border(top: BorderSide(color: Mc.hairline, width: 1))),
            alignment: Alignment.center,
            child: Text('查看全部',
                style: Mc.tag(color: Mc.cobaltSoft)),
          ),
        ),
      ]),
    );
  }

  Widget _panelMsg(String msg, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(child: Text(msg, style: Mc.mono(11, color: color))),
    );
  }

  Widget _notifTile(Map n) {
    return InkWell(
      onTap: () => _openItem(n),
      hoverColor: Mc.cardHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                  color: Mc.cobalt, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(Fmt.ago(n['publish_at']),
                style: Mc.mono(10, color: Mc.muted)),
          ]),
          const SizedBox(height: 3),
          Text(n['title']?.toString() ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Mc.body(12)),
        ]),
      ),
    );
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(6),
        hoverColor: Mc.cardHigh,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Stack(clipBehavior: Clip.none, children: [
            Icon(Icons.notifications_outlined,
                size: 20,
                color: _entry != null ? Mc.ink : Mc.muted),
            // 红点: 有通知时显示 (对齐 web)
            if (_items.isNotEmpty)
              Positioned(
                top: -1,
                right: -1,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Mc.bear,
                    shape: BoxShape.circle,
                    border: Border.all(color: Mc.canvas, width: 1.5),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// 顶栏全局搜索框: 回车或点右侧提交图标, 推入搜索结果覆盖页。
/// 提交后清空输入, 空串不触发。
class _SearchBox extends StatefulWidget {
  const _SearchBox();

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit([String? _]) {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    ShellRouter.I.push('搜索', 'SEARCH', SearchResultsPage(query: q));
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return McInput(
      controller: _ctrl,
      hint: '搜索币种 / 资讯',
      prefix: Icons.search,
      height: 36,
      onSubmitted: _submit,
      suffix: InkWell(
        onTap: _submit,
        borderRadius: BorderRadius.circular(6),
        hoverColor: Mc.cardHigh,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Icon(Icons.east, size: 15, color: Mc.cobaltSoft),
        ),
      ),
    );
  }
}
