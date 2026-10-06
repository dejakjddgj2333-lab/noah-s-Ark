/// 页面翻译分组 2: 首页六个子页面
/// (overview / market / terminal / funding / whale / liquidation).
/// 结构: { key: { langCode: text } }.
/// langCode: zh-CN/zh-TW/en/ja/ko/es/pt/hi.
/// 变量用 {n}/{v}/{label} 等占位符, 页面里 replaceAll 注入.
final Map<String, Map<String, String>> table = {
  // ---------------- 共用 ----------------
  'no_data': {
    'zh-CN': '暂无数据', 'zh-TW': '暫無數據', 'en': 'No data',
    'ja': 'データなし', 'ko': '데이터 없음', 'es': 'Sin datos',
    'pt': 'Sem dados', 'hi': 'कोई डेटा नहीं',
  },
  'mkt_loading': {
    'zh-CN': '行情加载中…', 'zh-TW': '行情載入中…', 'en': 'Loading market…',
    'ja': '相場を読み込み中…', 'ko': '시세 로딩 중…', 'es': 'Cargando mercado…',
    'pt': 'Carregando mercado…', 'hi': 'बाज़ार लोड हो रहा है…',
  },
  // ---------------- 情绪等级 (共用 senti_) ----------------
  'senti_extreme_fear': {
    'zh-CN': '极度恐慌', 'zh-TW': '極度恐慌', 'en': 'Extreme Fear',
    'ja': '極度の恐怖', 'ko': '극도의 공포', 'es': 'Miedo extremo',
    'pt': 'Medo extremo', 'hi': 'अत्यंत भय',
  },
  'senti_fear': {
    'zh-CN': '恐慌', 'zh-TW': '恐慌', 'en': 'Fear',
    'ja': '恐怖', 'ko': '공포', 'es': 'Miedo',
    'pt': 'Medo', 'hi': 'भय',
  },
  'senti_neutral': {
    'zh-CN': '中性', 'zh-TW': '中性', 'en': 'Neutral',
    'ja': '中立', 'ko': '중립', 'es': 'Neutral',
    'pt': 'Neutro', 'hi': 'तटस्थ',
  },
  'senti_greed': {
    'zh-CN': '贪婪', 'zh-TW': '貪婪', 'en': 'Greed',
    'ja': '強欲', 'ko': '탐욕', 'es': 'Avaricia',
    'pt': 'Ganância', 'hi': 'लालच',
  },
  'senti_extreme_greed': {
    'zh-CN': '极度贪婪', 'zh-TW': '極度貪婪', 'en': 'Extreme Greed',
    'ja': '極度の強欲', 'ko': '극도의 탐욕', 'es': 'Avaricia extrema',
    'pt': 'Ganância extrema', 'hi': 'अत्यंत लालच',
  },
  // ---------------- 相对时间 (共用 time_) ----------------
  'time_just_now': {
    'zh-CN': '刚刚', 'zh-TW': '剛剛', 'en': 'Just now',
    'ja': 'たった今', 'ko': '방금', 'es': 'Ahora mismo',
    'pt': 'Agora mesmo', 'hi': 'अभी',
  },
  'time_minutes_ago': {
    'zh-CN': '{n}分钟前', 'zh-TW': '{n}分鐘前', 'en': '{n}m ago',
    'ja': '{n}分前', 'ko': '{n}분 전', 'es': 'hace {n} min',
    'pt': 'há {n} min', 'hi': '{n} मिनट पहले',
  },
  'time_hours_ago': {
    'zh-CN': '{n}小时前', 'zh-TW': '{n}小時前', 'en': '{n}h ago',
    'ja': '{n}時間前', 'ko': '{n}시간 전', 'es': 'hace {n} h',
    'pt': 'há {n} h', 'hi': '{n} घंटे पहले',
  },
  'time_days_ago': {
    'zh-CN': '{n}天前', 'zh-TW': '{n}天前', 'en': '{n}d ago',
    'ja': '{n}日前', 'ko': '{n}일 전', 'es': 'hace {n} d',
    'pt': 'há {n} d', 'hi': '{n} दिन पहले',
  },

  // ---------------- home_overview_page ----------------
  'ov_section_assets': {
    'zh-CN': '主流资产速览', 'zh-TW': '主流資產速覽', 'en': 'Major Assets',
    'ja': '主要資産一覧', 'ko': '주요 자산 요약', 'es': 'Activos principales',
    'pt': 'Ativos principais', 'hi': 'प्रमुख एसेट्स',
  },
  'ov_section_whale': {
    'zh-CN': '巨鲸异动速递', 'zh-TW': '巨鯨異動速遞', 'en': 'Whale Alerts',
    'ja': 'クジラ速報', 'ko': '고래 알림', 'es': 'Alertas de ballenas',
    'pt': 'Alertas de baleias', 'hi': 'व्हेल अलर्ट',
  },
  'ov_whale_syncing': {
    'zh-CN': '实时同步中', 'zh-TW': '實時同步中', 'en': 'Syncing live',
    'ja': 'リアルタイム同期中', 'ko': '실시간 동기화 중', 'es': 'Sincronizando',
    'pt': 'Sincronizando', 'hi': 'लाइव सिंक हो रहा है',
  },
  'ov_market_banner': {
    'zh-CN': '全网市场全景', 'zh-TW': '全網市場全景', 'en': 'Global Market Overview',
    'ja': '市場全体の概況', 'ko': '전체 시장 개요', 'es': 'Panorama del mercado',
    'pt': 'Panorama do mercado', 'hi': 'ग्लोबल मार्केट अवलोकन',
  },
  'ov_mcap_24h': {
    'zh-CN': '24H 总市值', 'zh-TW': '24H 總市值', 'en': '24H Market Cap',
    'ja': '24H 時価総額', 'ko': '24H 총 시가총액', 'es': 'Cap. de mercado 24H',
    'pt': 'Cap. de mercado 24H', 'hi': '24H मार्केट कैप',
  },
  'ov_volume_24h': {
    'zh-CN': '24H 成交额', 'zh-TW': '24H 成交額', 'en': '24H Volume',
    'ja': '24H 出来高', 'ko': '24H 거래대금', 'es': 'Volumen 24H',
    'pt': 'Volume 24H', 'hi': '24H वॉल्यूम',
  },
  'ov_long_index': {
    'zh-CN': '多头主导指数', 'zh-TW': '多頭主導指數', 'en': 'Long Dominance',
    'ja': 'ロング優位指数', 'ko': '롱 우위 지수', 'es': 'Dominio long',
    'pt': 'Dominância long', 'hi': 'लॉग डॉमिनेंस',
  },
  'ov_no_assets': {
    'zh-CN': '暂无资产数据', 'zh-TW': '暫無資產數據', 'en': 'No asset data',
    'ja': '資産データなし', 'ko': '자산 데이터 없음', 'es': 'Sin datos de activos',
    'pt': 'Sem dados de ativos', 'hi': 'कोई एसेट डेटा नहीं',
  },
  'ov_no_whale': {
    'zh-CN': '暂无巨鲸异动数据', 'zh-TW': '暫無巨鯨異動數據', 'en': 'No whale activity',
    'ja': 'クジラの動向なし', 'ko': '고래 동향 없음', 'es': 'Sin actividad de ballenas',
    'pt': 'Sem atividade de baleias', 'hi': 'कोई व्हेल गतिविधि नहीं',
  },
  'ov_sentiment_index': {
    'zh-CN': '情绪指数', 'zh-TW': '情緒指數', 'en': 'Sentiment Index',
    'ja': 'センチメント指数', 'ko': '심리 지수', 'es': 'Índice de sentimiento',
    'pt': 'Índice de sentimento', 'hi': 'सेंटिमेंट इंडेक्स',
  },
  'ov_senti_sub': {
    'zh-CN': '实时 · {label}', 'zh-TW': '實時 · {label}', 'en': 'Live · {label}',
    'ja': 'リアルタイム · {label}', 'ko': '실시간 · {label}', 'es': 'En vivo · {label}',
    'pt': 'Ao vivo · {label}', 'hi': 'लाइव · {label}',
  },
  'ov_liq_24h': {
    'zh-CN': '24H 爆仓', 'zh-TW': '24H 爆倉', 'en': '24H Liquidations',
    'ja': '24H 清算', 'ko': '24H 청산', 'es': 'Liquidaciones 24H',
    'pt': 'Liquidações 24H', 'hi': '24H लिक्विडेशन',
  },
  'ov_liq_long_short': {
    'zh-CN': '多 {long} · 空 {short}', 'zh-TW': '多 {long} · 空 {short}',
    'en': 'Long {long} · Short {short}', 'ja': 'ロング {long} · ショート {short}',
    'ko': '롱 {long} · 숏 {short}', 'es': 'Long {long} · Short {short}',
    'pt': 'Long {long} · Short {short}', 'hi': 'लॉन्ग {long} · शॉर्ट {short}',
  },
  'ov_funding_weighted': {
    'zh-CN': '资金费率加权', 'zh-TW': '資金費率加權', 'en': 'Weighted Funding Rate',
    'ja': '加重平均資金調達率', 'ko': '가중 펀딩 비율', 'es': 'Tasa de fondeo ponderada',
    'pt': 'Taxa de funding ponderada', 'hi': 'वेटेड फंडिंग रेट',
  },
  'ov_long_pays': {
    'zh-CN': '多头付费', 'zh-TW': '多頭付費', 'en': 'Longs pay',
    'ja': 'ロングが支払い', 'ko': '롱 지불', 'es': 'Pagan los long',
    'pt': 'Longs pagam', 'hi': 'लॉन्ग भुगतान',
  },
  'ov_short_pays': {
    'zh-CN': '空头付费', 'zh-TW': '空頭付費', 'en': 'Shorts pay',
    'ja': 'ショートが支払い', 'ko': '숏 지불', 'es': 'Pagan los short',
    'pt': 'Shorts pagam', 'hi': 'शॉर्ट भुगतान',
  },
  'ov_settle_8h': {
    'zh-CN': '8H结算', 'zh-TW': '8H結算', 'en': '8H settlement',
    'ja': '8時間決済', 'ko': '8시간 정산', 'es': 'Liquidación 8H',
    'pt': 'Liquidação 8H', 'hi': '8H सेटलमेंट',
  },
  'ov_alt_season': {
    'zh-CN': '山寨季指数', 'zh-TW': '山寨季指數', 'en': 'Altcoin Season Index',
    'ja': 'アルトシーズン指数', 'ko': '알트시즌 지수', 'es': 'Índice de altseason',
    'pt': 'Índice de altseason', 'hi': 'अल्टकॉइन सीज़न इंडेक्स',
  },
  'ov_alt_in_season': {
    'zh-CN': '山寨季进行中', 'zh-TW': '山寨季進行中', 'en': 'Altcoin season in progress',
    'ja': 'アルトシーズン進行中', 'ko': '알트시즌 진행 중', 'es': 'Altseason en curso',
    'pt': 'Altseason em andamento', 'hi': 'अल्ट सीज़न जारी',
  },
  'ov_btc_season': {
    'zh-CN': '比特币季', 'zh-TW': '比特幣季', 'en': 'Bitcoin Season',
    'ja': 'ビットコインシーズン', 'ko': '비트코인 시즌', 'es': 'Temporada de Bitcoin',
    'pt': 'Temporada do Bitcoin', 'hi': 'बिटकॉइन सीज़न',
  },
  'ov_alt_gap': {
    'zh-CN': '距山寨季差 {n} 点', 'zh-TW': '距山寨季差 {n} 點',
    'en': '{n} pts to altseason', 'ja': 'アルトシーズンまであと {n} 点',
    'ko': '알트시즌까지 {n}포인트', 'es': 'A {n} pts de la altseason',
    'pt': 'A {n} pts da altseason', 'hi': 'अल्ट सीज़न से {n} अंक दूर',
  },
  'ov_whale_body': {
    'zh-CN': '巨鲸地址 {addr} 在 Hyperliquid {verb} {symbol}，仓位规模约 {usd}。',
    'zh-TW': '巨鯨地址 {addr} 在 Hyperliquid {verb} {symbol}，倉位規模約 {usd}。',
    'en': 'Whale {addr} {verb} {symbol} on Hyperliquid, position ~{usd}.',
    'ja': 'クジラ {addr} が Hyperliquid で {symbol} を{verb}、ポジション規模は約 {usd}。',
    'ko': '고래 {addr}가 Hyperliquid에서 {symbol} {verb}, 포지션 규모 약 {usd}.',
    'es': 'La ballena {addr} {verb} {symbol} en Hyperliquid, posición ~{usd}.',
    'pt': 'A baleia {addr} {verb} {symbol} na Hyperliquid, posição ~{usd}.',
    'hi': 'व्हेल {addr} ने Hyperliquid पर {symbol} {verb}, पोज़ीशन ~{usd}।',
  },

  // ---------------- home_market_page ----------------
  'mkt_cat_all': {
    'zh-CN': '全部', 'zh-TW': '全部', 'en': 'All',
    'ja': 'すべて', 'ko': '전체', 'es': 'Todos',
    'pt': 'Todos', 'hi': 'सभी',
  },
  'mkt_cat_solana': {
    'zh-CN': 'Solana生态', 'zh-TW': 'Solana生態', 'en': 'Solana Ecosystem',
    'ja': 'Solanaエコシステム', 'ko': 'Solana 생태계', 'es': 'Ecosistema Solana',
    'pt': 'Ecossistema Solana', 'hi': 'Solana इकोसिस्टम',
  },
  'mkt_load_failed': {
    'zh-CN': '行情加载失败, 下拉重试', 'zh-TW': '行情載入失敗, 下拉重試',
    'en': 'Failed to load, pull to retry', 'ja': '読み込み失敗、引っ張って再試行',
    'ko': '로드 실패, 당겨서 다시 시도', 'es': 'Error al cargar, desliza para reintentar',
    'pt': 'Falha ao carregar, puxe para tentar de novo', 'hi': 'लोड विफल, रीट्राई के लिए खींचें',
  },
  'mkt_sector_empty': {
    'zh-CN': '该板块暂无上榜币种', 'zh-TW': '該板塊暫無上榜幣種',
    'en': 'No listed coins in this sector', 'ja': 'このセクターに該当銘柄なし',
    'ko': '이 섹터에 상장된 코인 없음', 'es': 'Sin monedas en este sector',
    'pt': 'Sem moedas neste setor', 'hi': 'इस सेक्टर में कोई कॉइन नहीं',
  },
  'mkt_market_heat': {
    'zh-CN': '全网市场热度', 'zh-TW': '全網市場熱度', 'en': 'Global Market Heat',
    'ja': '市場全体のヒート', 'ko': '전체 시장 히트', 'es': 'Calor del mercado',
    'pt': 'Calor do mercado', 'hi': 'ग्लोबल मार्केट हीट',
  },
  'mkt_volume_24h': {
    'zh-CN': '24H 全网成交', 'zh-TW': '24H 全網成交', 'en': '24H Total Volume',
    'ja': '24H 全体出来高', 'ko': '24H 전체 거래대금', 'es': 'Volumen total 24H',
    'pt': 'Volume total 24H', 'hi': '24H कुल वॉल्यूम',
  },
  'mkt_very_active': {
    'zh-CN': '极度活跃', 'zh-TW': '極度活躍', 'en': 'Extremely active',
    'ja': '非常に活発', 'ko': '매우 활발', 'es': 'Muy activo',
    'pt': 'Muito ativo', 'hi': 'बेहद सक्रिय',
  },
  'mkt_high': {
    'zh-CN': '高', 'zh-TW': '高', 'en': 'High',
    'ja': '高値', 'ko': '고가', 'es': 'Máx',
    'pt': 'Máx', 'hi': 'उच्च',
  },
  'mkt_leader_up': {
    'zh-CN': '领涨', 'zh-TW': '領漲', 'en': 'Top gainer',
    'ja': '上昇主導', 'ko': '상승 주도', 'es': 'Líder de subida',
    'pt': 'Líder de alta', 'hi': 'टॉप गेनर',
  },
  'mkt_leader_down': {
    'zh-CN': '领跌', 'zh-TW': '領跌', 'en': 'Top loser',
    'ja': '下落主導', 'ko': '하락 주도', 'es': 'Líder de bajada',
    'pt': 'Líder de queda', 'hi': 'टॉप लूज़र',
  },
  'mkt_tag_breakout': {
    'zh-CN': '爆发', 'zh-TW': '爆發', 'en': 'Breakout',
    'ja': '急騰', 'ko': '급등', 'es': 'Explosivo',
    'pt': 'Explosão', 'hi': 'ब्रेकआउट',
  },
  'mkt_tag_volume': {
    'zh-CN': '放量', 'zh-TW': '放量', 'en': 'Volume surge',
    'ja': '出来高増', 'ko': '거래량 증가', 'es': 'Volumen al alza',
    'pt': 'Volume em alta', 'hi': 'वॉल्यूम सर्ज',
  },
  'mkt_tag_range': {
    'zh-CN': '震荡', 'zh-TW': '震盪', 'en': 'Ranging',
    'ja': 'レンジ', 'ko': '횡보', 'es': 'Lateral',
    'pt': 'Lateral', 'hi': 'रेंजिंग',
  },
  'mkt_tag_weak': {
    'zh-CN': '走弱', 'zh-TW': '走弱', 'en': 'Weakening',
    'ja': '軟調', 'ko': '약세', 'es': 'Debilitándose',
    'pt': 'Enfraquecendo', 'hi': 'कमज़ोर',
  },
  'mkt_sort_volume': {
    'zh-CN': '成交额榜', 'zh-TW': '成交額榜', 'en': 'By Volume',
    'ja': '出来高順', 'ko': '거래대금순', 'es': 'Por volumen',
    'pt': 'Por volume', 'hi': 'वॉल्यूम क्रम',
  },
  'mkt_sort_gainers': {
    'zh-CN': '涨幅榜', 'zh-TW': '漲幅榜', 'en': 'Gainers',
    'ja': '上昇率順', 'ko': '상승률순', 'es': 'Ganadores',
    'pt': 'Ganhadores', 'hi': 'गेनर्स',
  },
  'mkt_sort_losers': {
    'zh-CN': '跌幅榜', 'zh-TW': '跌幅榜', 'en': 'Losers',
    'ja': '下落率順', 'ko': '하락률순', 'es': 'Perdedores',
    'pt': 'Perdedores', 'hi': 'लूज़र्स',
  },
  'mkt_col_pair_vol': {
    'zh-CN': '币种 / 成交额', 'zh-TW': '幣種 / 成交額', 'en': 'Coin / Volume',
    'ja': '銘柄 / 出来高', 'ko': '코인 / 거래대금', 'es': 'Moneda / Volumen',
    'pt': 'Moeda / Volume', 'hi': 'कॉइन / वॉल्यूम',
  },
  'mkt_col_price': {
    'zh-CN': '现价 (USD)', 'zh-TW': '現價 (USD)', 'en': 'Price (USD)',
    'ja': '現在値 (USD)', 'ko': '현재가 (USD)', 'es': 'Precio (USD)',
    'pt': 'Preço (USD)', 'hi': 'कीमत (USD)',
  },
  'mkt_col_trend': {
    'zh-CN': '24H 趋势 / 涨跌', 'zh-TW': '24H 趨勢 / 漲跌', 'en': '24H Trend / Change',
    'ja': '24H トレンド / 騰落', 'ko': '24H 추세 / 등락', 'es': 'Tendencia 24H / Cambio',
    'pt': 'Tendência 24H / Variação', 'hi': '24H ट्रेंड / बदलाव',
  },
  'mkt_heatmap_title': {
    'zh-CN': '板块轮动动能 (24H Heatmap)', 'zh-TW': '板塊輪動動能 (24H Heatmap)',
    'en': 'Sector Rotation (24H Heatmap)', 'ja': 'セクターローテーション (24H ヒートマップ)',
    'ko': '섹터 로테이션 (24H 히트맵)', 'es': 'Rotación sectorial (mapa 24H)',
    'pt': 'Rotação setorial (mapa 24H)', 'hi': 'सेक्टर रोटेशन (24H हीटमैप)',
  },
  'mkt_okx_realtime': {
    'zh-CN': 'OKX 永续实时', 'zh-TW': 'OKX 永續實時', 'en': 'OKX Perp Live',
    'ja': 'OKX 無期限リアルタイム', 'ko': 'OKX 무기한 실시간', 'es': 'OKX Perp en vivo',
    'pt': 'OKX Perp ao vivo', 'hi': 'OKX पर्प लाइव',
  },
  'mkt_sector_loading': {
    'zh-CN': '板块数据加载中…', 'zh-TW': '板塊數據載入中…', 'en': 'Loading sector data…',
    'ja': 'セクターデータを読み込み中…', 'ko': '섹터 데이터 로딩 중…',
    'es': 'Cargando datos sectoriales…', 'pt': 'Carregando dados setoriais…',
    'hi': 'सेक्टर डेटा लोड हो रहा है…',
  },
  'mkt_data_source': {
    'zh-CN': '数据源: OKX 永续合约', 'zh-TW': '數據源: OKX 永續合約',
    'en': 'Source: OKX Perpetuals', 'ja': 'データ源: OKX 無期限',
    'ko': '데이터 소스: OKX 무기한', 'es': 'Fuente: Futuros OKX',
    'pt': 'Fonte: Perpétuos OKX', 'hi': 'स्रोत: OKX पर्पेचुअल',
  },
  'mkt_heartbeat_right': {
    'zh-CN': '24H 行情 · 下拉刷新', 'zh-TW': '24H 行情 · 下拉刷新',
    'en': '24H Market · Pull to refresh', 'ja': '24H 相場 · 引っ張って更新',
    'ko': '24H 시세 · 당겨서 새로고침', 'es': 'Mercado 24H · Desliza para actualizar',
    'pt': 'Mercado 24H · Puxe para atualizar', 'hi': '24H मार्केट · रीफ्रेश के लिए खींचें',
  },

  // ---------------- home_terminal_page ----------------
  'term_matrix_section': {
    'zh-CN': '市场深度量化指标矩阵', 'zh-TW': '市場深度量化指標矩陣',
    'en': 'Market Depth Metrics Matrix', 'ja': '市場深度定量指標マトリックス',
    'ko': '시장 심도 정량 지표 매트릭스', 'es': 'Matriz de métricas de profundidad',
    'pt': 'Matriz de métricas de profundidade', 'hi': 'मार्केट डेप्थ मेट्रिक्स मैट्रिक्स',
  },
  'term_matrix_trailing': {
    'zh-CN': '公开数据源实时聚合', 'zh-TW': '公開數據源實時聚合',
    'en': 'Aggregated from public sources', 'ja': '公開データをリアルタイム集約',
    'ko': '공개 데이터 실시간 집계', 'es': 'Agregado de fuentes públicas',
    'pt': 'Agregado de fontes públicas', 'hi': 'सार्वजनिक स्रोतों से लाइव एग्रीगेट',
  },
  'term_assets_section': {
    'zh-CN': '主流资产多维量化指标一览', 'zh-TW': '主流資產多維量化指標一覽',
    'en': 'Major Assets Multi-Metric Overview', 'ja': '主要資産の多次元指標一覧',
    'ko': '주요 자산 다차원 지표一览', 'es': 'Resumen multimétrico de activos',
    'pt': 'Resumo multimétrico de ativos', 'hi': 'प्रमुख एसेट्स मल्टी-मेट्रिक अवलोकन',
  },
  'term_assets_trailing': {
    'zh-CN': 'OKX 行情 · 三所费率', 'zh-TW': 'OKX 行情 · 三所費率',
    'en': 'OKX Market · 3-Exchange Rates', 'ja': 'OKX 相場 · 3取引所レート',
    'ko': 'OKX 시세 · 3개 거래소 수수료', 'es': 'Mercado OKX · Tasas de 3 exchanges',
    'pt': 'Mercado OKX · Taxas de 3 corretoras', 'hi': 'OKX मार्केट · 3 एक्सचेंज रेट',
  },
  'term_sentiment_index': {
    'zh-CN': '情绪指数', 'zh-TW': '情緒指數', 'en': 'Sentiment Index',
    'ja': 'センチメント指数', 'ko': '심리 지수', 'es': 'Índice de sentimiento',
    'pt': 'Índice de sentimento', 'hi': 'सेंटिमेंट इंडेक्स',
  },
  'term_vs_yesterday': {
    'zh-CN': '{diff} 较昨日', 'zh-TW': '{diff} 較昨日', 'en': '{diff} vs yesterday',
    'ja': '前日比 {diff}', 'ko': '전일 대비 {diff}', 'es': '{diff} vs ayer',
    'pt': '{diff} vs ontem', 'hi': 'कल से {diff}',
  },
  'term_yesterday_line': {
    'zh-CN': '昨日 {v} · {label}', 'zh-TW': '昨日 {v} · {label}',
    'en': 'Yesterday {v} · {label}', 'ja': '昨日 {v} · {label}',
    'ko': '어제 {v} · {label}', 'es': 'Ayer {v} · {label}',
    'pt': 'Ontem {v} · {label}', 'hi': 'कल {v} · {label}',
  },
  'term_lastweek_line': {
    'zh-CN': '上周 {v} · {label}', 'zh-TW': '上週 {v} · {label}',
    'en': 'Last week {v} · {label}', 'ja': '先週 {v} · {label}',
    'ko': '지난주 {v} · {label}', 'es': 'Semana pasada {v} · {label}',
    'pt': 'Semana passada {v} · {label}', 'hi': 'पिछला सप्ताह {v} · {label}',
  },
  'term_dominance': {
    'zh-CN': '市占率分布', 'zh-TW': '市佔率分佈', 'en': 'Dominance Distribution',
    'ja': 'ドミナンス分布', 'ko': '점유율 분포', 'es': 'Distribución de dominio',
    'pt': 'Distribuição de dominância', 'hi': 'डॉमिनेंस वितरण',
  },
  'term_liq_count': {
    'zh-CN': '{n} 笔', 'zh-TW': '{n} 筆', 'en': '{n}',
    'ja': '{n} 件', 'ko': '{n}건', 'es': '{n}',
    'pt': '{n}', 'hi': '{n}',
  },
  'term_ls_footer': {
    'zh-CN': '多头 {long}% · 空头 {short}%', 'zh-TW': '多頭 {long}% · 空頭 {short}%',
    'en': 'Long {long}% · Short {short}%', 'ja': 'ロング {long}% · ショート {short}%',
    'ko': '롱 {long}% · 숏 {short}%', 'es': 'Long {long}% · Short {short}%',
    'pt': 'Long {long}% · Short {short}%', 'hi': 'लॉन्ग {long}% · शॉर्ट {short}%',
  },
  'term_vol_prefix': {
    'zh-CN': '成交 {v}', 'zh-TW': '成交 {v}', 'en': 'Vol {v}',
    'ja': '出来高 {v}', 'ko': '거래 {v}', 'es': 'Vol {v}',
    'pt': 'Vol {v}', 'hi': 'वॉल्यूम {v}',
  },
  'term_rate_na': {
    'zh-CN': '费率 --', 'zh-TW': '費率 --', 'en': 'Rate --',
    'ja': 'レート --', 'ko': '수수료 --', 'es': 'Tasa --',
    'pt': 'Taxa --', 'hi': 'रेट --',
  },
  'term_rate_prefix': {
    'zh-CN': '费率 {v}', 'zh-TW': '費率 {v}', 'en': 'Rate {v}',
    'ja': 'レート {v}', 'ko': '수수료 {v}', 'es': 'Tasa {v}',
    'pt': 'Taxa {v}', 'hi': 'रेट {v}',
  },
  'term_alt_change': {
    'zh-CN': '24H {sign}{n} 点', 'zh-TW': '24H {sign}{n} 點',
    'en': '24H {sign}{n} pts', 'ja': '24H {sign}{n} 点',
    'ko': '24H {sign}{n}포인트', 'es': '24H {sign}{n} pts',
    'pt': '24H {sign}{n} pts', 'hi': '24H {sign}{n} अंक',
  },
  'term_alt_gap_mock': {
    'zh-CN': '距山寨爆发差 37 点', 'zh-TW': '距山寨爆發差 37 點',
    'en': '37 pts to alt breakout', 'ja': 'アルト急騰まであと 37 点',
    'ko': '알트 급등까지 37포인트', 'es': 'A 37 pts del boom de alts',
    'pt': 'A 37 pts do boom das alts', 'hi': 'अल्ट ब्रेकआउट से 37 अंक दूर',
  },
  'term_alt_season': {
    'zh-CN': '山寨季指数', 'zh-TW': '山寨季指數', 'en': 'Altcoin Season Index',
    'ja': 'アルトシーズン指数', 'ko': '알트시즌 지수', 'es': 'Índice de altseason',
    'pt': 'Índice de altseason', 'hi': 'अल्टकॉइन सीज़न इंडेक्स',
  },
  'term_open_interest': {
    'zh-CN': '全网未平仓合约', 'zh-TW': '全網未平倉合約', 'en': 'Total Open Interest',
    'ja': '全ネット未決済建玉', 'ko': '전체 미결제 약정', 'es': 'Interés abierto total',
    'pt': 'Interesse aberto total', 'hi': 'कुल ओपन इंटरेस्ट',
  },
  'term_oi_footer': {
    'zh-CN': 'BTC+ETH 永续名义持仓', 'zh-TW': 'BTC+ETH 永續名義持倉',
    'en': 'BTC+ETH perp notional', 'ja': 'BTC+ETH 無期限名目建玉',
    'ko': 'BTC+ETH 무기한 명목 포지션', 'es': 'Nocional perp BTC+ETH',
    'pt': 'Nocional perp BTC+ETH', 'hi': 'BTC+ETH पर्प नोशनल',
  },
  'term_funding_weighted': {
    'zh-CN': '资金费率加权', 'zh-TW': '資金費率加權', 'en': 'Weighted Funding Rate',
    'ja': '加重平均資金調達率', 'ko': '가중 펀딩 비율', 'es': 'Tasa de fondeo ponderada',
    'pt': 'Taxa de funding ponderada', 'hi': 'वेटेड फंडिंग रेट',
  },
  'term_funding_pill': {
    'zh-CN': '适度偏多', 'zh-TW': '適度偏多', 'en': 'Moderately long',
    'ja': 'ややロング寄り', 'ko': '적당히 롱 우세', 'es': 'Moderadamente long',
    'pt': 'Moderadamente long', 'hi': 'मॉडरेट लॉन्ग',
  },
  'term_funding_footer': {
    'zh-CN': 'Binance/OKX/Bybit 均值', 'zh-TW': 'Binance/OKX/Bybit 均值',
    'en': 'Binance/OKX/Bybit average', 'ja': 'Binance/OKX/Bybit 平均',
    'ko': 'Binance/OKX/Bybit 평균', 'es': 'Media Binance/OKX/Bybit',
    'pt': 'Média Binance/OKX/Bybit', 'hi': 'Binance/OKX/Bybit औसत',
  },
  'term_liq_total': {
    'zh-CN': '24H 爆仓总额', 'zh-TW': '24H 爆倉總額', 'en': '24H Total Liquidations',
    'ja': '24H 清算総額', 'ko': '24H 총 청산', 'es': 'Liquidaciones totales 24H',
    'pt': 'Liquidações totais 24H', 'hi': '24H कुल लिक्विडेशन',
  },
  'term_liq_footer': {
    'zh-CN': 'OKX/Bybit 实时强平聚合', 'zh-TW': 'OKX/Bybit 實時強平聚合',
    'en': 'OKX/Bybit live liquidation feed', 'ja': 'OKX/Bybit リアルタイム清算集約',
    'ko': 'OKX/Bybit 실시간 강제청산 집계', 'es': 'Liquidaciones en vivo OKX/Bybit',
    'pt': 'Liquidações ao vivo OKX/Bybit', 'hi': 'OKX/Bybit लाइव लिक्विडेशन',
  },
  'term_stable_index': {
    'zh-CN': '稳定币供给指数', 'zh-TW': '穩定幣供給指數', 'en': 'Stablecoin Supply Index',
    'ja': 'ステーブルコイン供給指数', 'ko': '스테이블코인 공급 지수',
    'es': 'Índice de oferta de stablecoins', 'pt': 'Índice de oferta de stablecoins',
    'hi': 'स्टेबलकॉइन सप्लाई इंडेक्स',
  },
  'term_stable_footer': {
    'zh-CN': 'DefiLlama 全稳定币流通', 'zh-TW': 'DefiLlama 全穩定幣流通',
    'en': 'DefiLlama total stablecoin supply', 'ja': 'DefiLlama 全ステーブルコイン流通',
    'ko': 'DefiLlama 전체 스테이블코인 유통', 'es': 'DefiLlama, toda la oferta de stablecoins',
    'pt': 'DefiLlama, toda a oferta de stablecoins', 'hi': 'DefiLlama कुल स्टेबलकॉइन सप्लाई',
  },
  'term_long_short_ratio': {
    'zh-CN': '多空人数比 (L/S)', 'zh-TW': '多空人數比 (L/S)', 'en': 'Long/Short Ratio (L/S)',
    'ja': 'ロング/ショート比 (L/S)', 'ko': '롱/숏 비율 (L/S)', 'es': 'Ratio Long/Short (L/S)',
    'pt': 'Razão Long/Short (L/S)', 'hi': 'लॉन्ग/शॉर्ट रेशियो (L/S)',
  },
  'term_pill_okx_perp': {
    'zh-CN': 'OKX 永续', 'zh-TW': 'OKX 永續', 'en': 'OKX Perp',
    'ja': 'OKX 無期限', 'ko': 'OKX 무기한', 'es': 'OKX Perp',
    'pt': 'OKX Perp', 'hi': 'OKX पर्प',
  },
  'term_pill_binance_acct': {
    'zh-CN': 'Binance 账户', 'zh-TW': 'Binance 賬戶', 'en': 'Binance accounts',
    'ja': 'Binance アカウント', 'ko': 'Binance 계정', 'es': 'Cuentas de Binance',
    'pt': 'Contas da Binance', 'hi': 'Binance अकाउंट',
  },

  // ---------------- home_funding_page ----------------
  'fund_health_long_overheat': {
    'zh-CN': '多头过热·高溢价', 'zh-TW': '多頭過熱·高溢價', 'en': 'Longs overheated · high premium',
    'ja': 'ロング過熱・高プレミアム', 'ko': '롱 과열·고 프리미엄', 'es': 'Longs sobrecalentados · prima alta',
    'pt': 'Longs superaquecidos · prêmio alto', 'hi': 'लॉन्ग ओवरहीट · हाई प्रीमियम',
  },
  'fund_health_long_healthy': {
    'zh-CN': '健康多头·温和溢价', 'zh-TW': '健康多頭·溫和溢價', 'en': 'Healthy longs · mild premium',
    'ja': '健全なロング・緩やかなプレミアム', 'ko': '건전한 롱·완만한 프리미엄',
    'es': 'Longs saludables · prima moderada', 'pt': 'Longs saudáveis · prêmio moderado',
    'hi': 'स्वस्थ लॉन्ग · माइल्ड प्रीमियम',
  },
  'fund_health_balanced': {
    'zh-CN': '多空均衡', 'zh-TW': '多空均衡', 'en': 'Balanced long/short',
    'ja': 'ロング・ショート均衡', 'ko': '롱숏 균형', 'es': 'Equilibrio long/short',
    'pt': 'Equilíbrio long/short', 'hi': 'लॉन्ग/शॉर्ट संतुलित',
  },
  'fund_health_short_mild': {
    'zh-CN': '空头温和·贴水', 'zh-TW': '空頭溫和·貼水', 'en': 'Mild shorts · discount',
    'ja': '緩やかなショート・ディスカウント', 'ko': '완만한 숏·디스카운트',
    'es': 'Shorts moderados · descuento', 'pt': 'Shorts moderados · desconto',
    'hi': 'माइल्ड शॉर्ट · डिस्काउंट',
  },
  'fund_health_short_crowded': {
    'zh-CN': '空头拥挤·深度贴水', 'zh-TW': '空頭擁擠·深度貼水', 'en': 'Crowded shorts · deep discount',
    'ja': 'ショート混雑・大幅ディスカウント', 'ko': '숏 혼잡·깊은 디스카운트',
    'es': 'Shorts congestionados · descuento fuerte', 'pt': 'Shorts lotados · desconto profundo',
    'hi': 'क्राउडेड शॉर्ट · डीप डिस्काउंट',
  },
  'fund_status_overheat': {
    'zh-CN': '多头过热', 'zh-TW': '多頭過熱', 'en': 'Longs overheated',
    'ja': 'ロング過熱', 'ko': '롱 과열', 'es': 'Longs sobrecalentados',
    'pt': 'Longs superaquecidos', 'hi': 'लॉन्ग ओवरहीट',
  },
  'fund_status_mild_long': {
    'zh-CN': '适度看多', 'zh-TW': '適度看多', 'en': 'Moderately bullish',
    'ja': 'やや強気', 'ko': '적당히 강세', 'es': 'Moderadamente alcista',
    'pt': 'Moderadamente otimista', 'hi': 'मॉडरेट बुलिश',
  },
  'fund_status_stable': {
    'zh-CN': '基准平稳', 'zh-TW': '基準平穩', 'en': 'Stable baseline',
    'ja': '基準は安定', 'ko': '기준 안정', 'es': 'Base estable',
    'pt': 'Base estável', 'hi': 'स्टेबल बेसलाइन',
  },
  'fund_status_short_crowded': {
    'zh-CN': '空头拥挤', 'zh-TW': '空頭擁擠', 'en': 'Crowded shorts',
    'ja': 'ショート混雑', 'ko': '숏 혼잡', 'es': 'Shorts congestionados',
    'pt': 'Shorts lotados', 'hi': 'क्राउडेड शॉर्ट',
  },
  'fund_per_8h': {
    'zh-CN': '/ 8h', 'zh-TW': '/ 8h', 'en': '/ 8h',
    'ja': '/ 8h', 'ko': '/ 8h', 'es': '/ 8h',
    'pt': '/ 8h', 'hi': '/ 8h',
  },
  'fund_index_title': {
    'zh-CN': '全网加权资金费率指数', 'zh-TW': '全網加權資金費率指數',
    'en': 'Global Weighted Funding Rate Index', 'ja': '全ネット加重平均資金調達率指数',
    'ko': '전체 가중 펀딩 비율 지수', 'es': 'Índice global de tasa de fondeo ponderada',
    'pt': 'Índice global de taxa de funding ponderada', 'hi': 'ग्लोबल वेटेड फंडिंग रेट इंडेक्स',
  },
  'fund_settle_8h': {
    'zh-CN': '8H结算', 'zh-TW': '8H結算', 'en': '8H settlement',
    'ja': '8時間決済', 'ko': '8시간 정산', 'es': 'Liquidación 8H',
    'pt': 'Liquidação 8H', 'hi': '8H सेटलमेंट',
  },
  'fund_apy_label': {
    'zh-CN': '综合加权年化 (APY)', 'zh-TW': '綜合加權年化 (APY)', 'en': 'Weighted APY',
    'ja': '加重平均年率 (APY)', 'ko': '가중 연율 (APY)', 'es': 'APY ponderado',
    'pt': 'APY ponderado', 'hi': 'वेटेड APY',
  },
  'fund_next_settle': {
    'zh-CN': '距离下次结算', 'zh-TW': '距離下次結算', 'en': 'Next settlement in',
    'ja': '次回決済まで', 'ko': '다음 정산까지', 'es': 'Próxima liquidación en',
    'pt': 'Próxima liquidação em', 'hi': 'अगला सेटलमेंट',
  },
  'fund_settle_cycle': {
    'zh-CN': '结算周期 UTC 00/08/16', 'zh-TW': '結算週期 UTC 00/08/16',
    'en': 'Settlement cycle UTC 00/08/16', 'ja': '決済サイクル UTC 00/08/16',
    'ko': '정산 주기 UTC 00/08/16', 'es': 'Ciclo de liquidación UTC 00/08/16',
    'pt': 'Ciclo de liquidação UTC 00/08/16', 'hi': 'सेटलमेंट साइकिल UTC 00/08/16',
  },
  'fund_temp_low': {
    'zh-CN': '极度恐慌贴水 (-100%)', 'zh-TW': '極度恐慌貼水 (-100%)',
    'en': 'Extreme fear discount (-100%)', 'ja': '極度の恐怖ディスカウント (-100%)',
    'ko': '극도의 공포 디스카운트 (-100%)', 'es': 'Descuento de miedo extremo (-100%)',
    'pt': 'Desconto de medo extremo (-100%)', 'hi': 'अत्यंत भय डिस्काउंट (-100%)',
  },
  'fund_temp_mid': {
    'zh-CN': '中性基准 (0%)', 'zh-TW': '中性基準 (0%)', 'en': 'Neutral baseline (0%)',
    'ja': '中立基準 (0%)', 'ko': '중립 기준 (0%)', 'es': 'Base neutral (0%)',
    'pt': 'Base neutra (0%)', 'hi': 'तटस्थ बेसलाइन (0%)',
  },
  'fund_temp_high': {
    'zh-CN': '极度过热溢价 (+100%)', 'zh-TW': '極度過熱溢價 (+100%)',
    'en': 'Extreme greed premium (+100%)', 'ja': '極度の過熱プレミアム (+100%)',
    'ko': '극도의 과열 프리미엄 (+100%)', 'es': 'Prima de avaricia extrema (+100%)',
    'pt': 'Prêmio de ganância extrema (+100%)', 'hi': 'अत्यंत लालच प्रीमियम (+100%)',
  },
  'fund_arb_title': {
    'zh-CN': '期现套利年化推荐 (Basis Arbitrage)', 'zh-TW': '期現套利年化推薦 (Basis Arbitrage)',
    'en': 'Basis Arbitrage APY Picks', 'ja': 'ベーシス裁定 年率おすすめ',
    'ko': '베이시스 차익 연율 추천', 'es': 'Selección de APY de arbitraje de base',
    'pt': 'Seleções de APY de arbitragem de base', 'hi': 'बेसिस आर्बिट्राज APY पिक्स',
  },
  'fund_arb_formula': {
    'zh-CN': '年化 = 8H费率×1095', 'zh-TW': '年化 = 8H費率×1095',
    'en': 'APY = 8H rate × 1095', 'ja': '年率 = 8時間レート × 1095',
    'ko': '연율 = 8시간 수수료 × 1095', 'es': 'APY = tasa 8H × 1095',
    'pt': 'APY = taxa 8H × 1095', 'hi': 'APY = 8H रेट × 1095',
  },
  'fund_arb_none': {
    'zh-CN': '当前无正费率合约, 暂无套利机会', 'zh-TW': '當前無正費率合約, 暫無套利機會',
    'en': 'No positive-rate contracts, no arbitrage now',
    'ja': '正レートの銘柄がなく、裁定機会なし',
    'ko': '양수 수수료 계약 없음, 차익 기회 없음',
    'es': 'Sin contratos de tasa positiva, sin arbitraje',
    'pt': 'Sem contratos de taxa positiva, sem arbitragem',
    'hi': 'कोई पॉज़िटिव-रेट कॉन्ट्रैक्ट नहीं, कोई आर्बिट्राज नहीं',
  },
  'fund_pick_top': {
    'zh-CN': '首推', 'zh-TW': '首推', 'en': 'Top pick',
    'ja': 'イチ押し', 'ko': '최우선', 'es': 'Primera opción',
    'pt': 'Primeira escolha', 'hi': 'टॉप पिक',
  },
  'fund_pick_second': {
    'zh-CN': '次选', 'zh-TW': '次選', 'en': 'Second pick',
    'ja': '次点', 'ko': '차선', 'es': 'Segunda opción',
    'pt': 'Segunda escolha', 'hi': 'सेकंड पिक',
  },
  'fund_three_ex_avg': {
    'zh-CN': '三所费率均值', 'zh-TW': '三所費率均值', 'en': '3-exchange avg',
    'ja': '3取引所平均', 'ko': '3개 거래소 평균', 'es': 'Media de 3 exchanges',
    'pt': 'Média de 3 corretoras', 'hi': '3 एक्सचेंज औसत',
  },
  'fund_basis_hedge': {
    'zh-CN': '基差对冲', 'zh-TW': '基差對沖', 'en': 'Basis hedge',
    'ja': 'ベーシスヘッジ', 'ko': '베이시스 헤지', 'es': 'Cobertura de base',
    'pt': 'Hedge de base', 'hi': 'बेसिस हेज',
  },
  'fund_long_spot_short_perp': {
    'zh-CN': '做多现货 + 做空永续', 'zh-TW': '做多現貨 + 做空永續',
    'en': 'Long spot + short perp', 'ja': '現物ロング + 無期限ショート',
    'ko': '현물 롱 + 무기한 숏', 'es': 'Long spot + short perp',
    'pt': 'Long spot + short perp', 'hi': 'लॉन्ग स्पॉट + शॉर्ट पर्प',
  },
  'fund_expected_apy': {
    'zh-CN': '预期 APY', 'zh-TW': '預期 APY', 'en': 'Expected APY',
    'ja': '予想 APY', 'ko': '예상 APY', 'es': 'APY esperado',
    'pt': 'APY esperado', 'hi': 'अपेक्षित APY',
  },
  'fund_today': {
    'zh-CN': '今日', 'zh-TW': '今日', 'en': 'Today',
    'ja': '今日', 'ko': '오늘', 'es': 'Hoy',
    'pt': 'Hoje', 'hi': 'आज',
  },
  'fund_matrix_title': {
    'zh-CN': '全市场主流永续费率矩阵', 'zh-TW': '全市場主流永續費率矩陣',
    'en': 'Major Perp Funding Rate Matrix', 'ja': '主要無期限レートマトリックス',
    'ko': '주요 무기한 수수료 매트릭스', 'es': 'Matriz de tasas de futuros principales',
    'pt': 'Matriz de taxas de perpétuos', 'hi': 'मेजर पर्प फंडिंग रेट मैट्रिक्स',
  },
  'fund_matrix_sub': {
    'zh-CN': '已聚合主流3大所', 'zh-TW': '已聚合主流3大所',
    'en': 'Aggregated from top 3 exchanges', 'ja': '主要3取引所を集約',
    'ko': '주요 3개 거래소 집계', 'es': 'Agregado de los 3 principales exchanges',
    'pt': 'Agregado das 3 principais corretoras', 'hi': 'टॉप 3 एक्सचेंज से एग्रीगेट',
  },
  'fund_filter_pos': {
    'zh-CN': '正费率 (多头拥挤)', 'zh-TW': '正費率 (多頭擁擠)', 'en': 'Positive (crowded longs)',
    'ja': '正レート (ロング混雑)', 'ko': '양수 수수료 (롱 혼잡)', 'es': 'Positiva (longs llenos)',
    'pt': 'Positiva (longs lotados)', 'hi': 'पॉज़िटिव (क्राउडेड लॉन्ग)',
  },
  'fund_filter_neg': {
    'zh-CN': '负费率 (空头拥挤)', 'zh-TW': '負費率 (空頭擁擠)', 'en': 'Negative (crowded shorts)',
    'ja': '負レート (ショート混雑)', 'ko': '음수 수수료 (숏 혼잡)', 'es': 'Negativa (shorts llenos)',
    'pt': 'Negativa (shorts lotados)', 'hi': 'नेगेटिव (क्राउडेड शॉर्ट)',
  },
  'fund_filter_hot': {
    'zh-CN': '异动激增', 'zh-TW': '異動激增', 'en': 'Surging',
    'ja': '急変動', 'ko': '급변동', 'es': 'Repunte',
    'pt': 'Disparando', 'hi': 'सर्जिंग',
  },
  'fund_col_pair': {
    'zh-CN': '交易对 / 现价', 'zh-TW': '交易對 / 現價', 'en': 'Pair / Price',
    'ja': 'ペア / 現在値', 'ko': '페어 / 현재가', 'es': 'Par / Precio',
    'pt': 'Par / Preço', 'hi': 'पेयर / कीमत',
  },
  'fund_col_rate': {
    'zh-CN': '8H费率 (三所聚合)', 'zh-TW': '8H費率 (三所聚合)', 'en': '8H Rate (3-exchange)',
    'ja': '8時間レート (3取引所)', 'ko': '8시간 수수료 (3개 거래소)', 'es': 'Tasa 8H (3 exchanges)',
    'pt': 'Taxa 8H (3 corretoras)', 'hi': '8H रेट (3 एक्सचेंज)',
  },
  'fund_col_apy': {
    'zh-CN': '年化 / 状态', 'zh-TW': '年化 / 狀態', 'en': 'APY / Status',
    'ja': '年率 / 状態', 'ko': '연율 / 상태', 'es': 'APY / Estado',
    'pt': 'APY / Status', 'hi': 'APY / स्थिति',
  },
  'fund_empty_category': {
    'zh-CN': '该分类下暂无合约', 'zh-TW': '該分類下暫無合約', 'en': 'No contracts in this category',
    'ja': 'このカテゴリに銘柄なし', 'ko': '이 분류에 계약 없음', 'es': 'Sin contratos en esta categoría',
    'pt': 'Sem contratos nesta categoria', 'hi': 'इस श्रेणी में कोई कॉन्ट्रैक्ट नहीं',
  },
  'fund_loading': {
    'zh-CN': '加载中...', 'zh-TW': '載入中...', 'en': 'Loading...',
    'ja': '読み込み中...', 'ko': '로딩 중...', 'es': 'Cargando...',
    'pt': 'Carregando...', 'hi': 'लोड हो रहा है...',
  },
  'fund_expand': {
    'zh-CN': '展开更多合约费率', 'zh-TW': '展開更多合約費率', 'en': 'Show more contract rates',
    'ja': 'さらに銘柄レートを表示', 'ko': '더 많은 계약 수수료 보기', 'es': 'Mostrar más tasas',
    'pt': 'Mostrar mais taxas', 'hi': 'और कॉन्ट्रैक्ट रेट देखें',
  },
  'fund_collapse': {
    'zh-CN': '收起额外合约', 'zh-TW': '收起額外合約', 'en': 'Hide extra contracts',
    'ja': '追加銘柄を隠す', 'ko': '추가 계약 접기', 'es': 'Ocultar contratos extra',
    'pt': 'Ocultar contratos extras', 'hi': 'अतिरिक्त कॉन्ट्रैक्ट छिपाएँ',
  },

  // ---------------- home_whale_page ----------------
  'whale_anon': {
    'zh-CN': '匿名巨鲸', 'zh-TW': '匿名巨鯨', 'en': 'Anonymous whale',
    'ja': '匿名のクジラ', 'ko': '익명 고래', 'es': 'Ballena anónima',
    'pt': 'Baleia anônima', 'hi': 'गुमनाम व्हेल',
  },
  'whale_pill_reduce': {
    'zh-CN': '减仓离场', 'zh-TW': '減倉離場', 'en': 'Reduced & exited',
    'ja': '減倉・撤退', 'ko': '축소·청산', 'es': 'Redujo y salió',
    'pt': 'Reduziu e saiu', 'hi': 'घटाया और बाहर',
  },
  'whale_pill_add': {
    'zh-CN': '加仓开仓', 'zh-TW': '加倉開倉', 'en': 'Added position',
    'ja': '増倉・新規', 'ko': '증액·신규', 'es': 'Aumentó posición',
    'pt': 'Aumentou posição', 'hi': 'पोज़ीशन बढ़ाई',
  },
  'whale_pill_move': {
    'zh-CN': '仓位异动', 'zh-TW': '倉位異動', 'en': 'Position change',
    'ja': 'ポジション変動', 'ko': '포지션 변동', 'es': 'Cambio de posición',
    'pt': 'Mudança de posição', 'hi': 'पोज़ीशन बदलाव',
  },
  'whale_verb_reduce': {
    'zh-CN': '减仓/平仓', 'zh-TW': '減倉/平倉', 'en': 'reduced/closed',
    'ja': '減倉/決済', 'ko': '축소/청산', 'es': 'redujo/cerró',
    'pt': 'reduziu/fechou', 'hi': 'घटाया/बंद किया',
  },
  'whale_verb_add': {
    'zh-CN': '加仓/开仓', 'zh-TW': '加倉/開倉', 'en': 'added/opened',
    'ja': '増倉/新規', 'ko': '증액/신규', 'es': 'aumentó/abrió',
    'pt': 'aumentou/abriu', 'hi': 'बढ़ाया/खोला',
  },
  'whale_verb_move': {
    'zh-CN': '调整仓位', 'zh-TW': '調整倉位', 'en': 'adjusted',
    'ja': '調整', 'ko': '조정', 'es': 'ajustó',
    'pt': 'ajustou', 'hi': 'समायोजित',
  },
  'whale_feed_short': {
    'zh-CN': '巨鲸减仓 · 空头异动', 'zh-TW': '巨鯨減倉 · 空頭異動', 'en': 'Whale reduced · short move',
    'ja': 'クジラ減倉 · ショート変動', 'ko': '고래 축소 · 숏 변동', 'es': 'Ballena redujo · movimiento short',
    'pt': 'Baleia reduziu · movimento short', 'hi': 'व्हेल घटाया · शॉर्ट मूव',
  },
  'whale_feed_long': {
    'zh-CN': '巨鲸加仓 · 多头异动', 'zh-TW': '巨鯨加倉 · 多頭異動', 'en': 'Whale added · long move',
    'ja': 'クジラ増倉 · ロング変動', 'ko': '고래 증액 · 롱 변동', 'es': 'Ballena aumentó · movimiento long',
    'pt': 'Baleia aumentou · movimento long', 'hi': 'व्हेल बढ़ाया · लॉन्ग मूव',
  },
  'whale_feed_move': {
    'zh-CN': '巨鲸仓位异动', 'zh-TW': '巨鯨倉位異動', 'en': 'Whale position change',
    'ja': 'クジラのポジション変動', 'ko': '고래 포지션 변동', 'es': 'Cambio de posición de ballena',
    'pt': 'Mudança de posição de baleia', 'hi': 'व्हेल पोज़ीशन बदलाव',
  },
  'whale_position_change': {
    'zh-CN': '{symbol} 仓位变动', 'zh-TW': '{symbol} 倉位變動', 'en': '{symbol} position change',
    'ja': '{symbol} ポジション変動', 'ko': '{symbol} 포지션 변동', 'es': '{symbol} cambio de posición',
    'pt': '{symbol} mudança de posição', 'hi': '{symbol} पोज़ीशन बदलाव',
  },
  'whale_position_update': {
    'zh-CN': '仓位规模更新', 'zh-TW': '倉位規模更新', 'en': 'Position size updated',
    'ja': 'ポジション規模を更新', 'ko': '포지션 규모 업데이트', 'es': 'Tamaño de posición actualizado',
    'pt': 'Tamanho da posição atualizado', 'hi': 'पोज़ीशन साइज़ अपडेट',
  },
  'whale_liq_overview': {
    'zh-CN': '链上流动性异动总览', 'zh-TW': '鏈上流動性異動總覽', 'en': 'On-Chain Liquidity Overview',
    'ja': 'オンチェーン流動性概況', 'ko': '온체인 유동성 개요', 'es': 'Panorama de liquidez on-chain',
    'pt': 'Panorama de liquidez on-chain', 'hi': 'ऑन-चेन लिक्विडिटी अवलोकन',
  },
  'whale_listening_24h': {
    'zh-CN': '24H 连续监听', 'zh-TW': '24H 連續監聽', 'en': '24H live monitoring',
    'ja': '24時間連続監視', 'ko': '24시간 연속 모니터링', 'es': 'Monitoreo 24H',
    'pt': 'Monitoramento 24H', 'hi': '24H लाइव मॉनिटरिंग',
  },
  'whale_stable_total': {
    'zh-CN': '稳定币总流通', 'zh-TW': '穩定幣總流通', 'en': 'Total Stablecoin Supply',
    'ja': 'ステーブルコイン総流通', 'ko': '스테이블코인 총 유통', 'es': 'Oferta total de stablecoins',
    'pt': 'Oferta total de stablecoins', 'hi': 'कुल स्टेबलकॉइन सप्लाई',
  },
  'whale_stable_caption': {
    'zh-CN': 'DefiLlama 全稳定币 24H', 'zh-TW': 'DefiLlama 全穩定幣 24H',
    'en': 'DefiLlama all stablecoins 24H', 'ja': 'DefiLlama 全ステーブルコイン 24H',
    'ko': 'DefiLlama 전체 스테이블코인 24H', 'es': 'DefiLlama todas las stablecoins 24H',
    'pt': 'DefiLlama todas as stablecoins 24H', 'hi': 'DefiLlama सभी स्टेबलकॉइन 24H',
  },
  'whale_tvl_total': {
    'zh-CN': 'DeFi 总锁仓 TVL', 'zh-TW': 'DeFi 總鎖倉 TVL', 'en': 'DeFi Total TVL',
    'ja': 'DeFi 総ロック額 TVL', 'ko': 'DeFi 총 예치 TVL', 'es': 'TVL total de DeFi',
    'pt': 'TVL total de DeFi', 'hi': 'DeFi कुल TVL',
  },
  'whale_tvl_caption': {
    'zh-CN': 'DefiLlama 全链锁仓 24H', 'zh-TW': 'DefiLlama 全鏈鎖倉 24H',
    'en': 'DefiLlama all-chain TVL 24H', 'ja': 'DefiLlama 全チェーンロック 24H',
    'ko': 'DefiLlama 전체 체인 예치 24H', 'es': 'DefiLlama TVL de todas las cadenas 24H',
    'pt': 'DefiLlama TVL de todas as cadeias 24H', 'hi': 'DefiLlama ऑल-चेन TVL 24H',
  },
  'whale_top_stable': {
    'zh-CN': 'TOP 稳定币 · 24H', 'zh-TW': 'TOP 穩定幣 · 24H', 'en': 'Top Stablecoins · 24H',
    'ja': 'トップステーブルコイン · 24H', 'ko': '상위 스테이블코인 · 24H', 'es': 'Top stablecoins · 24H',
    'pt': 'Top stablecoins · 24H', 'hi': 'टॉप स्टेबलकॉइन · 24H',
  },
  'whale_circ_change': {
    'zh-CN': '流通 / 涨跌', 'zh-TW': '流通 / 漲跌', 'en': 'Circulating / Change',
    'ja': '流通 / 騰落', 'ko': '유통 / 등락', 'es': 'Circulación / Cambio',
    'pt': 'Circulação / Variação', 'hi': 'सर्कुलेटिंग / बदलाव',
  },
  'whale_filter_all': {
    'zh-CN': '全部', 'zh-TW': '全部', 'en': 'All',
    'ja': 'すべて', 'ko': '전체', 'es': 'Todos',
    'pt': 'Todos', 'hi': 'सभी',
  },
  'whale_filter_position': {
    'zh-CN': '合约仓位异动', 'zh-TW': '合約倉位異動', 'en': 'Position change',
    'ja': 'ポジション変動', 'ko': '계약 포지션 변동', 'es': 'Cambio de posición',
    'pt': 'Mudança de posição', 'hi': 'पोज़ीशन बदलाव',
  },
  'whale_feed_title': {
    'zh-CN': '实时异动高精时间线', 'zh-TW': '實時異動高精時間線', 'en': 'Live Activity Timeline',
    'ja': 'リアルタイム変動タイムライン', 'ko': '실시간 변동 타임라인', 'es': 'Cronología en vivo',
    'pt': 'Linha do tempo ao vivo', 'hi': 'लाइव एक्टिविटी टाइमलाइन',
  },
  'whale_ws_connected': {
    'zh-CN': 'WebSocket 已连通', 'zh-TW': 'WebSocket 已連通', 'en': 'WebSocket connected',
    'ja': 'WebSocket 接続済み', 'ko': 'WebSocket 연결됨', 'es': 'WebSocket conectado',
    'pt': 'WebSocket conectado', 'hi': 'WebSocket कनेक्टेड',
  },
  'whale_no_feed': {
    'zh-CN': '当前筛选下暂无异动', 'zh-TW': '當前篩選下暫無異動', 'en': 'No activity under this filter',
    'ja': 'このフィルターで変動なし', 'ko': '이 필터에서 변동 없음', 'es': 'Sin actividad con este filtro',
    'pt': 'Sem atividade com este filtro', 'hi': 'इस फ़िल्टर में कोई गतिविधि नहीं',
  },
  'whale_detail_link': {
    'zh-CN': '研判详情', 'zh-TW': '研判詳情', 'en': 'Analysis',
    'ja': '分析詳細', 'ko': '분석 상세', 'es': 'Análisis',
    'pt': 'Análise', 'hi': 'विश्लेषण',
  },
  'whale_detail_amount': {
    'zh-CN': '金额', 'zh-TW': '金額', 'en': 'Amount',
    'ja': '金額', 'ko': '금액', 'es': 'Monto',
    'pt': 'Valor', 'hi': 'राशि',
  },
  'whale_detail_value': {
    'zh-CN': '估值', 'zh-TW': '估值', 'en': 'Value',
    'ja': '評価額', 'ko': '평가액', 'es': 'Valor',
    'pt': 'Valor', 'hi': 'मूल्य',
  },
  'whale_detail_chain': {
    'zh-CN': '链/网络', 'zh-TW': '鏈/網絡', 'en': 'Chain/Network',
    'ja': 'チェーン/ネットワーク', 'ko': '체인/네트워크', 'es': 'Cadena/Red',
    'pt': 'Cadeia/Rede', 'hi': 'चेन/नेटवर्क',
  },
  'whale_detail_from': {
    'zh-CN': '转出方', 'zh-TW': '轉出方', 'en': 'From',
    'ja': '送金元', 'ko': '보낸 쪽', 'es': 'Emisor',
    'pt': 'Remetente', 'hi': 'प्रेषक',
  },
  'whale_detail_to': {
    'zh-CN': '接收方', 'zh-TW': '接收方', 'en': 'To',
    'ja': '受取先', 'ko': '받는 쪽', 'es': 'Receptor',
    'pt': 'Destinatário', 'hi': 'प्राप्तकर्ता',
  },
  'whale_interpret_prefix': {
    'zh-CN': '解读: 大额{text}。', 'zh-TW': '解讀: 大額{text}。',
    'en': 'Insight: large {text}.', 'ja': '解読: 大口{text}。',
    'ko': '해석: 대규모 {text}.', 'es': 'Interpretación: gran {text}.',
    'pt': 'Interpretação: grande {text}.', 'hi': 'व्याख्या: बड़ा {text}।',
  },
  'whale_interpret_reduce': {
    'zh-CN': '减仓平仓, 该巨鲸短期看空或止盈', 'zh-TW': '減倉平倉, 該巨鯨短期看空或止盈',
    'en': 'reduction/close suggests the whale is short-term bearish or taking profit',
    'ja': '減倉・決済は短期的な弱気または利確を示唆',
    'ko': '축소·청산은 단기 약세 또는 익절 신호',
    'es': 'la reducción/cierre sugiere visión bajista o toma de ganancias',
    'pt': 'a redução/fecho sugere visão baixista ou realização de lucro',
    'hi': 'घटाना/बंद करना शॉर्ट-टर्म बेयरिश या प्रॉफिट-टेकिंग दर्शाता है',
  },
  'whale_interpret_add': {
    'zh-CN': '加仓开仓, 该巨鲸短期看多', 'zh-TW': '加倉開倉, 該巨鯨短期看多',
    'en': 'adding/opening suggests the whale is short-term bullish',
    'ja': '増倉・新規は短期的な強気を示唆',
    'ko': '증액·신규는 단기 강세 신호',
    'es': 'aumentar/abrir sugiere visión alcista a corto plazo',
    'pt': 'aumentar/abrir sugere visão altista a curto prazo',
    'hi': 'बढ़ाना/खोलना शॉर्ट-टर्म बुलिश दर्शाता है',
  },
  'whale_interpret_move': {
    'zh-CN': '转入交易所通常被视为潜在卖出信号, 需关注后续盘口承接',
    'zh-TW': '轉入交易所通常被視為潛在賣出信號, 需關注後續盤口承接',
    'en': 'moving to an exchange is often a potential sell signal; watch order-book support',
    'ja': '取引所への移動は潜在的な売りシグナルと見なされがち。板の受けに注目',
    'ko': '거래소 이체는 잠재적 매도 신호로 간주되며, 호가창 지지를 주시해야 함',
    'es': 'mover a un exchange suele ser señal de venta potencial; vigila el libro de órdenes',
    'pt': 'mover para uma corretora costuma ser sinal de venda potencial; observe o livro de ofertas',
    'hi': 'एक्सचेंज में भेजना अक्सर संभावित बिक्री संकेत है; ऑर्डर-बुक सपोर्ट देखें',
  },
  'whale_threshold_title': {
    'zh-CN': '巨鲸预警阈值', 'zh-TW': '巨鯨預警閾值', 'en': 'Whale Alert Threshold',
    'ja': 'クジラアラートしきい値', 'ko': '고래 알림 임계값', 'es': 'Umbral de alerta de ballenas',
    'pt': 'Limite de alerta de baleias', 'hi': 'व्हेल अलर्ट थ्रेशोल्ड',
  },
  'whale_threshold_cta': {
    'zh-CN': '设置巨鲸预警阈值', 'zh-TW': '設置巨鯨預警閾值', 'en': 'Set whale alert threshold',
    'ja': 'クジラアラートしきい値を設定', 'ko': '고래 알림 임계값 설정', 'es': 'Configurar umbral de ballenas',
    'pt': 'Definir limite de baleias', 'hi': 'व्हेल अलर्ट थ्रेशोल्ड सेट करें',
  },
  'whale_threshold_set': {
    'zh-CN': '预警阈值: ≥ {v}', 'zh-TW': '預警閾值: ≥ {v}', 'en': 'Threshold: ≥ {v}',
    'ja': 'しきい値: ≥ {v}', 'ko': '임계값: ≥ {v}', 'es': 'Umbral: ≥ {v}',
    'pt': 'Limite: ≥ {v}', 'hi': 'थ्रेशोल्ड: ≥ {v}',
  },

  // ---------------- home_liquidation_page ----------------
  'liq_unit_orders': {
    'zh-CN': '笔强平', 'zh-TW': '筆強平', 'en': 'liquidations',
    'ja': '件の清算', 'ko': '건 강제청산', 'es': 'liquidaciones',
    'pt': 'liquidações', 'hi': 'लिक्विडेशन',
  },
  'liq_unit_people': {
    'zh-CN': '人被爆仓', 'zh-TW': '人被爆倉', 'en': 'traders liquidated',
    'ja': '人が清算', 'ko': '명 청산', 'es': 'traders liquidados',
    'pt': 'traders liquidados', 'hi': 'ट्रेडर लिक्विडेट',
  },
  'liq_unknown_ex': {
    'zh-CN': '未知', 'zh-TW': '未知', 'en': 'Unknown',
    'ja': '不明', 'ko': '알 수 없음', 'es': 'Desconocido',
    'pt': 'Desconhecido', 'hi': 'अज्ञात',
  },
  'liq_all': {
    'zh-CN': '全部', 'zh-TW': '全部', 'en': 'All',
    'ja': 'すべて', 'ko': '전체', 'es': 'Todos',
    'pt': 'Todos', 'hi': 'सभी',
  },
  'liq_all_short': {
    'zh-CN': '全', 'zh-TW': '全', 'en': 'All',
    'ja': '全', 'ko': '전체', 'es': 'T',
    'pt': 'T', 'hi': 'सभी',
  },
  'liq_monitor_title': {
    'zh-CN': '全网多空爆仓实时监控', 'zh-TW': '全網多空爆倉實時監控',
    'en': 'Live Long/Short Liquidation Monitor', 'ja': '全ネットロング/ショート清算リアルタイム監視',
    'ko': '전체 롱/숏 청산 실시간 모니터', 'es': 'Monitor de liquidaciones long/short en vivo',
    'pt': 'Monitor de liquidações long/short ao vivo', 'hi': 'लाइव लॉन्ग/शॉर्ट लिक्विडेशन मॉनिटर',
  },
  'liq_long_short_pct': {
    'zh-CN': '多单 {long}% · 空单 {short}%', 'zh-TW': '多單 {long}% · 空單 {short}%',
    'en': 'Long {long}% · Short {short}%', 'ja': 'ロング {long}% · ショート {short}%',
    'ko': '롱 {long}% · 숏 {short}%', 'es': 'Long {long}% · Short {short}%',
    'pt': 'Long {long}% · Short {short}%', 'hi': 'लॉन्ग {long}% · शॉर्ट {short}%',
  },
  'liq_long_liq': {
    'zh-CN': '多头爆仓', 'zh-TW': '多頭爆倉', 'en': 'Long liquidated',
    'ja': 'ロング清算', 'ko': '롱 청산', 'es': 'Long liquidado',
    'pt': 'Long liquidado', 'hi': 'लॉन्ग लिक्विडेट',
  },
  'liq_short_liq': {
    'zh-CN': '空头爆仓', 'zh-TW': '空頭爆倉', 'en': 'Short liquidated',
    'ja': 'ショート清算', 'ko': '숏 청산', 'es': 'Short liquidado',
    'pt': 'Short liquidado', 'hi': 'शॉर्ट लिक्विडेट',
  },
  'liq_long_pos': {
    'zh-CN': '多单爆仓', 'zh-TW': '多單爆倉', 'en': 'Long liquidations',
    'ja': 'ロング清算', 'ko': '롱 청산', 'es': 'Liquidaciones long',
    'pt': 'Liquidações long', 'hi': 'लॉन्ग लिक्विडेशन',
  },
  'liq_short_pos': {
    'zh-CN': '空单爆仓', 'zh-TW': '空單爆倉', 'en': 'Short liquidations',
    'ja': 'ショート清算', 'ko': '숏 청산', 'es': 'Liquidaciones short',
    'pt': 'Liquidações short', 'hi': 'शॉर्ट लिक्विडेशन',
  },
  'liq_total_title': {
    'zh-CN': '总爆仓', 'zh-TW': '總爆倉', 'en': 'Total Liquidations',
    'ja': '総清算', 'ko': '총 청산', 'es': 'Liquidaciones totales',
    'pt': 'Liquidações totais', 'hi': 'कुल लिक्विडेशन',
  },
  'liq_total_trailing': {
    'zh-CN': '全网多空清洗测度', 'zh-TW': '全網多空清洗測度', 'en': 'Network flush gauge',
    'ja': '全ネットロング/ショート洗浄指標', 'ko': '전체 롱/숏 플러시 측정',
    'es': 'Medidor de limpieza long/short', 'pt': 'Medidor de limpeza long/short',
    'hi': 'नेटवर्क फ्लश गेज',
  },
  'liq_1h': {
    'zh-CN': '1小时爆仓', 'zh-TW': '1小時爆倉', 'en': '1H liquidations',
    'ja': '1時間清算', 'ko': '1시간 청산', 'es': 'Liquidaciones 1H',
    'pt': 'Liquidações 1H', 'hi': '1H लिक्विडेशन',
  },
  'liq_4h': {
    'zh-CN': '4小时爆仓', 'zh-TW': '4小時爆倉', 'en': '4H liquidations',
    'ja': '4時間清算', 'ko': '4시간 청산', 'es': 'Liquidaciones 4H',
    'pt': 'Liquidações 4H', 'hi': '4H लिक्विडेशन',
  },
  'liq_12h': {
    'zh-CN': '12小时爆仓', 'zh-TW': '12小時爆倉', 'en': '12H liquidations',
    'ja': '12時間清算', 'ko': '12시간 청산', 'es': 'Liquidaciones 12H',
    'pt': 'Liquidações 12H', 'hi': '12H लिक्विडेशन',
  },
  'liq_24h': {
    'zh-CN': '24小时爆仓', 'zh-TW': '24小時爆倉', 'en': '24H liquidations',
    'ja': '24時間清算', 'ko': '24시간 청산', 'es': 'Liquidaciones 24H',
    'pt': 'Liquidações 24H', 'hi': '24H लिक्विडेशन',
  },
  'liq_summary_24h_pre': {
    'zh-CN': '最近24小时共记录 ', 'zh-TW': '最近24小時共記錄 ',
    'en': 'In the last 24h, ', 'ja': '直近24時間で ',
    'ko': '최근 24시간 동안 ', 'es': 'En las últimas 24h, ',
    'pt': 'Nas últimas 24h, ', 'hi': 'पिछले 24 घंटों में ',
  },
  'liq_summary_24h_mid': {
    'zh-CN': '，爆仓总金额为 ', 'zh-TW': '，爆倉總金額為 ',
    'en': ' totaling ', 'ja': '、清算総額は ',
    'ko': ', 총 청산 금액은 ', 'es': ' con un total de ',
    'pt': ' totalizando ', 'hi': ' कुल ',
  },
  'liq_largest_pre': {
    'zh-CN': '最大单笔爆仓单发生在 ', 'zh-TW': '最大單筆爆倉單發生在 ',
    'en': 'Largest single liquidation at ', 'ja': '最大単一清算は ',
    'ko': '최대 단일 청산 발생 ', 'es': 'Mayor liquidación única en ',
    'pt': 'Maior liquidação única em ', 'hi': 'सबसे बड़ा एकल लिक्विडेशन ',
  },
  'liq_largest_mid': {
    'zh-CN': ' 价值 ', 'zh-TW': ' 價值 ',
    'en': ' worth ', 'ja': ' 額 ',
    'ko': ' 가치 ', 'es': ' por valor de ',
    'pt': ' no valor de ', 'hi': ' मूल्य ',
  },
  'liq_heatmap_title': {
    'zh-CN': '交易所爆仓热力分布', 'zh-TW': '交易所爆倉熱力分佈',
    'en': 'Exchange Liquidation Heatmap', 'ja': '取引所清算ヒートマップ',
    'ko': '거래소 청산 히트맵', 'es': 'Mapa de calor de liquidaciones por exchange',
    'pt': 'Mapa de calor de liquidações por corretora', 'hi': 'एक्सचेंज लिक्विडेशन हीटमैप',
  },
  'liq_heatmap_trailing': {
    'zh-CN': '合约全网体量图', 'zh-TW': '合約全網體量圖', 'en': 'Network futures volume map',
    'ja': '全ネット先物出来高マップ', 'ko': '전체 선물 볼륨 맵', 'es': 'Mapa de volumen de futuros',
    'pt': 'Mapa de volume de futuros', 'hi': 'नेटवर्क फ्यूचर्स वॉल्यूम मैप',
  },
  'liq_binance_sub': {
    'zh-CN': '币安合约', 'zh-TW': '幣安合約', 'en': 'Binance Futures',
    'ja': 'Binance 先物', 'ko': '바이낸스 선물', 'es': 'Futuros de Binance',
    'pt': 'Futuros da Binance', 'hi': 'बिनेंस फ्यूचर्स',
  },
  'liq_okx_sub': {
    'zh-CN': '欧易', 'zh-TW': '歐易', 'en': 'OKX',
    'ja': 'OKX', 'ko': 'OKX', 'es': 'OKX',
    'pt': 'OKX', 'hi': 'OKX',
  },
  'liq_share': {
    'zh-CN': '占比', 'zh-TW': '佔比', 'en': 'Share',
    'ja': 'シェア', 'ko': '비중', 'es': 'Participación',
    'pt': 'Participação', 'hi': 'शेयर',
  },
  'liq_long_dominant': {
    'zh-CN': '多头清算主导', 'zh-TW': '多頭清算主導', 'en': 'Long liquidations dominate',
    'ja': 'ロング清算優位', 'ko': '롱 청산 우세', 'es': 'Dominan las liquidaciones long',
    'pt': 'Liquidações long dominam', 'hi': 'लॉन्ग लिक्विडेशन प्रमुख',
  },
  'liq_short_dominant': {
    'zh-CN': '空头清算主导', 'zh-TW': '空頭清算主導', 'en': 'Short liquidations dominate',
    'ja': 'ショート清算優位', 'ko': '숏 청산 우세', 'es': 'Dominan las liquidaciones short',
    'pt': 'Liquidações short dominam', 'hi': 'शॉर्ट लिक्विडेशन प्रमुख',
  },
  'liq_realtime_note': {
    'zh-CN': '实时根据成交刷新', 'zh-TW': '實時根據成交刷新', 'en': 'Updated live by trades',
    'ja': '約定に応じてリアルタイム更新', 'ko': '체결에 따라 실시간 갱신', 'es': 'Actualizado en vivo por operaciones',
    'pt': 'Atualizado ao vivo por negociações', 'hi': 'ट्रेड से लाइव अपडेट',
  },
  'liq_exchange_stats': {
    'zh-CN': '交易所爆仓统计', 'zh-TW': '交易所爆倉統計', 'en': 'Exchange Liquidation Stats',
    'ja': '取引所清算統計', 'ko': '거래소 청산 통계', 'es': 'Estadísticas de liquidación por exchange',
    'pt': 'Estatísticas de liquidação por corretora', 'hi': 'एक्सचेंज लिक्विडेशन आँकड़े',
  },
  'liq_range_1h': {
    'zh-CN': '1小时', 'zh-TW': '1小時', 'en': '1H',
    'ja': '1時間', 'ko': '1시간', 'es': '1H',
    'pt': '1H', 'hi': '1H',
  },
  'liq_range_4h': {
    'zh-CN': '4小时', 'zh-TW': '4小時', 'en': '4H',
    'ja': '4時間', 'ko': '4시간', 'es': '4H',
    'pt': '4H', 'hi': '4H',
  },
  'liq_range_12h': {
    'zh-CN': '12小时', 'zh-TW': '12小時', 'en': '12H',
    'ja': '12時間', 'ko': '12시간', 'es': '12H',
    'pt': '12H', 'hi': '12H',
  },
  'liq_range_24h': {
    'zh-CN': '24小时', 'zh-TW': '24小時', 'en': '24H',
    'ja': '24時間', 'ko': '24시간', 'es': '24H',
    'pt': '24H', 'hi': '24H',
  },
  'liq_col_exchange': {
    'zh-CN': '交易所', 'zh-TW': '交易所', 'en': 'Exchange',
    'ja': '取引所', 'ko': '거래소', 'es': 'Exchange',
    'pt': 'Corretora', 'hi': 'एक्सचेंज',
  },
  'liq_col_share': {
    'zh-CN': '占比', 'zh-TW': '佔比', 'en': 'Share',
    'ja': 'シェア', 'ko': '비중', 'es': 'Participación',
    'pt': 'Participação', 'hi': 'शेयर',
  },
  'liq_col_price': {
    'zh-CN': '价格', 'zh-TW': '價格', 'en': 'Price',
    'ja': '価格', 'ko': '가격', 'es': 'Precio',
    'pt': 'Preço', 'hi': 'कीमत',
  },
  'liq_col_amount': {
    'zh-CN': '爆仓金额', 'zh-TW': '爆倉金額', 'en': 'Amount',
    'ja': '清算額', 'ko': '청산 금액', 'es': 'Monto liquidado',
    'pt': 'Valor liquidado', 'hi': 'लिक्विडेशन राशि',
  },
  'liq_col_time': {
    'zh-CN': '时间', 'zh-TW': '時間', 'en': 'Time',
    'ja': '時刻', 'ko': '시간', 'es': 'Hora',
    'pt': 'Hora', 'hi': 'समय',
  },
  'liq_realtime_title': {
    'zh-CN': '实时爆仓', 'zh-TW': '實時爆倉', 'en': 'Live Liquidations',
    'ja': 'リアルタイム清算', 'ko': '실시간 청산', 'es': 'Liquidaciones en vivo',
    'pt': 'Liquidações ao vivo', 'hi': 'लाइव लिक्विडेशन',
  },
  'liq_ge_1k': {
    'zh-CN': '≥ 1千', 'zh-TW': '≥ 1千', 'en': '≥ 1K',
    'ja': '≥ 1千', 'ko': '≥ 1천', 'es': '≥ 1K',
    'pt': '≥ 1K', 'hi': '≥ 1K',
  },
  'liq_ge_1w': {
    'zh-CN': '≥ 1万', 'zh-TW': '≥ 1萬', 'en': '≥ 10K',
    'ja': '≥ 1万', 'ko': '≥ 1만', 'es': '≥ 10K',
    'pt': '≥ 10K', 'hi': '≥ 10K',
  },
  'liq_ge_10w': {
    'zh-CN': '≥ 10万', 'zh-TW': '≥ 10萬', 'en': '≥ 100K',
    'ja': '≥ 10万', 'ko': '≥ 10만', 'es': '≥ 100K',
    'pt': '≥ 100K', 'hi': '≥ 100K',
  },
  'liq_ge_100w': {
    'zh-CN': '≥ 100万', 'zh-TW': '≥ 100萬', 'en': '≥ 1M',
    'ja': '≥ 100万', 'ko': '≥ 100만', 'es': '≥ 1M',
    'pt': '≥ 1M', 'hi': '≥ 1M',
  },
  'liq_no_match': {
    'zh-CN': '暂无符合筛选的爆仓单', 'zh-TW': '暫無符合篩選的爆倉單',
    'en': 'No liquidations match this filter', 'ja': 'このフィルターに合う清算なし',
    'ko': '필터에 맞는 청산 없음', 'es': 'Ninguna liquidación coincide con el filtro',
    'pt': 'Nenhuma liquidação corresponde ao filtro', 'hi': 'इस फ़िल्टर से कोई लिक्विडेशन नहीं',
  },
  'liq_long_forced': {
    'zh-CN': '做多强平', 'zh-TW': '做多強平', 'en': 'Long liquidated',
    'ja': 'ロング強制決済', 'ko': '롱 강제청산', 'es': 'Long liquidado',
    'pt': 'Long liquidado', 'hi': 'लॉन्ग लिक्विडेट',
  },
  'liq_short_forced': {
    'zh-CN': '做空强平', 'zh-TW': '做空強平', 'en': 'Short liquidated',
    'ja': 'ショート強制決済', 'ko': '숏 강제청산', 'es': 'Short liquidado',
    'pt': 'Short liquidado', 'hi': 'शॉर्ट लिक्विडेट',
  },
};
