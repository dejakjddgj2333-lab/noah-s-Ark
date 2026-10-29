/* 生成《诺亚方舟运营后台操作手册》.docx */
const fs = require('fs')
const path = require('path')
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, ImageRun,
  Header, Footer, AlignmentType, LevelFormat, HeadingLevel, BorderStyle,
  WidthType, ShadingType, PageNumber, PageBreak, TableOfContents,
} = require('docx')

const SHOTS = String.raw`C:\Users\other8080\Videos\project\hk\shots_admin`
const OUT = String.raw`C:\Users\other8080\Videos\project\hk\docs\明策运营后台操作手册.docx`

const FONT = 'Microsoft YaHei'
const BLUE = '2E5BFF'
const GRAY = '595959'
const CONTENT_W = 9026 // A4, 1 inch margins

// ── helpers ──
const h1 = (text) => new Paragraph({
  heading: HeadingLevel.HEADING_1,
  children: [new TextRun({ text, bold: true, size: 36, font: FONT, color: '1A1A2E' })],
  spacing: { before: 360, after: 240 },
})
const h2 = (text) => new Paragraph({
  heading: HeadingLevel.HEADING_2,
  children: [new TextRun({ text, bold: true, size: 28, font: FONT, color: BLUE })],
  spacing: { before: 300, after: 160 },
})
const h3 = (text) => new Paragraph({
  heading: HeadingLevel.HEADING_3,
  children: [new TextRun({ text, bold: true, size: 24, font: FONT, color: '1A1A2E' })],
  spacing: { before: 220, after: 120 },
})
const p = (text, opts = {}) => new Paragraph({
  children: [new TextRun({ text, size: 21, font: FONT, color: '333333', ...opts })],
  spacing: { after: 120, line: 320 },
})
const bullet = (text, bold = null) => new Paragraph({
  numbering: { reference: 'bullets', level: 0 },
  children: bold
    ? [new TextRun({ text: bold, bold: true, size: 21, font: FONT, color: '333333' }),
       new TextRun({ text, size: 21, font: FONT, color: '333333' })]
    : [new TextRun({ text, size: 21, font: FONT, color: '333333' })],
  spacing: { after: 80, line: 300 },
})
const note = (text) => new Paragraph({
  children: [new TextRun({ text: '注意：', bold: true, size: 21, font: FONT, color: 'B45309' }),
             new TextRun({ text, size: 21, font: FONT, color: 'B45309' })],
  spacing: { after: 160, line: 300 },
  shading: { fill: 'FFF7E8', type: ShadingType.CLEAR },
  border: { left: { style: BorderStyle.SINGLE, size: 18, color: 'F0A020' } },
  indent: { left: 160 },
})
const shot = (file, caption, w = 600) => {
  const data = fs.readFileSync(path.join(SOTS_DIR, file))
  const hpx = Math.round((w * 9) / 16)
  return [
    new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [new ImageRun({
        type: 'png', data,
        transformation: { width: w, height: hpx },
        altText: { title: caption, description: caption, name: file },
      })],
      spacing: { before: 120, after: 60 },
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [new TextRun({ text: caption, size: 18, font: FONT, color: GRAY, italics: true })],
      spacing: { after: 240 },
    }),
  ]
}
const SOTS_DIR = SHOTS

const cellBorder = { style: BorderStyle.SINGLE, size: 4, color: 'C9D2E8' }
const borders = { top: cellBorder, bottom: cellBorder, left: cellBorder, right: cellBorder }
const tcell = (text, width, head = false) => new TableCell({
  borders,
  width: { size: width, type: WidthType.DXA },
  shading: head ? { fill: '2E5BFF', type: ShadingType.CLEAR } : undefined,
  margins: { top: 60, bottom: 60, left: 100, right: 100 },
  children: [new Paragraph({
    children: [new TextRun({
      text, size: 20, font: FONT, bold: head,
      color: head ? 'FFFFFF' : '333333',
    })],
  })],
})
const makeTable = (widths, rows) => new Table({
  width: { size: CONTENT_W, type: WidthType.DXA },
  columnWidths: widths,
  rows: rows.map((r, i) => new TableRow({
    children: r.map((c, j) => tcell(c, widths[j], i === 0)),
  })),
})

