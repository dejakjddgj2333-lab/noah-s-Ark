import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../core/theme.dart';

/// 语言选择页: 国旗 + 语言名列表, 选中即生效并持久化.
class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: McColors.surfaceContainerLowest,
      appBar: AppBar(
        backgroundColor: McColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: McColors.onSurface),
        title: Text(tr('language_select'),
            style: McText.sans(size: 15, weight: FontWeight.w700)),
      ),
      body: ListenableBuilder(
        listenable: L10n.instance,
        builder: (context, _) {
          final current = L10n.instance.code;
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
            itemCount: L10n.languages.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final lang = L10n.languages[i];
              final selected = lang.code == current;
              return GestureDetector(
                onTap: () => L10n.instance.setCode(lang.code),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: selected
                        ? McColors.primaryContainer.withValues(alpha: 0.15)
                        : McColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? McColors.primary.withValues(alpha: 0.6)
                          : McColors.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(lang.flag, style: const TextStyle(fontSize: 26)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(lang.nativeName,
                                style: McText.sans(
                                    size: 15,
                                    weight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: Colors.white)),
                            if (lang.englishName != lang.nativeName)
                              Text(lang.englishName,
                                  style: McText.sans(
                                      size: 12,
                                      color: McColors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      if (selected)
                        const Icon(Icons.check_circle,
                            size: 20, color: McColors.primary),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
