/// 页面翻译分组 3: 资讯 / 宏观日历 / 行情详情 / 好友 / 群聊 / 通话.
/// 结构: { key: { langCode: text } }.
/// langCode: zh-CN/zh-TW/en/ja/ko/es/pt/hi.
/// 变量用 {name}/{n}/{date}/{week}/{symbol} 等占位符, 页面里 replaceAll 注入.
final Map<String, Map<String, String>> table = {
  // ---------------- 共用 ----------------
  'delete': {
    'zh-CN': '删除', 'zh-TW': '刪除', 'en': 'Delete',
    'ja': '削除', 'ko': '삭제', 'es': 'Eliminar',
    'pt': 'Excluir', 'hi': 'हटाएँ',
  },

  // ---------------- news_page / news_detail_page (news_) ----------------
  'news_today': {
    'zh-CN': '今天', 'zh-TW': '今天', 'en': 'Today',
    'ja': '今日', 'ko': '오늘', 'es': 'Hoy',
    'pt': 'Hoje', 'hi': 'आज',
  },
  'news_yesterday': {
    'zh-CN': '昨天', 'zh-TW': '昨天', 'en': 'Yesterday',
    'ja': '昨日', 'ko': '어제', 'es': 'Ayer',
    'pt': 'Ontem', 'hi': 'कल',
  },
  'news_policy': {
    'zh-CN': '政策', 'zh-TW': '政策', 'en': 'Policy',
    'ja': '政策', 'ko': '정책', 'es': 'Política',
    'pt': 'Política', 'hi': 'नीति',
  },
  'news_no_more': {
    'zh-CN': '没有更多了', 'zh-TW': '沒有更多了', 'en': 'No more',
    'ja': 'これ以上ありません', 'ko': '더 이상 없음', 'es': 'No hay más',
    'pt': 'Não há mais', 'hi': 'और कुछ नहीं',
  },
  'news_load_more': {
    'zh-CN': '加载更多', 'zh-TW': '載入更多', 'en': 'Load more',
    'ja': 'さらに読み込む', 'ko': '더 보기', 'es': 'Cargar más',
    'pt': 'Carregar mais', 'hi': 'और लोड करें',
  },
  'news_load_failed': {
    'zh-CN': '加载失败', 'zh-TW': '載入失敗', 'en': 'Load failed',
    'ja': '読み込みに失敗しました', 'ko': '로드 실패', 'es': 'Error al cargar',
    'pt': 'Falha ao carregar', 'hi': 'लोड विफल',
  },
  'news_retry': {
    'zh-CN': '重试', 'zh-TW': '重試', 'en': 'Retry',
    'ja': '再試行', 'ko': '다시 시도', 'es': 'Reintentar',
    'pt': 'Tentar novamente', 'hi': 'पुनः प्रयास',
  },
  'news_refresh': {
    'zh-CN': '刷新', 'zh-TW': '重新整理', 'en': 'Refresh',
    'ja': '更新', 'ko': '새로고침', 'es': 'Actualizar',
    'pt': 'Atualizar', 'hi': 'रीफ्रेश',
  },
  'news_breaking': {
    'zh-CN': '突发头条', 'zh-TW': '突發頭條', 'en': 'Breaking',
    'ja': '速報トップ', 'ko': '속보 헤드라인', 'es': 'Última hora',
    'pt': 'Últimas', 'hi': 'ब्रेकिंग',
  },
  'news_flash_24': {
    'zh-CN': '7×24 快讯', 'zh-TW': '7×24 快訊', 'en': '7×24 Flash',
    'ja': '7×24 速報', 'ko': '7×24 속보', 'es': 'Flash 7×24',
    'pt': 'Flash 7×24', 'hi': '7×24 फ़्लैश',
  },
  'news_streaming': {
    'zh-CN': '/ 自动流送中', 'zh-TW': '/ 自動流送中', 'en': '/ Live',
    'ja': '/ 自動配信中', 'ko': '/ 자동 스트리밍 중', 'es': '/ En vivo',
    'pt': '/ Ao vivo', 'hi': '/ लाइव',
  },
  'news_bullish': {
    'zh-CN': '利好', 'zh-TW': '利好', 'en': 'Bullish',
    'ja': '好材料', 'ko': '호재', 'es': 'Alcista',
    'pt': 'Altista', 'hi': 'तेज़ी',
  },
  'news_bearish': {
    'zh-CN': '利空', 'zh-TW': '利空', 'en': 'Bearish',
    'ja': '悪材料', 'ko': '악재', 'es': 'Bajista',
    'pt': 'Baixista', 'hi': 'मंदी',
  },
  'news_view_detail': {
    'zh-CN': '查看详情', 'zh-TW': '查看詳情', 'en': 'View details',
    'ja': '詳細を見る', 'ko': '자세히 보기', 'es': 'Ver detalles',
    'pt': 'Ver detalhes', 'hi': 'विवरण देखें',
  },
  // ---- 详情页 ----
  'news_detail_title': {
    'zh-CN': '资讯详情', 'zh-TW': '資訊詳情', 'en': 'News Detail',
    'ja': 'ニュース詳細', 'ko': '뉴스 상세', 'es': 'Detalle',
    'pt': 'Detalhe', 'hi': 'समाचार विवरण',
  },
  'news_research': {
    'zh-CN': '研报', 'zh-TW': '研報', 'en': 'Research',
    'ja': 'レポート', 'ko': '리포트', 'es': 'Informe',
    'pt': 'Relatório', 'hi': 'रिपोर्ट',
  },
  'news_no_content': {
    'zh-CN': '暂无正文内容', 'zh-TW': '暫無正文內容', 'en': 'No content',
    'ja': '本文がありません', 'ko': '본문 없음', 'es': 'Sin contenido',
    'pt': 'Sem conteúdo', 'hi': 'कोई सामग्री नहीं',
  },
  'news_view_original': {
    'zh-CN': '查看原文', 'zh-TW': '查看原文', 'en': 'View original',
    'ja': '原文を見る', 'ko': '원문 보기', 'es': 'Ver original',
    'pt': 'Ver original', 'hi': 'मूल देखें',
  },
  'news_like': {
    'zh-CN': '点赞', 'zh-TW': '點讚', 'en': 'Like',
    'ja': 'いいね', 'ko': '좋아요', 'es': 'Me gusta',
    'pt': 'Curtir', 'hi': 'पसंद',
  },
  'news_comment': {
    'zh-CN': '评论', 'zh-TW': '評論', 'en': 'Comment',
    'ja': 'コメント', 'ko': '댓글', 'es': 'Comentar',
    'pt': 'Comentar', 'hi': 'टिप्पणी',
  },
  'news_favorite': {
    'zh-CN': '收藏', 'zh-TW': '收藏', 'en': 'Favorite',
    'ja': 'お気に入り', 'ko': '즐겨찾기', 'es': 'Favorito',
    'pt': 'Favorito', 'hi': 'पसंदीदा',
  },
  'news_share': {
    'zh-CN': '分享', 'zh-TW': '分享', 'en': 'Share',
    'ja': '共有', 'ko': '공유', 'es': 'Compartir',
    'pt': 'Compartilhar', 'hi': 'साझा करें',
  },
  'news_login_to_comment': {
    'zh-CN': '登录后参与评论', 'zh-TW': '登入後參與評論', 'en': 'Log in to comment',
    'ja': 'ログインしてコメント', 'ko': '로그인 후 댓글 작성', 'es': 'Inicia sesión para comentar',
    'pt': 'Faça login para comentar', 'hi': 'टिप्पणी करने के लिए लॉग इन करें',
  },
  'news_comment_hint': {
    'zh-CN': '写下你的看法...', 'zh-TW': '寫下你的看法...', 'en': 'Share your thoughts...',
    'ja': 'コメントを入力...', 'ko': '의견을 남겨주세요...', 'es': 'Escribe tu opinión...',
    'pt': 'Escreva sua opinião...', 'hi': 'अपनी राय लिखें...',
  },
  'news_reply_to': {
    'zh-CN': '回复 @{name}', 'zh-TW': '回覆 @{name}', 'en': 'Reply to @{name}',
    'ja': '@{name} に返信', 'ko': '@{name}에게 답글', 'es': 'Responder a @{name}',
    'pt': 'Responder a @{name}', 'hi': '@{name} को उत्तर दें',
  },
  'news_reply_hint': {
    'zh-CN': '回复 @{name}...', 'zh-TW': '回覆 @{name}...', 'en': 'Reply to @{name}...',
    'ja': '@{name} に返信...', 'ko': '@{name}에게 답글...', 'es': 'Responder a @{name}...',
    'pt': 'Responder a @{name}...', 'hi': '@{name} को उत्तर दें...',
  },
  'news_send': {
    'zh-CN': '发送', 'zh-TW': '發送', 'en': 'Send',
    'ja': '送信', 'ko': '보내기', 'es': 'Enviar',
    'pt': 'Enviar', 'hi': 'भेजें',
  },
  'news_reply': {
    'zh-CN': '回复', 'zh-TW': '回覆', 'en': 'Reply',
    'ja': '返信', 'ko': '답글', 'es': 'Responder',
    'pt': 'Responder', 'hi': 'उत्तर दें',
  },
  'news_no_comments': {
    'zh-CN': '暂无评论, 来抢沙发', 'zh-TW': '暫無評論, 來搶沙發', 'en': 'No comments yet, be the first',
    'ja': 'コメントはまだありません', 'ko': '댓글이 없습니다. 첫 댓글을 남겨보세요', 'es': 'Sin comentarios, sé el primero',
    'pt': 'Sem comentários, seja o primeiro', 'hi': 'अभी कोई टिप्पणी नहीं, पहले बनें',
  },
  'news_no_replies': {
    'zh-CN': '暂无回复', 'zh-TW': '暫無回覆', 'en': 'No replies',
    'ja': '返信はありません', 'ko': '답글 없음', 'es': 'Sin respuestas',
    'pt': 'Sem respostas', 'hi': 'कोई उत्तर नहीं',
  },
  'news_collapse_replies': {
    'zh-CN': '收起回复', 'zh-TW': '收起回覆', 'en': 'Collapse replies',
    'ja': '返信を折りたたむ', 'ko': '답글 접기', 'es': 'Contraer respuestas',
    'pt': 'Recolher respostas', 'hi': 'उत्तर समेटें',
  },
  'news_view_replies': {
    'zh-CN': '查看 {n} 条回复', 'zh-TW': '查看 {n} 條回覆', 'en': 'View {n} replies',
    'ja': '{n} 件の返信を見る', 'ko': '답글 {n}개 보기', 'es': 'Ver {n} respuestas',
    'pt': 'Ver {n} respostas', 'hi': '{n} उत्तर देखें',
  },
  'news_anonymous': {
    'zh-CN': '匿名用户', 'zh-TW': '匿名用戶', 'en': 'Anonymous',
    'ja': '匿名ユーザー', 'ko': '익명 사용자', 'es': 'Anónimo',
    'pt': 'Anônimo', 'hi': 'गुमनाम',
  },
  'news_anon_initial': {
    'zh-CN': '匿', 'zh-TW': '匿', 'en': 'A',
    'ja': '匿', 'ko': '익', 'es': 'A',
    'pt': 'A', 'hi': 'गु',
  },
  'news_delete_comment': {
    'zh-CN': '删除评论', 'zh-TW': '刪除評論', 'en': 'Delete comment',
    'ja': 'コメントを削除', 'ko': '댓글 삭제', 'es': 'Eliminar comentario',
    'pt': 'Excluir comentário', 'hi': 'टिप्पणी हटाएँ',
  },
  'news_delete_comment_hint': {
    'zh-CN': '确定删除这条评论吗?', 'zh-TW': '確定刪除這條評論嗎?', 'en': 'Delete this comment?',
    'ja': 'このコメントを削除しますか?', 'ko': '이 댓글을 삭제하시겠습니까?', 'es': '¿Eliminar este comentario?',
    'pt': 'Excluir este comentário?', 'hi': 'क्या यह टिप्पणी हटाएँ?',
  },
  'news_comment_published': {
    'zh-CN': '评论已发布', 'zh-TW': '評論已發佈', 'en': 'Comment posted',
    'ja': 'コメントを投稿しました', 'ko': '댓글이 게시되었습니다', 'es': 'Comentario publicado',
    'pt': 'Comentário publicado', 'hi': 'टिप्पणी प्रकाशित हुई',
  },
  'news_publish_failed': {
    'zh-CN': '发布失败, 请重试', 'zh-TW': '發佈失敗, 請重試', 'en': 'Post failed, please retry',
    'ja': '投稿に失敗しました。再試行してください', 'ko': '게시 실패, 다시 시도하세요', 'es': 'Error al publicar, reintenta',
    'pt': 'Falha ao publicar, tente novamente', 'hi': 'प्रकाशन विफल, पुनः प्रयास करें',
  },
  'news_deleted': {
    'zh-CN': '已删除', 'zh-TW': '已刪除', 'en': 'Deleted',
    'ja': '削除しました', 'ko': '삭제됨', 'es': 'Eliminado',
    'pt': 'Excluído', 'hi': 'हटाया गया',
  },
  'news_delete_failed': {
    'zh-CN': '删除失败', 'zh-TW': '刪除失敗', 'en': 'Delete failed',
    'ja': '削除に失敗しました', 'ko': '삭제 실패', 'es': 'Error al eliminar',
    'pt': 'Falha ao excluir', 'hi': 'हटाना विफल',
  },
  'news_comments_failed_retry': {
    'zh-CN': '评论加载失败, 点击重试', 'zh-TW': '評論載入失敗, 點擊重試', 'en': 'Failed to load comments, tap to retry',
    'ja': 'コメントの読み込みに失敗しました。タップで再試行', 'ko': '댓글 로드 실패, 탭하여 재시도', 'es': 'Error al cargar comentarios, toca para reintentar',
    'pt': 'Falha ao carregar comentários, toque para tentar', 'hi': 'टिप्पणियाँ लोड विफल, पुनः प्रयास के लिए टैप करें',
  },
  'news_op_failed': {
    'zh-CN': '操作失败, 请重试', 'zh-TW': '操作失敗, 請重試', 'en': 'Operation failed, please retry',
    'ja': '操作に失敗しました。再試行してください', 'ko': '작업 실패, 다시 시도하세요', 'es': 'Operación fallida, reintenta',
    'pt': 'Operação falhou, tente novamente', 'hi': 'कार्रवाई विफल, पुनः प्रयास करें',
  },
  'news_favorited': {
    'zh-CN': '已收藏', 'zh-TW': '已收藏', 'en': 'Favorited',
    'ja': 'お気に入りに追加しました', 'ko': '즐겨찾기 추가됨', 'es': 'Añadido a favoritos',
    'pt': 'Adicionado aos favoritos', 'hi': 'पसंदीदा में जोड़ा गया',
  },
  'news_unfavorited': {
    'zh-CN': '已取消收藏', 'zh-TW': '已取消收藏', 'en': 'Removed from favorites',
    'ja': 'お気に入りを解除しました', 'ko': '즐겨찾기 해제됨', 'es': 'Eliminado de favoritos',
    'pt': 'Removido dos favoritos', 'hi': 'पसंदीदा से हटाया गया',
  },
  'news_link_invalid': {
    'zh-CN': '链接无效', 'zh-TW': '連結無效', 'en': 'Invalid link',
    'ja': '無効なリンク', 'ko': '유효하지 않은 링크', 'es': 'Enlace no válido',
    'pt': 'Link inválido', 'hi': 'अमान्य लिंक',
  },
  'news_link_cannot_open': {
    'zh-CN': '无法打开链接', 'zh-TW': '無法開啟連結', 'en': 'Cannot open link',
    'ja': 'リンクを開けません', 'ko': '링크를 열 수 없습니다', 'es': 'No se puede abrir el enlace',
    'pt': 'Não foi possível abrir o link', 'hi': 'लिंक नहीं खुल सका',
  },

  // ---------------- macro_calendar_page (cal_) ----------------
  'cal_title': {
    'zh-CN': '宏观日历', 'zh-TW': '宏觀日曆', 'en': 'Macro Calendar',
    'ja': 'マクロカレンダー', 'ko': '매크로 캘린더', 'es': 'Calendario macro',
    'pt': 'Calendário macro', 'hi': 'मैक्रो कैलेंडर',
  },
  'cal_today': {
    'zh-CN': '今天', 'zh-TW': '今天', 'en': 'Today',
    'ja': '今日', 'ko': '오늘', 'es': 'Hoy',
    'pt': 'Hoje', 'hi': 'आज',
  },
  'cal_weekdays': {
    'zh-CN': '一,二,三,四,五,六,日', 'zh-TW': '一,二,三,四,五,六,日', 'en': 'Mon,Tue,Wed,Thu,Fri,Sat,Sun',
    'ja': '月,火,水,木,金,土,日', 'ko': '월,화,수,목,금,토,일', 'es': 'lun,mar,mié,jue,vie,sáb,dom',
    'pt': 'seg,ter,qua,qui,sex,sáb,dom', 'hi': 'सोम,मंगल,बुध,गुरु,शुक्र,शनि,रवि',
  },
  'cal_date_label': {
    'zh-CN': '{date} 星期{week}', 'zh-TW': '{date} 星期{week}', 'en': '{date} {week}',
    'ja': '{date} ({week})', 'ko': '{date} {week}', 'es': '{date} {week}',
    'pt': '{date} {week}', 'hi': '{date} {week}',
  },
  'cal_no_events': {
    'zh-CN': '当日无宏观事件', 'zh-TW': '當日無宏觀事件', 'en': 'No macro events today',
    'ja': '当日のマクロイベントはありません', 'ko': '오늘의 매크로 이벤트 없음', 'es': 'Sin eventos macro hoy',
    'pt': 'Sem eventos macro hoje', 'hi': 'आज कोई मैक्रो इवेंट नहीं',
  },
  'cal_high': {
    'zh-CN': '高', 'zh-TW': '高', 'en': 'High',
    'ja': '高', 'ko': '높음', 'es': 'Alta',
    'pt': 'Alta', 'hi': 'उच्च',
  },
  'cal_mid': {
    'zh-CN': '中', 'zh-TW': '中', 'en': 'Medium',
    'ja': '中', 'ko': '중간', 'es': 'Media',
    'pt': 'Média', 'hi': 'मध्यम',
  },
  'cal_low': {
    'zh-CN': '低', 'zh-TW': '低', 'en': 'Low',
    'ja': '低', 'ko': '낮음', 'es': 'Baja',
    'pt': 'Baixa', 'hi': 'निम्न',
  },
  'cal_previous': {
    'zh-CN': '前值', 'zh-TW': '前值', 'en': 'Previous',
    'ja': '前回', 'ko': '이전', 'es': 'Previo',
    'pt': 'Anterior', 'hi': 'पिछला',
  },
  'cal_forecast': {
    'zh-CN': '预期', 'zh-TW': '預期', 'en': 'Forecast',
    'ja': '予想', 'ko': '예상', 'es': 'Previsión',
    'pt': 'Previsão', 'hi': 'पूर्वानुमान',
  },
  'cal_actual': {
    'zh-CN': '公布', 'zh-TW': '公佈', 'en': 'Actual',
    'ja': '発表', 'ko': '실제', 'es': 'Publicado',
    'pt': 'Publicado', 'hi': 'वास्तविक',
  },
  'cal_interpretation': {
    'zh-CN': '指标解读', 'zh-TW': '指標解讀', 'en': 'Interpretation',
    'ja': '指標解説', 'ko': '지표 해석', 'es': 'Interpretación',
    'pt': 'Interpretação', 'hi': 'संकेतक विश्लेषण',
  },
  'cal_history': {
    'zh-CN': '历史走势 (近 {n} 期)', 'zh-TW': '歷史走勢 (近 {n} 期)', 'en': 'History (last {n})',
    'ja': '過去の推移 (直近 {n} 期)', 'ko': '과거 추이 (최근 {n}건)', 'es': 'Historial (últimos {n})',
    'pt': 'Histórico (últimos {n})', 'hi': 'इतिहास (पिछले {n})',
  },
  'cal_no_history': {
    'zh-CN': '暂无历史数据', 'zh-TW': '暫無歷史數據', 'en': 'No history data',
    'ja': '過去のデータがありません', 'ko': '과거 데이터 없음', 'es': 'Sin datos históricos',
    'pt': 'Sem dados históricos', 'hi': 'कोई ऐतिहासिक डेटा नहीं',
  },
  'cal_above_forecast': {
    'zh-CN': '高于预期', 'zh-TW': '高於預期', 'en': 'Above forecast',
    'ja': '予想上回る', 'ko': '예상 상회', 'es': 'Por encima',
    'pt': 'Acima do previsto', 'hi': 'अनुमान से ऊपर',
  },
  'cal_below_forecast': {
    'zh-CN': '低于预期', 'zh-TW': '低於預期', 'en': 'Below forecast',
    'ja': '予想下回る', 'ko': '예상 하회', 'es': 'Por debajo',
    'pt': 'Abaixo do previsto', 'hi': 'अनुमान से नीचे',
  },
  'cal_meets_forecast': {
    'zh-CN': '符合预期', 'zh-TW': '符合預期', 'en': 'In line',
    'ja': '予想通り', 'ko': '예상 부합', 'es': 'En línea',
    'pt': 'Em linha', 'hi': 'अनुमान के अनुरूप',
  },

  // ---------------- market_detail_page (mktd_) ----------------
  'mktd_perp': {
    'zh-CN': '永续', 'zh-TW': '永續', 'en': 'Perp',
    'ja': '無期限', 'ko': '무기한', 'es': 'Perpetuo',
    'pt': 'Perpétuo', 'hi': 'परपेचुअल',
  },
  'mktd_spot': {
    'zh-CN': '现货', 'zh-TW': '現貨', 'en': 'Spot',
    'ja': '現物', 'ko': '현물', 'es': 'Spot',
    'pt': 'Spot', 'hi': 'स्पॉट',
  },
  'mktd_high_24h': {
    'zh-CN': '24H 最高', 'zh-TW': '24H 最高', 'en': '24H High',
    'ja': '24H 高値', 'ko': '24H 최고', 'es': 'Máx 24H',
    'pt': 'Máx 24H', 'hi': '24H उच्च',
  },
  'mktd_low_24h': {
    'zh-CN': '24H 最低', 'zh-TW': '24H 最低', 'en': '24H Low',
    'ja': '24H 安値', 'ko': '24H 최저', 'es': 'Mín 24H',
    'pt': 'Mín 24H', 'hi': '24H निम्न',
  },
  'mktd_change_24h': {
    'zh-CN': '24H 涨跌额', 'zh-TW': '24H 漲跌額', 'en': '24H Change',
    'ja': '24H 変動額', 'ko': '24H 변동액', 'es': 'Cambio 24H',
    'pt': 'Variação 24H', 'hi': '24H परिवर्तन',
  },
  'mktd_turnover_24h': {
    'zh-CN': '24H 成交额', 'zh-TW': '24H 成交額', 'en': '24H Turnover',
    'ja': '24H 出来高', 'ko': '24H 거래대금', 'es': 'Volumen 24H',
    'pt': 'Volume 24H', 'hi': '24H टर्नओवर',
  },
  'mktd_open_interest': {
    'zh-CN': '持仓量', 'zh-TW': '持倉量', 'en': 'Open Interest',
    'ja': '建玉', 'ko': '미결제약정', 'es': 'Interés abierto',
    'pt': 'Interesse aberto', 'hi': 'ओपन इंटरेस्ट',
  },
  'mktd_tab_kline': {
    'zh-CN': 'K线', 'zh-TW': 'K線', 'en': 'Chart',
    'ja': 'チャート', 'ko': '차트', 'es': 'Gráfico',
    'pt': 'Gráfico', 'hi': 'चार्ट',
  },
  'mktd_tab_orderbook': {
    'zh-CN': '盘口', 'zh-TW': '盤口', 'en': 'Order Book',
    'ja': '板', 'ko': '호가', 'es': 'Libro',
    'pt': 'Livro', 'hi': 'ऑर्डर बुक',
  },
  'mktd_tab_trades': {
    'zh-CN': '成交', 'zh-TW': '成交', 'en': 'Trades',
    'ja': '約定', 'ko': '체결', 'es': 'Operaciones',
    'pt': 'Negócios', 'hi': 'ट्रेड',
  },
  'mktd_kline_trend': {
    'zh-CN': 'K线走势', 'zh-TW': 'K線走勢', 'en': 'Price Chart',
    'ja': 'チャート走势', 'ko': '차트 추이', 'es': 'Gráfico de precio',
    'pt': 'Gráfico de preço', 'hi': 'मूल्य चार्ट',
  },
  'mktd_no_kline': {
    'zh-CN': '暂无K线数据', 'zh-TW': '暫無K線數據', 'en': 'No chart data',
    'ja': 'チャートデータがありません', 'ko': '차트 데이터 없음', 'es': 'Sin datos de gráfico',
    'pt': 'Sem dados de gráfico', 'hi': 'कोई चार्ट डेटा नहीं',
  },
  'mktd_waiting_orderbook': {
    'zh-CN': '等待盘口数据…', 'zh-TW': '等待盤口數據…', 'en': 'Waiting for order book…',
    'ja': '板データを待機中…', 'ko': '호가 데이터 대기 중…', 'es': 'Esperando libro…',
    'pt': 'Aguardando livro…', 'hi': 'ऑर्डर बुक की प्रतीक्षा…',
  },
  'mktd_price_usdt': {
    'zh-CN': '价格 (USDT)', 'zh-TW': '價格 (USDT)', 'en': 'Price (USDT)',
    'ja': '価格 (USDT)', 'ko': '가격 (USDT)', 'es': 'Precio (USDT)',
    'pt': 'Preço (USDT)', 'hi': 'मूल्य (USDT)',
  },
  'mktd_amount': {
    'zh-CN': '数量 ({symbol})', 'zh-TW': '數量 ({symbol})', 'en': 'Amount ({symbol})',
    'ja': '数量 ({symbol})', 'ko': '수량 ({symbol})', 'es': 'Cantidad ({symbol})',
    'pt': 'Quantidade ({symbol})', 'hi': 'मात्रा ({symbol})',
  },
  'mktd_mark': {
    'zh-CN': '标记', 'zh-TW': '標記', 'en': 'Mark',
    'ja': 'マーク', 'ko': '마크', 'es': 'Marca',
    'pt': 'Marca', 'hi': 'मार्क',
  },
  'mktd_spread': {
    'zh-CN': '价差', 'zh-TW': '價差', 'en': 'Spread',
    'ja': 'スプレッド', 'ko': '스프레드', 'es': 'Spread',
    'pt': 'Spread', 'hi': 'स्प्रेड',
  },
  'mktd_time': {
    'zh-CN': '时间', 'zh-TW': '時間', 'en': 'Time',
    'ja': '時間', 'ko': '시간', 'es': 'Hora',
    'pt': 'Hora', 'hi': 'समय',
  },
  'mktd_waiting_trades': {
    'zh-CN': '等待成交数据…', 'zh-TW': '等待成交數據…', 'en': 'Waiting for trades…',
    'ja': '約定データを待機中…', 'ko': '체결 데이터 대기 중…', 'es': 'Esperando operaciones…',
    'pt': 'Aguardando negócios…', 'hi': 'ट्रेड की प्रतीक्षा…',
  },
  'mktd_funding_rate': {
    'zh-CN': '资金费率', 'zh-TW': '資金費率', 'en': 'Funding Rate',
    'ja': '資金調達率', 'ko': '펀딩 비율', 'es': 'Tasa de financiación',
    'pt': 'Taxa de financiamento', 'hi': 'फंडिंग दर',
  },
  'mktd_current_rate': {
    'zh-CN': '当前费率', 'zh-TW': '當前費率', 'en': 'Current Rate',
    'ja': '現在のレート', 'ko': '현재 비율', 'es': 'Tasa actual',
    'pt': 'Taxa atual', 'hi': 'वर्तमान दर',
  },
  'mktd_next_settle': {
    'zh-CN': '下次结算', 'zh-TW': '下次結算', 'en': 'Next Settlement',
    'ja': '次回清算', 'ko': '다음 정산', 'es': 'Próxima liquidación',
    'pt': 'Próxima liquidação', 'hi': 'अगला निपटान',
  },
  'mktd_search_coin': {
    'zh-CN': '搜索币种', 'zh-TW': '搜索幣種', 'en': 'Search coin',
    'ja': 'コインを検索', 'ko': '코인 검색', 'es': 'Buscar moneda',
    'pt': 'Buscar moeda', 'hi': 'कॉइन खोजें',
  },
  'mktd_contract': {
    'zh-CN': '合约', 'zh-TW': '合約', 'en': 'Futures',
    'ja': '先物', 'ko': '선물', 'es': 'Futuros',
    'pt': 'Futuros', 'hi': 'फ्यूचर्स',
  },
  'mktd_no_match': {
    'zh-CN': '无匹配币种', 'zh-TW': '無匹配幣種', 'en': 'No matching coin',
    'ja': '一致するコインがありません', 'ko': '일치하는 코인 없음', 'es': 'Sin moneda coincidente',
    'pt': 'Nenhuma moeda correspondente', 'hi': 'कोई मेल खाता कॉइन नहीं',
  },

  // ---------------- friends_page (frd_) ----------------
  'frd_title': {
    'zh-CN': '新朋友', 'zh-TW': '新朋友', 'en': 'New Friends',
    'ja': '新しい友達', 'ko': '새 친구', 'es': 'Nuevos amigos',
    'pt': 'Novos amigos', 'hi': 'नए दोस्त',
  },
  'frd_tab_friends': {
    'zh-CN': '好友', 'zh-TW': '好友', 'en': 'Friends',
    'ja': '友達', 'ko': '친구', 'es': 'Amigos',
    'pt': 'Amigos', 'hi': 'दोस्त',
  },
  'frd_tab_requests': {
    'zh-CN': '请求', 'zh-TW': '請求', 'en': 'Requests',
    'ja': 'リクエスト', 'ko': '요청', 'es': 'Solicitudes',
    'pt': 'Solicitações', 'hi': 'अनुरोध',
  },
  'frd_tab_add': {
    'zh-CN': '添加', 'zh-TW': '添加', 'en': 'Add',
    'ja': '追加', 'ko': '추가', 'es': 'Añadir',
    'pt': 'Adicionar', 'hi': 'जोड़ें',
  },
  'frd_open_failed': {
    'zh-CN': '打开会话失败', 'zh-TW': '開啟會話失敗', 'en': 'Failed to open conversation',
    'ja': '会話を開けませんでした', 'ko': '대화 열기 실패', 'es': 'Error al abrir la conversación',
    'pt': 'Falha ao abrir conversa', 'hi': 'वार्तालाप खोलना विफल',
  },
  'frd_delete_friend': {
    'zh-CN': '删除好友', 'zh-TW': '刪除好友', 'en': 'Delete friend',
    'ja': '友達を削除', 'ko': '친구 삭제', 'es': 'Eliminar amigo',
    'pt': 'Excluir amigo', 'hi': 'दोस्त हटाएँ',
  },
  'frd_delete_friend_hint': {
    'zh-CN': '确定删除好友 {name} 吗?', 'zh-TW': '確定刪除好友 {name} 嗎?', 'en': 'Delete friend {name}?',
    'ja': '友達 {name} を削除しますか?', 'ko': '친구 {name}을(를) 삭제하시겠습니까?', 'es': '¿Eliminar al amigo {name}?',
    'pt': 'Excluir o amigo {name}?', 'hi': 'क्या दोस्त {name} को हटाएँ?',
  },
  'frd_deleted': {
    'zh-CN': '已删除', 'zh-TW': '已刪除', 'en': 'Deleted',
    'ja': '削除しました', 'ko': '삭제됨', 'es': 'Eliminado',
    'pt': 'Excluído', 'hi': 'हटाया गया',
  },
  'frd_delete_failed': {
    'zh-CN': '删除失败', 'zh-TW': '刪除失敗', 'en': 'Delete failed',
    'ja': '削除に失敗しました', 'ko': '삭제 실패', 'es': 'Error al eliminar',
    'pt': 'Falha ao excluir', 'hi': 'हटाना विफल',
  },
  'frd_accepted': {
    'zh-CN': '已接受', 'zh-TW': '已接受', 'en': 'Accepted',
    'ja': '承認しました', 'ko': '수락됨', 'es': 'Aceptado',
    'pt': 'Aceito', 'hi': 'स्वीकार किया',
  },
  'frd_rejected': {
    'zh-CN': '已拒绝', 'zh-TW': '已拒絕', 'en': 'Rejected',
    'ja': '拒否しました', 'ko': '거절됨', 'es': 'Rechazado',
    'pt': 'Recusado', 'hi': 'अस्वीकृत',
  },
  'frd_op_failed': {
    'zh-CN': '操作失败', 'zh-TW': '操作失敗', 'en': 'Operation failed',
    'ja': '操作に失敗しました', 'ko': '작업 실패', 'es': 'Operación fallida',
    'pt': 'Operação falhou', 'hi': 'कार्रवाई विफल',
  },
  'frd_request_sent': {
    'zh-CN': '请求已发送', 'zh-TW': '請求已發送', 'en': 'Request sent',
    'ja': 'リクエストを送信しました', 'ko': '요청 전송됨', 'es': 'Solicitud enviada',
    'pt': 'Solicitação enviada', 'hi': 'अनुरोध भेजा गया',
  },
  'frd_send_failed': {
    'zh-CN': '发送失败', 'zh-TW': '發送失敗', 'en': 'Send failed',
    'ja': '送信に失敗しました', 'ko': '전송 실패', 'es': 'Error al enviar',
    'pt': 'Falha ao enviar', 'hi': 'भेजना विफल',
  },
  'frd_no_friends': {
    'zh-CN': '还没有好友, 去「添加」找人吧', 'zh-TW': '還沒有好友, 去「添加」找人吧', 'en': 'No friends yet, go to Add to find people',
    'ja': '友達がいません。「追加」から探しましょう', 'ko': '아직 친구가 없습니다. "추가"에서 찾아보세요', 'es': 'Aún no tienes amigos, ve a Añadir para buscar',
    'pt': 'Ainda sem amigos, vá em Adicionar para encontrar', 'hi': 'अभी कोई दोस्त नहीं, जोड़ें पर जाकर खोजें',
  },
  'frd_no_requests': {
    'zh-CN': '暂无好友请求', 'zh-TW': '暫無好友請求', 'en': 'No friend requests',
    'ja': '友達リクエストはありません', 'ko': '친구 요청 없음', 'es': 'Sin solicitudes de amistad',
    'pt': 'Sem solicitações de amizade', 'hi': 'कोई फ्रेंड रिक्वेस्ट नहीं',
  },
  'frd_incoming': {
    'zh-CN': '收到的请求', 'zh-TW': '收到的請求', 'en': 'Received',
    'ja': '受信したリクエスト', 'ko': '받은 요청', 'es': 'Recibidas',
    'pt': 'Recebidas', 'hi': 'प्राप्त अनुरोध',
  },
  'frd_outgoing': {
    'zh-CN': '我发出的', 'zh-TW': '我發出的', 'en': 'Sent',
    'ja': '送信したリクエスト', 'ko': '보낸 요청', 'es': 'Enviadas',
    'pt': 'Enviadas', 'hi': 'भेजे गए',
  },
  'frd_accept': {
    'zh-CN': '接受', 'zh-TW': '接受', 'en': 'Accept',
    'ja': '承認', 'ko': '수락', 'es': 'Aceptar',
    'pt': 'Aceitar', 'hi': 'स्वीकारें',
  },
  'frd_reject': {
    'zh-CN': '拒绝', 'zh-TW': '拒絕', 'en': 'Reject',
    'ja': '拒否', 'ko': '거절', 'es': 'Rechazar',
    'pt': 'Recusar', 'hi': 'अस्वीकारें',
  },
  'frd_pending': {
    'zh-CN': '等待验证', 'zh-TW': '等待驗證', 'en': 'Pending',
    'ja': '承認待ち', 'ko': '확인 대기 중', 'es': 'Pendiente',
    'pt': 'Pendente', 'hi': 'लंबित',
  },
  'frd_search_hint': {
    'zh-CN': '搜索用户名', 'zh-TW': '搜索用戶名', 'en': 'Search username',
    'ja': 'ユーザー名を検索', 'ko': '사용자 이름 검색', 'es': 'Buscar usuario',
    'pt': 'Buscar usuário', 'hi': 'उपयोगकर्ता नाम खोजें',
  },
  'frd_search_prompt': {
    'zh-CN': '输入用户名搜索', 'zh-TW': '輸入用戶名搜索', 'en': 'Enter a username to search',
    'ja': 'ユーザー名を入力して検索', 'ko': '사용자 이름을 입력하여 검색', 'es': 'Ingresa un usuario para buscar',
    'pt': 'Digite um usuário para buscar', 'hi': 'खोजने के लिए उपयोगकर्ता नाम दर्ज करें',
  },
  'frd_not_found': {
    'zh-CN': '未找到该用户', 'zh-TW': '未找到該用戶', 'en': 'User not found',
    'ja': 'ユーザーが見つかりません', 'ko': '사용자를 찾을 수 없음', 'es': 'Usuario no encontrado',
    'pt': 'Usuário não encontrado', 'hi': 'उपयोगकर्ता नहीं मिला',
  },
  'frd_self': {
    'zh-CN': '自己', 'zh-TW': '自己', 'en': 'You',
    'ja': '自分', 'ko': '나', 'es': 'Tú',
    'pt': 'Você', 'hi': 'आप',
  },
  'frd_sent': {
    'zh-CN': '已发送', 'zh-TW': '已發送', 'en': 'Sent',
    'ja': '送信済み', 'ko': '전송됨', 'es': 'Enviado',
    'pt': 'Enviado', 'hi': 'भेजा गया',
  },
  'frd_add_friend': {
    'zh-CN': '加好友', 'zh-TW': '加好友', 'en': 'Add friend',
    'ja': '友達追加', 'ko': '친구 추가', 'es': 'Añadir amigo',
    'pt': 'Adicionar amigo', 'hi': 'दोस्त जोड़ें',
  },

  // ---------------- group_create_page / group_info_page (grp_) ----------------
  'grp_create_title': {
    'zh-CN': '发起群聊', 'zh-TW': '發起群聊', 'en': 'New Group',
    'ja': 'グループ作成', 'ko': '그룹 만들기', 'es': 'Nuevo grupo',
    'pt': 'Novo grupo', 'hi': 'नया समूह',
  },
  'grp_create': {
    'zh-CN': '创建', 'zh-TW': '創建', 'en': 'Create',
    'ja': '作成', 'ko': '만들기', 'es': 'Crear',
    'pt': 'Criar', 'hi': 'बनाएँ',
  },
  'grp_enter_name': {
    'zh-CN': '请输入群名称', 'zh-TW': '請輸入群名稱', 'en': 'Please enter a group name',
    'ja': 'グループ名を入力してください', 'ko': '그룹 이름을 입력하세요', 'es': 'Ingresa el nombre del grupo',
    'pt': 'Digite o nome do grupo', 'hi': 'कृपया समूह का नाम दर्ज करें',
  },
  'grp_select_member': {
    'zh-CN': '请选择至少一位成员', 'zh-TW': '請選擇至少一位成員', 'en': 'Select at least one member',
    'ja': 'メンバーを1人以上選択してください', 'ko': '최소 한 명의 멤버를 선택하세요', 'es': 'Selecciona al menos un miembro',
    'pt': 'Selecione pelo menos um membro', 'hi': 'कम से कम एक सदस्य चुनें',
  },
  'grp_create_failed': {
    'zh-CN': '创建失败', 'zh-TW': '創建失敗', 'en': 'Create failed',
    'ja': '作成に失敗しました', 'ko': '만들기 실패', 'es': 'Error al crear',
    'pt': 'Falha ao criar', 'hi': 'बनाना विफल',
  },
  'grp_name_hint': {
    'zh-CN': '群名称', 'zh-TW': '群名稱', 'en': 'Group name',
    'ja': 'グループ名', 'ko': '그룹 이름', 'es': 'Nombre del grupo',
    'pt': 'Nome do grupo', 'hi': 'समूह का नाम',
  },
  'grp_select_members': {
    'zh-CN': '选择成员', 'zh-TW': '選擇成員', 'en': 'Select members',
    'ja': 'メンバーを選択', 'ko': '멤버 선택', 'es': 'Seleccionar miembros',
    'pt': 'Selecionar membros', 'hi': 'सदस्य चुनें',
  },
  'grp_selected': {
    'zh-CN': '已选 {n}', 'zh-TW': '已選 {n}', 'en': '{n} selected',
    'ja': '{n} 人選択中', 'ko': '{n}명 선택됨', 'es': '{n} seleccionados',
    'pt': '{n} selecionados', 'hi': '{n} चुने गए',
  },
  'grp_no_friends': {
    'zh-CN': '暂无好友可选', 'zh-TW': '暫無好友可選', 'en': 'No friends available',
    'ja': '選択できる友達がいません', 'ko': '선택할 친구 없음', 'es': 'No hay amigos disponibles',
    'pt': 'Nenhum amigo disponível', 'hi': 'कोई दोस्त उपलब्ध नहीं',
  },
  // ---- 群信息页 ----
  'grp_info_title': {
    'zh-CN': '群聊信息', 'zh-TW': '群聊資訊', 'en': 'Group Info',
    'ja': 'グループ情報', 'ko': '그룹 정보', 'es': 'Info del grupo',
    'pt': 'Info do grupo', 'hi': 'समूह जानकारी',
  },
  'grp_members': {
    'zh-CN': '成员 {n}', 'zh-TW': '成員 {n}', 'en': 'Members {n}',
    'ja': 'メンバー {n}', 'ko': '멤버 {n}', 'es': 'Miembros {n}',
    'pt': 'Membros {n}', 'hi': 'सदस्य {n}',
  },
  'grp_name_label': {
    'zh-CN': '群名', 'zh-TW': '群名', 'en': 'Group name',
    'ja': 'グループ名', 'ko': '그룹 이름', 'es': 'Nombre del grupo',
    'pt': 'Nome do grupo', 'hi': 'समूह का नाम',
  },
  'grp_edit': {
    'zh-CN': '编辑', 'zh-TW': '編輯', 'en': 'Edit',
    'ja': '編集', 'ko': '편집', 'es': 'Editar',
    'pt': 'Editar', 'hi': 'संपादित करें',
  },
  'grp_edit_name': {
    'zh-CN': '修改群名', 'zh-TW': '修改群名', 'en': 'Edit group name',
    'ja': 'グループ名を変更', 'ko': '그룹 이름 변경', 'es': 'Editar nombre del grupo',
    'pt': 'Editar nome do grupo', 'hi': 'समूह का नाम बदलें',
  },
  'grp_name_input_hint': {
    'zh-CN': '输入群名', 'zh-TW': '輸入群名', 'en': 'Enter group name',
    'ja': 'グループ名を入力', 'ko': '그룹 이름 입력', 'es': 'Ingresa el nombre del grupo',
    'pt': 'Digite o nome do grupo', 'hi': 'समूह का नाम दर्ज करें',
  },
  'grp_name_updated': {
    'zh-CN': '群名已修改', 'zh-TW': '群名已修改', 'en': 'Group name updated',
    'ja': 'グループ名を変更しました', 'ko': '그룹 이름이 변경되었습니다', 'es': 'Nombre del grupo actualizado',
    'pt': 'Nome do grupo atualizado', 'hi': 'समूह का नाम अपडेट हुआ',
  },
  'grp_update_failed': {
    'zh-CN': '修改失败', 'zh-TW': '修改失敗', 'en': 'Update failed',
    'ja': '変更に失敗しました', 'ko': '변경 실패', 'es': 'Error al actualizar',
    'pt': 'Falha ao atualizar', 'hi': 'अपडेट विफल',
  },
  'grp_remove_member': {
    'zh-CN': '移除成员', 'zh-TW': '移除成員', 'en': 'Remove member',
    'ja': 'メンバーを削除', 'ko': '멤버 제거', 'es': 'Eliminar miembro',
    'pt': 'Remover membro', 'hi': 'सदस्य हटाएँ',
  },
  'grp_remove_member_hint': {
    'zh-CN': '将「{name}」移出群聊?', 'zh-TW': '將「{name}」移出群聊?', 'en': 'Remove "{name}" from the group?',
    'ja': '「{name}」をグループから削除しますか?', 'ko': '"{name}"을(를) 그룹에서 제거하시겠습니까?', 'es': '¿Eliminar a "{name}" del grupo?',
    'pt': 'Remover "{name}" do grupo?', 'hi': 'क्या "{name}" को समूह से हटाएँ?',
  },
  'grp_remove': {
    'zh-CN': '移除', 'zh-TW': '移除', 'en': 'Remove',
    'ja': '削除', 'ko': '제거', 'es': 'Eliminar',
    'pt': 'Remover', 'hi': 'हटाएँ',
  },
  'grp_removed': {
    'zh-CN': '已移除', 'zh-TW': '已移除', 'en': 'Removed',
    'ja': '削除しました', 'ko': '제거됨', 'es': 'Eliminado',
    'pt': 'Removido', 'hi': 'हटाया गया',
  },
  'grp_remove_failed': {
    'zh-CN': '移除失败', 'zh-TW': '移除失敗', 'en': 'Remove failed',
    'ja': '削除に失敗しました', 'ko': '제거 실패', 'es': 'Error al eliminar',
    'pt': 'Falha ao remover', 'hi': 'हटाना विफल',
  },
  'grp_load_friends_failed': {
    'zh-CN': '加载好友失败', 'zh-TW': '載入好友失敗', 'en': 'Failed to load friends',
    'ja': '友達の読み込みに失敗しました', 'ko': '친구 로드 실패', 'es': 'Error al cargar amigos',
    'pt': 'Falha ao carregar amigos', 'hi': 'दोस्त लोड विफल',
  },
  'grp_no_addable_friends': {
    'zh-CN': '没有可添加的好友', 'zh-TW': '沒有可添加的好友', 'en': 'No friends to add',
    'ja': '追加できる友達がいません', 'ko': '추가할 친구 없음', 'es': 'No hay amigos para añadir',
    'pt': 'Nenhum amigo para adicionar', 'hi': 'जोड़ने के लिए कोई दोस्त नहीं',
  },
  'grp_pick_friend': {
    'zh-CN': '选择好友加入群聊', 'zh-TW': '選擇好友加入群聊', 'en': 'Select a friend to join',
    'ja': '友達を選択してグループに追加', 'ko': '그룹에 추가할 친구 선택', 'es': 'Selecciona un amigo para unirse',
    'pt': 'Selecione um amigo para entrar', 'hi': 'शामिल करने के लिए दोस्त चुनें',
  },
  'grp_added': {
    'zh-CN': '已添加 {name}', 'zh-TW': '已添加 {name}', 'en': 'Added {name}',
    'ja': '{name} を追加しました', 'ko': '{name} 추가됨', 'es': '{name} añadido',
    'pt': '{name} adicionado', 'hi': '{name} जोड़ा गया',
  },
  'grp_add_failed': {
    'zh-CN': '添加失败', 'zh-TW': '添加失敗', 'en': 'Add failed',
    'ja': '追加に失敗しました', 'ko': '추가 실패', 'es': 'Error al añadir',
    'pt': 'Falha ao adicionar', 'hi': 'जोड़ना विफल',
  },
  'grp_owner': {
    'zh-CN': '群主', 'zh-TW': '群主', 'en': 'Owner',
    'ja': 'オーナー', 'ko': '방장', 'es': 'Propietario',
    'pt': 'Proprietário', 'hi': 'मालिक',
  },
  'grp_reload': {
    'zh-CN': '重新加载', 'zh-TW': '重新載入', 'en': 'Reload',
    'ja': '再読み込み', 'ko': '다시 로드', 'es': 'Recargar',
    'pt': 'Recarregar', 'hi': 'पुनः लोड करें',
  },

  // ---------------- call_page (call_) ----------------
  'call_ringing': {
    'zh-CN': '对方振铃…', 'zh-TW': '對方振鈴…', 'en': 'Ringing…',
    'ja': '呼び出し中…', 'ko': '벨 울리는 중…', 'es': 'Sonando…',
    'pt': 'Tocando…', 'hi': 'रिंग हो रहा है…',
  },
  'call_invite': {
    'zh-CN': '邀请你语音通话', 'zh-TW': '邀請你語音通話', 'en': 'Invites you to a voice call',
    'ja': '音声通話に招待しています', 'ko': '음성 통화 초대', 'es': 'Te invita a una llamada de voz',
    'pt': 'Convida você para uma chamada de voz', 'hi': 'आपको वॉयस कॉल के लिए आमंत्रित कर रहा है',
  },
  'call_in_call': {
    'zh-CN': '通话中', 'zh-TW': '通話中', 'en': 'In call',
    'ja': '通話中', 'ko': '통화 중', 'es': 'En llamada',
    'pt': 'Em chamada', 'hi': 'कॉल में',
  },
  'call_ended': {
    'zh-CN': '通话已结束', 'zh-TW': '通話已結束', 'en': 'Call ended',
    'ja': '通話が終了しました', 'ko': '통화 종료', 'es': 'Llamada finalizada',
    'pt': 'Chamada encerrada', 'hi': 'कॉल समाप्त',
  },
  'call_calling': {
    'zh-CN': '呼叫中…', 'zh-TW': '呼叫中…', 'en': 'Calling…',
    'ja': '発信中…', 'ko': '발신 중…', 'es': 'Llamando…',
    'pt': 'Chamando…', 'hi': 'कॉल किया जा रहा है…',
  },
  'call_peer': {
    'zh-CN': '对方', 'zh-TW': '對方', 'en': 'Peer',
    'ja': '相手', 'ko': '상대방', 'es': 'Otro',
    'pt': 'Outro', 'hi': 'सामने वाला',
  },
  'call_reject': {
    'zh-CN': '拒绝', 'zh-TW': '拒絕', 'en': 'Decline',
    'ja': '拒否', 'ko': '거절', 'es': 'Rechazar',
    'pt': 'Recusar', 'hi': 'अस्वीकारें',
  },
  'call_accept': {
    'zh-CN': '接听', 'zh-TW': '接聽', 'en': 'Answer',
    'ja': '応答', 'ko': '응답', 'es': 'Contestar',
    'pt': 'Atender', 'hi': 'उत्तर दें',
  },
  'call_mute': {
    'zh-CN': '静音', 'zh-TW': '靜音', 'en': 'Mute',
    'ja': 'ミュート', 'ko': '음소거', 'es': 'Silenciar',
    'pt': 'Silenciar', 'hi': 'म्यूट',
  },
  'call_muted': {
    'zh-CN': '已静音', 'zh-TW': '已靜音', 'en': 'Muted',
    'ja': 'ミュート中', 'ko': '음소거됨', 'es': 'Silenciado',
    'pt': 'Silenciado', 'hi': 'म्यूट किया गया',
  },
  'call_hangup': {
    'zh-CN': '挂断', 'zh-TW': '掛斷', 'en': 'Hang up',
    'ja': '切る', 'ko': '끊기', 'es': 'Colgar',
    'pt': 'Desligar', 'hi': 'काटें',
  },
  'call_speaker': {
    'zh-CN': '免提', 'zh-TW': '免提', 'en': 'Speaker',
    'ja': 'スピーカー', 'ko': '스피커', 'es': 'Altavoz',
    'pt': 'Alto-falante', 'hi': 'स्पीकर',
  },
  'call_earpiece': {
    'zh-CN': '听筒', 'zh-TW': '聽筒', 'en': 'Earpiece',
    'ja': '受話器', 'ko': '수화기', 'es': 'Auricular',
    'pt': 'Auricular', 'hi': 'ईयरपीस',
  },
};