const children = []

// ── 封面 ──
children.push(
  new Paragraph({ spacing: { before: 3600 } }),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: '明策运营后台', bold: true, size: 56, font: FONT, color: '1A1A2E' })],
    spacing: { after: 200 },
  }),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: '操 作 手 册', bold: true, size: 44, font: FONT, color: BLUE })],
    spacing: { after: 600 },
  }),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: '链上资产 · 邀请返佣 · 运营管理平台', size: 24, font: FONT, color: GRAY })],
    spacing: { after: 2400 },
  }),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: '文档版本：V1.0', size: 22, font: FONT, color: GRAY })],
    spacing: { after: 120 },
  }),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: '编制日期：2026 年 10 月 19 日', size: 22, font: FONT, color: GRAY })],
    spacing: { after: 120 },
  }),
  new Paragraph({
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: '适用对象：平台运营、财务、客服及系统管理员', size: 22, font: FONT, color: GRAY })],
  }),
  new Paragraph({ children: [new PageBreak()] }),
)

// ── 目录 (静态: WPS/Word 均直接可见, 不依赖域更新) ──
const TOC = [
  ['1. 系统概述', ['1.1 功能模块总览', '1.2 安全要求']],
  ['2. 登录与全局界面', ['2.1 登录', '2.2 全局界面']],
  ['3. 仪表盘', ['3.1 统计卡片', '3.2 图表']],
  ['4. 用户管理', ['4.1 查询用户', '4.2 用户档案', '4.3 冻结 / 解冻', '4.4 余额调整（调账）', '4.5 更多操作']],
  ['5. 资金管理', ['5.1 充值记录', '5.2 充值地址池', '5.3 资金归集', '5.4 提现审核']],
  ['6. 运营管理', ['6.1 产品管理', '6.2 购买订单', '6.3 举报管理']],
  ['7. 系统管理', ['7.1 管理员管理', '7.2 角色权限', '7.3 协议管理', '7.4 功能开关', '7.5 参数配置']],
  ['8. 附录', ['8.1 内置角色权限对照', '8.2 操作权限一览', '8.3 常见问题']],
]
children.push(
  new Paragraph({
    alignment: AlignmentType.CENTER,
    children: [new TextRun({ text: '目  录', bold: true, size: 32, font: FONT })],
    spacing: { after: 360 },
  }),
  ...TOC.flatMap(([c1, subs]) => [
    new Paragraph({
      children: [new TextRun({ text: c1, bold: true, size: 24, font: FONT, color: '1A1A2E' })],
      spacing: { before: 160, after: 100, line: 320 },
    }),
    ...subs.map((s2) => new Paragraph({
      children: [new TextRun({ text: s2, size: 21, font: FONT, color: '555555' })],
      indent: { left: 480 },
      spacing: { after: 60, line: 300 },
    })),
  ]),
  new Paragraph({ children: [new PageBreak()] }),
)

