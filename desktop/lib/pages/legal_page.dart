import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/kit.dart';

/// 法务文档页：服务条款 / 隐私政策 / 监管披露，按 kind 切换。
/// kind: terms / privacy / disclosure
class LegalPage extends StatelessWidget {
  const LegalPage({super.key, this.kind = 'terms'});
  final String kind;

  static const _docs = {
    'terms': _Doc(
      title: '服务条款',
      en: 'TERMS OF SERVICE',
      updated: '2025-01-01',
      sections: [
        _Section('1. 服务说明',
            '明策 MINGCE 终端（下称"本终端"）为机构级行情情报工具，提供多维行情数据、巨鲸动向监测、爆仓预警、资金费率分析及行业资讯聚合服务。本终端仅提供信息展示与分析工具，不构成任何投资建议。'),
        _Section('2. 账号与访问',
            '账号仅限本人使用，不得转让、共享或出借。您对账号下的一切操作负责。发现未授权访问应立即通知平台。平台有权对异常账号采取限制、冻结或注销措施。'),
        _Section('3. 数据与免责',
            '行情数据来源于第三方交易所及公开数据渠道，平台尽力保证数据及时性与准确性，但不对因数据延迟、错误或中断造成的任何损失承担责任。数字资产交易风险极高，据此操作，风险自担。'),
        _Section('4. 禁止行为',
            '禁止利用本终端从事任何违法违规活动，包括但不限于：爬取或转售平台数据、干扰服务正常运行、发布违法信息、洗钱及其他金融犯罪行为。'),
        _Section('5. 条款变更',
            '平台保留随时修订本条款的权利，修订后将在终端内公示。继续使用本终端即视为接受修订后的条款。'),
      ],
    ),
    'privacy': _Doc(
      title: '隐私政策',
      en: 'PRIVACY POLICY',
      updated: '2025-01-01',
      sections: [
        _Section('1. 信息收集',
            '我们收集您注册时提供的账号信息（用户名、邮箱）、登录日志及终端使用偏好设置（如自选列表、界面偏好），偏好类数据仅存储于您的本地浏览器。'),
        _Section('2. 信息使用',
            '收集的信息仅用于：账号身份验证、服务安全保障、产品功能改进。我们不会向任何第三方出售您的个人信息。'),
        _Section('3. 信息保护',
            '传输层采用 AES-256 GCM 加密协议，凭据经哈希处理后存储。平台部署访问控制、入侵检测等安全措施保护您的数据。'),
        _Section('4. Cookie 与本地存储',
            '本终端使用浏览器本地存储（localStorage）保存登录凭据与界面偏好，不用于跨站追踪。清除浏览器数据将同时清除这些信息。'),
        _Section('5. 您的权利',
            '您有权查询、更正、删除您的个人信息，或注销账号。相关操作可在"个人中心"发起，或联系客服协助处理。'),
      ],
    ),
    'disclosure': _Doc(
      title: '监管披露',
      en: 'REGULATORY DISCLOSURE',
      updated: '2025-01-01',
      sections: [
        _Section('1. 风险提示',
            '数字资产价格波动剧烈，存在极高的投资风险。过往表现不代表未来收益。您可能在短时间内损失全部本金。请在充分了解风险后审慎决策。'),
        _Section('2. 非投资建议',
            '本终端提供的所有行情数据、分析指标、资讯内容仅供参考，不构成任何形式的投资要约、要约邀请或交易建议。'),
        _Section('3. 司法辖区限制',
            '本终端服务不面向禁止数字资产相关服务的司法辖区用户。您有责任确认在所在辖区使用本服务合法合规。'),
        _Section('4. 数据合规',
            '平台遵循适用数据保护法规处理用户数据，详情见《隐私政策》。监管机构依法调取时，平台将按法律要求配合。'),
      ],
    ),
  };

  @override
  Widget build(BuildContext context) {
    final doc = _docs[kind] ?? _docs['terms']!;
    return Scaffold(
      body: Column(children: [
        _TopBar(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doc.en, style: Mc.tag(color: Mc.muted)),
                    const SizedBox(height: 8),
                    Text(doc.title, style: Mc.display(24, w: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('更新日期: ${doc.updated}',
                        style: Mc.mono(11, color: Mc.muted)),
                    const SizedBox(height: 24),
                    for (final s in doc.sections) ...[
                      McCard(
                        color: Mc.surface,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.h, style: Mc.display(15)),
                            const SizedBox(height: 8),
                            Text(s.p, style: Mc.body(13, color: Mc.muted)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    const SizedBox(height: 8),
                    Container(height: 1, color: Mc.hairline),
                    const SizedBox(height: 16),
                    Wrap(spacing: 24, children: [
                      for (final entry in _docs.entries)
                        if (entry.key != kind)
                          GestureDetector(
                            onTap: () => Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                    builder: (_) => LegalPage(kind: entry.key))),
                            child: Text(entry.value.title,
                                style: Mc.body(12,
                                    w: FontWeight.w600, color: Mc.cobaltSoft)),
                          ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Doc {
  const _Doc(
      {required this.title,
      required this.en,
      required this.updated,
      required this.sections});
  final String title;
  final String en;
  final String updated;
  final List<_Section> sections;
}

class _Section {
  const _Section(this.h, this.p);
  final String h;
  final String p;
}

/// 顶栏：品牌 + 返回。
class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Mc.canvas,
        border: Border(bottom: BorderSide(color: Mc.hairline)),
      ),
      child: Row(children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Mc.card,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Mc.hairline),
          ),
          alignment: Alignment.center,
          child: Text('N',
              style: Mc.display(12, w: FontWeight.w700, color: Mc.cobaltSoft)),
        ),
        const SizedBox(width: 10),
        Text('MINGCE', style: Mc.display(14, w: FontWeight.w700)),
        const SizedBox(width: 8),
        Text('| TERMINAL', style: Mc.tag()),
        const Spacer(),
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.arrow_back, size: 14, color: Mc.cobaltSoft),
            const SizedBox(width: 4),
            Text('返回',
                style: Mc.body(12, w: FontWeight.w600, color: Mc.cobaltSoft)),
          ]),
        ),
      ]),
    );
  }
}