// ── 1 系统概述 ──
children.push(
  h1('1. 系统概述'),
  p("明策运营后台是平台的统一管理端，覆盖用户、资金、运营、系统四大管理域。后台账号体系与 App 注册用户完全隔离，采用「角色 + 权限」的访问控制：页面权限控制菜单可见性，操作权限控制按钮可用性；未授权的菜单与按钮自动隐藏。"),
  h2('1.1 功能模块总览'),
  makeTable([2200, 3413, 3413], [
    ['模块分组', '包含页面', '主要用途'],
    ['概览', '仪表盘', '运营核心指标、趋势图表实时监控'],
    ['用户', '用户管理', '用户查询、档案、冻结、调账、改绑、删除'],
    ['资金', '充值记录 / 充值地址池 / 资金归集 / 提现审核', '链上充值监控、地址池维护、资金归集、提现打款审核'],
    ['运营', '产品管理 / 购买订单 / 举报管理', '理财产品上下架、订单与佣金查看、用户举报处理'],
    ['系统', '管理员管理 / 角色权限 / 协议管理 / 功能开关 / 参数配置', '账号与权限治理、法务文档发布、运行参数热更新'],
  ]),
  new Paragraph({ spacing: { after: 160 } }),
  h2('1.2 安全要求'),
  bullet('除内置 admin 外，所有管理员必须绑定谷歌验证器（TOTP）后才能登录后台。'),
  bullet('登录页第三栏为谷歌验证码，已绑定验证器的管理员登录时必填。'),
  bullet('调账、删除、归集等敏感操作均记入审计日志，操作人可追溯。'),
  new Paragraph({ children: [new PageBreak()] }),
)

// ── 2 登录与全局界面 ──
children.push(
  h1('2. 登录与全局界面'),
  h2('2.1 登录'),
  p('打开后台地址，进入登录页。输入用户名、密码；已绑定谷歌验证器的账号还需填写当前 6 位动态码，点击「登录」。'),
  ...shot('00_login.png', '图 2-1  登录页'),
  bullet('首次登录且未绑定谷歌验证的账号，系统将强制跳转至绑定页：用 Google Authenticator（或任意 TOTP 应用）扫码或手动输入密钥，再输入 App 显示的 6 位动态码完成绑定。'),
  bullet('登录失败、验证码错误会以红色气泡提示具体原因。'),
  h2('2.2 全局界面'),
  p('登录后进入主界面。左侧为功能菜单（按「概览 / 用户 / 资金 / 运营 / 系统」五组归类，无权限的菜单自动隐藏）；顶部为面包屑与工具区。'),
  bullet('全局搜索：', '顶栏搜索框输入功能名称，回车直达对应页面。'),
  bullet('通知铃铛：', '有待审核提现时亮红点，点击直达提现审核页。'),
  bullet('主题切换：', '太阳/月亮图标切换明暗主题，偏好自动记忆。'),
  bullet('账号区：', '显示用户名与角色标签，下拉菜单可退出登录。'),
  new Paragraph({ children: [new PageBreak()] }),
)

// ── 3 仪表盘 ──
children.push(
  h1('3. 仪表盘'),
  p('仪表盘是运营概况看板，实时统计系统用户、资金流转与订单动态。页头固定显示结算通证说明（USDT，TRC20/ERC20），右上角「刷新数据」可随时拉取最新统计。'),
  ...shot('01_dashboard.png', '图 3-1  仪表盘'),
  h2('3.1 统计卡片'),
  makeTable([2600, 6426], [
    ['卡片', '说明'],
    ['总用户数', '累计注册用户，附周环比（近 7 天新增 vs 前 7 天）'],
    ['今日新增用户', '当日注册数，附与昨日对比'],
    ['今日入账 (USDT)', '当日链上充值入账合计'],
    ['累计入账 (USDT)', '历史总链上充值汇总'],
    ['待审核提现', '待办审核笔数；有待办时红色警示'],
    ['订单总额 (USDT)', '全部产品订单金额合计（核心营运指标）'],
    ['在售产品', '当前上架销售中的产品数'],
  ]),
  new Paragraph({ spacing: { after: 160 } }),
  h2('3.2 图表'),
  bullet('近 14 天趋势：', '新增用户与入账 USDT 双轴折线。'),
  bullet('近 14 天订单金额：', '每日下单金额柱状图。'),
  bullet('入账网络分布：', 'TRC20 / ERC20 / BEP20 / Arbitrum 环形占比。'),
  bullet('提现状态分布：', '待审核 / 已打款 / 已拒绝环形占比。'),
  new Paragraph({ children: [new PageBreak()] }),
)

// ── 4 用户管理 ──
children.push(
  h1('4. 用户管理'),
  p('用于用户查询、档案调阅、冻结/解冻、余额调整及账号维护。页头显示用户总数与冻结数。'),
  ...shot('02_users.png', '图 4-1  用户管理列表'),
  h2('4.1 查询用户'),
  p('在搜索框输入用户名或邮箱关键字，回车或点「搜索」；「重置」清空条件。列表展示状态、VIP/团队等级、本金余额、收益余额、处理中金额与注册时间。'),
  h2('4.2 用户档案'),
  p('点击行内「档案」，右侧滑出该用户的全量只读档案：基本信息（邀请码、上级、VIP/持仓、团队）、以及订单、充值、收益结算、佣金、提现、资金明细、等级变动七个标签页。'),
  ...shot('d_user_profile.png', '图 4-2  用户全量档案（只读）'),
  h2('4.3 冻结 / 解冻'),
  p('点击「冻结」并二次确认后，该用户立即无法登录与交易；已冻结用户按钮变为「解冻」，操作后恢复正常。需要权限「用户管理 · 冻结/解冻」。'),
  h2('4.4 余额调整（调账）'),
  p('点击「调账」，在弹窗中选择账户（本金 / 收益）、填写金额（正数=加，负数=减，不能为 0）与调整原因（必填，记入审计日志），提交前需二次确认金额与账户。需要权限「用户管理 · 余额调整」。'),
  ...shot('d_user_adjust.png', '图 4-3  余额调整弹窗'),
  h2('4.5 更多操作'),
  p('「更多」下拉菜单提供：'),
  bullet('重置密码：', '为用户设置新密码（至少 6 位）。需要权限「用户管理 · 重置密码」。'),
  bullet('改绑邮箱/上级：', '修改邮箱，或填写新上级邀请码改绑推荐关系（留空不改）。需要权限「用户管理 · 改绑邮箱/上级」。'),
  bullet('删除空账户：', '仅当本金/收益余额与处理中金额全为 0 时出现；物理删除不可恢复，服务端二次校验。需要权限「用户管理 · 删除空账户」。'),
  note('调账必须填写原因并记入审计日志；仅空账户可删除。'),
  new Paragraph({ children: [new PageBreak()] }),
)

// ── 5 资金管理 ──
children.push(
  h1('5. 资金管理'),
  h2('5.1 充值记录'),
  p('链上充值入账监控页（只读）。顶部五张概览卡：今日入账、确认中笔数、异常待处理、地址池空闲、地址池已分配；页头常驻「链上监控运行中」，有异常时红点亮出「异常 N 笔」。'),
  ...shot('03_deposit_records.png', '图 5-1  充值记录'),
  p('可按状态（确认中 / 已入账 / 异常待处理）、网络（TRC20）、用户名组合查询；表格展示充值地址、txid、金额、区块确认数进度（当前/所需）、区块时间与入账时间，支持 20/50/100 条分页。'),
  h2('5.2 充值地址池'),
  p('维护充值地址池水位。可按网络（TRC20 / ERC20 / BEP20 / Arbitrum）与状态（空闲 / 已分配）筛选，查看每个地址的分配用户与分配时间。'),
  ...shot('04_deposit_addresses.png', '图 5-2  充值地址池'),
  p('生成地址：在右上角选择网络、填写数量（1~200），点击「生成地址」，成功后提示已生成数量。需要权限「充值地址池 · 生成地址」。'),
  note('地址池水位不足时用户充值会分配失败，请保持空闲地址充足；生成地址仅补充所选网络。'),
  new Paragraph({ children: [new PageBreak()] }),
  h2('5.3 资金归集'),
  p('将分散在用户充值子地址中的 USDT 归拢到平台主钱包。页面分三区：主钱包设置卡（每条链一张）、地址余额表、归集记录。'),
  ...shot('05_sweep.png', '图 5-3  资金归集'),
  h3('5.3.1 配置主钱包'),
  p('支持 TRC20 / ERC20 / BEP20 / Arbitrum 四条网络。未配置的卡片显示「待设置主钱包」，点击「立即配置主钱包」（或已配置卡的「设置 / 修改」），在弹窗中填写主钱包归集地址与归集阈值（地址余额达到该值才归集，默认 500 USDT）。卡片同时展示主钱包 USDT 余额与 Gas 储备池状态（充足/不足），并提供区块链浏览器跳转。需要权限「资金归集 · 设置主钱包/阈值」。'),
  h3('5.3.2 执行归集'),
  bullet('一键归集达阈值地址：', '二次确认后归集当前网络所有达阈值地址；缺 Gas 的地址自动跳过并标记，结束后提示「成功 / 缺gas / 失败 / 跳过」数量。需要权限「资金归集 · 执行归集」。'),
  bullet('单个归集：', '行内「归集」按钮单独归集该地址；低于阈值的行显示「强制归集」。缺 Gas 时提示先手动补 Gas。'),
  bullet('归集状态：', '可归集（绿色）、等待补 Gas（黄色）、低于阈值（灰色），按余额与 Gas 自动判定。'),
  h3('5.3.3 归集记录'),
  p('实时跟踪链上打包状态，可按全部 / 已成功 / 缺 Gas / 失败筛选；展示来源地址、主钱包、金额、状态、TXID（或错误信息）、操作人与时间。「导出记录」可将当前筛选结果导出为 CSV 文件。'),
  note('只显示有余额的地址；缺 Gas 的地址需手动补 Gas 后再单独或批量归集。'),
  new Paragraph({ children: [new PageBreak()] }),
  h2('5.4 提现审核'),
  p('处理用户提现申请，默认展示「待审核」队列（页头显示待办笔数），可切换已打款 / 已拒绝 / 全部。列表展示申请人与时间、账户类型（本金/收益）、金额与费用（服务费、网络费）、实际到账、网络、提现地址与状态。'),
  ...shot('06_withdrawal.png', '图 5-4  提现审核'),
  bullet('通过：', '弹窗确认金额，可填写打款交易号 txid（可选，允许稍后补录），确认后状态变为「已打款」。'),
  bullet('拒绝：', '弹窗填写拒绝原因，确认后金额与费用全额退回用户账户，状态变为「已拒绝」。'),
  p('两个操作均需权限「提现审核 · 审核通过/拒绝」；已处理记录显示「已结案」，不可重复操作。'),
  note('通过后请尽快链上打款并补录 TXID；拒绝会将金额与费用全额退回用户账户。'),
  new Paragraph({ children: [new PageBreak()] }),
)

// ── 6 运营管理 ──
children.push(
  h1('6. 运营管理'),
  h2('6.1 产品管理'),
  p('理财产品的配置与上下架管理。页头显示在售数与总数，可按全部 / 已上架 / 草稿 / 已下架筛选。列表展示产品名称与额度区间、基础日收益率、周期与返还方式、VIP 门槛、团队门槛与状态。'),
  ...shot('07_product.png', '图 6-1  产品管理'),
  h3('6.1.1 新建 / 编辑产品'),
  p('点击「新建产品」，在弹窗中填写：产品名称（必填）、描述、基础日收益率（小数，如 0.02 = 2%/日）、周期天数（1~3650）、返还方式（每满24小时 / 每隔7天 / 每隔30天 / 到期一次性 / 每小时测试）、最低与最高购买金额、个人 VIP 门槛（0~10，留空不限）、团队等级门槛（0~10，留空不限）。保存后产品为「草稿」状态，上架后 APP 才可见。已上架产品不可编辑。需要权限「产品管理 · 新建/编辑/上下架」。'),
  ...shot('d_product_new.png', '图 6-2  新建产品弹窗'),
  h3('6.1.2 上架 / 下架 / 删除'),
  bullet('上架：', '确认后执行完整参数校验，校验通过即上架、APP 可见可购。'),
  bullet('下架：', '下架后 APP 不可再购买，存量订单继续正常结算。'),
  bullet('删除：', '物理删除不可恢复；已上架产品删除后立即从 APP 消失，存量订单按购买时快照继续结算。有订单的产品不可删除。需要权限「产品管理 · 删除产品」。'),
  new Paragraph({ children: [new PageBreak()] }),
  h2('6.2 购买订单'),
  p('申购订单的只读视图，支持按用户名与状态（生效中 / 已完成）查询。列表展示产品、金额、日化率（含锁定加成时标注「基础+加成」）、周期/返还、结算进度（已结/总期）、已产生收益、已返本金、佣金支出与购买时间。'),
  ...shot('08_order.png', '图 6-3  购买订单'),
  p('点击「收益明细」弹窗查看该订单的逐期结算表（期数、收益、返本、应结算时点、实际入账）与触发的佣金支出表（接收人及代数、比例、佣金基数、佣金、入账时间）。'),
  h2('6.3 举报管理'),
  p('处理 App 内用户举报。可按全部 / 待处理 / 已处理 / 已驳回筛选；列表展示举报双方、举报原因（垃圾信息 / 辱骂骚扰 / 诈骗 / 色情内容 / 其他）、类型（评论 / 消息 / 用户）、相关内容与补充说明。'),
  ...shot('09_reports.png', '图 6-4  举报管理'),
  bullet('删评论 / 删消息：', '立即移除违规内容（针对内容类举报）。'),
  bullet('封号：', '封禁被举报用户，封号后无法登录。'),
  bullet('驳回：', '举报不成立，直接结案。'),
  p('以上操作均需权限「举报管理 · 处理举报」，处理后显示「已结案」。'),
  new Paragraph({ children: [new PageBreak()] }),
)

// ── 7 系统管理 ──
children.push(
  h1('7. 系统管理'),
  h2('7.1 管理员管理'),
  p('管理后台账号（与 App 用户完全隔离）。列表展示角色、谷歌验证绑定状态、账号状态与创建时间；页头对未绑谷歌验证的人数给出警示。全部操作需权限「管理员管理 · 绑定/改角色/移除」。'),
  ...shot('10_admins.png', '图 7-1  管理员管理'),
  h3('7.1.1 新建管理员'),
  p('点击「新建管理员」，填写用户名（至少 3 位，字母/数字/下划线）、初始密码（至少 8 位）并选择角色。创建后请立即在列表中点「绑定验证」为其完成谷歌验证绑定——未绑定无法登录。'),
  ...shot('d_admin_new.png', '图 7-2  新建管理员弹窗'),
  h3('7.1.2 账号维护'),
  bullet('绑定验证 / 重置验证：', '绑定弹窗展示二维码与手动密钥，输入验证器 6 位动态码确认；已绑定账号可「重置验证」，重置后下次登录需重新绑定。'),
  bullet('重置密码：', '设置新密码（至少 8 位）。'),
  bullet('改角色：', '变更该管理员的角色，权限随角色即时调整。'),
  bullet('禁用 / 启用：', '禁用后该账号无法登录后台；不能禁用自己。'),
  bullet('删除：', '删除后无法登录后台；不能删除自己。'),
  note('内置 admin 账号不可改角色、禁用、删除，也无需绑定谷歌验证。'),
  new Paragraph({ children: [new PageBreak()] }),
  h2('7.2 角色权限'),
  p('定义角色并分配权限。列表展示每个角色的权限集合；超级管理员拥有「全部权限」。操作需权限「角色权限 · 新建/编辑/删除」。'),
  ...shot('11_roles.png', '图 7-3  角色权限'),
  p('点击「新建角色」，填写角色名并在权限树中勾选页面权限与按钮权限（父节点支持半选）；「编辑」可回显并调整既有角色的权限；「删除」移除角色。'),
  ...shot('d_role_new.png', '图 7-4  新建角色弹窗'),
  note('内置「超级管理员」角色不可编辑/删除；删除角色前请确认无管理员仍绑定该角色。'),
  h2('7.3 协议管理'),
  p('维护「隐私政策」与「用户协议」两份公开法务文档。支持富文本与 HTML 源码两种编辑模式；点击「保存发布」即时生效。公开访问地址为 /api/legal/privacy 与 /api/legal/terms（无需登录，正文自动套用带暗色适配的标准页面外壳）。需要权限「协议管理 · 编辑协议」。'),
  ...shot('12_legal.png', '图 7-5  协议管理'),
  new Paragraph({ children: [new PageBreak()] }),
  h2('7.4 功能开关'),
  p('控制 App 端功能入口的运行时开关，拨动即保存、即时生效，页头显示「开启 N / 共 M 项」。需要权限「功能开关 · 修改开关」。'),
  ...shot('13_features.png', '图 7-6  功能开关'),
  note('充值/提现涉及资金合规资质，开启前请确认已取得相应资质；未开启时 App 内隐藏对应入口。标记「编译期控制」的开关（充值/理财显隐）已改为编译期常量，此处切换不生效。'),
  h2('7.5 参数配置'),
  p('运行参数热更新，按「收益转本金 / 提现 / 限流」三组展示。每项参数标注说明、允许范围与默认值；被后台覆盖的参数标「改」字标签。需要权限「参数配置 · 保存参数」。'),
  ...shot('14_config.png', '图 7-7  参数配置'),
  bullet('修改参数：', '直接在输入框编辑，改动过的输入框高亮，「保存修改」按钮显示待存项数。'),
  bullet('保存：', '弹出「名称：旧值 → 新值」确认清单，确认后立即生效，无需重启。'),
  bullet('还原修改：', '放弃全部未保存的编辑，重新拉取当前生效值。'),
  new Paragraph({ children: [new PageBreak()] }),
)

// ── 8 附录 ──
children.push(
  h1('8. 附录'),
  h2('8.1 内置角色权限对照'),
  p('系统预置四个角色。超级管理员不可编辑/删除；其余角色可在「角色权限」页调整或删除（删除前需确认无管理员绑定）。'),
  makeTable([1600, 2200, 5226], [
    ['角色', '定位', '拥有权限'],
    ['超级管理员', '系统管理', '全部权限（含删除空账户、删除产品、参数配置、角色与管理员治理等高危操作）'],
    ['运营', '日常运营', '仪表盘；用户管理（冻结/解冻、余额调整、重置密码、改绑邮箱/上级）；产品管理（新建/编辑/上下架）；购买订单'],
    ['财务', '资金结算', '仪表盘；充值记录；充值地址池（生成地址）；资金归集（执行归集）；提现审核（审核通过/拒绝）；购买订单；参数配置（仅查看）'],
    ['客服', '查询支持', '仪表盘；用户管理（仅查看）；充值记录（仅查看）'],
  ]),
  new Paragraph({ spacing: { after: 200 } }),
  h2('8.2 操作权限一览'),
  p('页面权限与页面同名（控制菜单可见性），下表列出各页面下的操作权限（控制按钮可用性）。无对应权限的账号看不到按钮，调用接口也会被服务端拒绝。'),
  makeTable([2600, 3300, 3126], [
    ['所属页面', '权限名称', '对应操作'],
    ['用户管理', '冻结/解冻', '冻结或恢复用户账号'],
    ['用户管理', '余额调整', '人工调账（本金/收益，记审计日志）'],
    ['用户管理', '重置密码', '为用户设置新密码'],
    ['用户管理', '改绑邮箱/上级', '修改邮箱、改绑推荐上级'],
    ['用户管理', '删除空账户', '物理删除零余额账户（默认仅超管）'],
    ['充值地址池', '生成地址', '批量生成充值地址'],
    ['资金归集', '设置主钱包/阈值', '配置归集目标地址与触发阈值'],
    ['资金归集', '执行归集', '单个/批量归集子地址资金'],
    ['提现审核', '审核通过/拒绝', '提现打款通过或拒绝退款'],
    ['产品管理', '新建/编辑/上下架', '产品全生命周期管理'],
    ['产品管理', '删除产品', '物理删除产品（默认仅超管）'],
    ['举报管理', '处理举报', '删内容、封号、驳回'],
    ['管理员管理', '绑定/改角色/移除', '管理员账号全部维护操作'],
    ['角色权限', '新建/编辑/删除', '角色定义与权限分配'],
    ['协议管理', '编辑协议', '隐私政策/用户协议保存发布'],
    ['功能开关', '修改开关', 'App 功能入口开关切换'],
    ['参数配置', '保存参数', '运行参数热更新'],
  ]),
  new Paragraph({ spacing: { after: 200 } }),
  h2('8.3 常见问题'),
  h3('Q1：新管理员登录不上？'),
  p('除 admin 外，管理员必须先绑定谷歌验证器才能登录。请超管在「管理员管理」中为其点「绑定验证」，扫码并完成动态码确认。'),
  h3('Q2：用户反馈充值没到账？'),
  p('先在「充值记录」按用户名查询：确认中=等待区块确认数达标；异常待处理=金额或地址匹配异常，需技术核查；同时检查「充值地址池」空闲水位是否充足。'),
  h3('Q3：归集提示缺 Gas？'),
  p('归集子地址需要原生币（TRX/ETH/BNB）支付矿工费。向缺 Gas 的地址手动转入少量对应原生币后，再执行单个或一键归集。'),
  h3('Q4：调账后用户说金额不对？'),
  p('调账记录可在「用户管理 → 档案 → 资金明细」中核查（类型为「人工调整」），每次调账均带操作人与原因，便于对账追责。'),
)

const doc = new Document({
  creator: 'MINGCE Ops',
  title: '明策运营后台操作手册',
  styles: {
    default: { document: { run: { font: FONT, size: 21 } } },
    paragraphStyles: [
      { id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { size: 36, bold: true, font: FONT, color: '1A1A2E' },
        paragraph: { spacing: { before: 360, after: 240 }, outlineLevel: 0 } },
      { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { size: 28, bold: true, font: FONT, color: BLUE },
        paragraph: { spacing: { before: 300, after: 160 }, outlineLevel: 1 } },
      { id: 'Heading3', name: 'Heading 3', basedOn: 'Normal', next: 'Normal', quickFormat: true,
        run: { size: 24, bold: true, font: FONT, color: '1A1A2E' },
        paragraph: { spacing: { before: 220, after: 120 }, outlineLevel: 2 } },
    ],
  },
  numbering: {
    config: [
      { reference: 'bullets',
        levels: [{ level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 520, hanging: 260 } } } }] },
    ],
  },
  sections: [{
    properties: {
      page: {
        size: { width: 11906, height: 16838 },
        margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 },
      },
    },
    headers: {
      default: new Header({
        children: [new Paragraph({
          alignment: AlignmentType.RIGHT,
          children: [new TextRun({ text: '明策运营后台 · 操作手册', size: 16, font: FONT, color: '999999' })],
        })],
      }),
    },
    footers: {
      default: new Footer({
        children: [new Paragraph({
          alignment: AlignmentType.CENTER,
          children: [
            new TextRun({ text: '第 ', size: 16, font: FONT, color: '999999' }),
            new TextRun({ children: [PageNumber.CURRENT], size: 16, font: FONT, color: '999999' }),
            new TextRun({ text: ' 页', size: 16, font: FONT, color: '999999' }),
          ],
        })],
      }),
    },
    children,
  }],
})

Packer.toBuffer(doc).then((buf) => {
  fs.writeFileSync(OUT, buf)
  console.log('written:', OUT, (buf.length / 1024).toFixed(0), 'KB')
})
