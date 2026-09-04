import 'package:flutter/material.dart';

import '../../color/app_colors.dart';

/// 使用說明頁面，依照主要功能提供圖文教學。
class UsageGuidePage extends StatelessWidget {
  const UsageGuidePage({super.key});

  static const List<_GuideSectionData> _sections = [
    _GuideSectionData(
      title: '詢問小精靈',
      icon: Icons.chat_bubble_outline,
      description: '在首頁下方輸入想詢問的內容，小精靈會依照您的飲食紀錄與個人資料提供建議。',
      guidance: '問題越具體，建議越準確。像是「晚餐想吃雞腿便當可以嗎？」會比「我可以吃嗎？」更好。',
      screenshots: [
        _GuideScreenshotData(
          assetPath: 'assets/images/usage_guide_companion.png',
          highlightLabel: '在這裡輸入問題',
        ),
      ],
    ),
    _GuideSectionData(
      title: '飲食紀錄',
      icon: Icons.restaurant_menu,
      description: '從飲食紀錄頁新增餐點，也可以查看每天記錄過的飲食內容。',
      guidance: '請輸入具體餐點名稱、餐別與份量。避免輸入過於抽象或無法辨識的餐點，例如「冷路歐雷」。',
      screenshots: [
        _GuideScreenshotData(
          assetPath: 'assets/images/usage_guide_records.png',
          highlightLabel: '點擊新增餐點',
        ),
        _GuideScreenshotData(
          assetPath: 'assets/images/usage_guide_record_add.png',
          highlightLabel: '搜尋並選擇餐點',
        ),
      ],
    ),
    _GuideSectionData(
      title: '飲食報告',
      icon: Icons.bar_chart,
      description: '在飲食報告頁查看每日熱量、營養狀態與小精靈提醒。',
      guidance: '記錄越完整，報告越能反映真實飲食狀態。建議每天三餐都補上。',
      screenshots: [
        _GuideScreenshotData(
          assetPath: 'assets/images/usage_guide_report.png',
          highlightLabel: '查看今日營養摘要',
        ),
      ],
    ),
    _GuideSectionData(
      title: '問題回饋',
      icon: Icons.feedback_outlined,
      description: '遇到資料錯誤、功能異常或建議事項，可以從設定頁送出問題回饋。',
      guidance: '描述問題時請附上發生頁面、操作步驟；若有畫面截圖，也可以一起附上。',
      screenshots: [
        _GuideScreenshotData(
          assetPath: 'assets/images/usage_guide_feedback.png',
          highlightLabel: '描述問題並附上截圖',
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _sections.length,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          title: const Text(
            '使用說明',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          backgroundColor: AppColors.background,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
          bottom: TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textPrimary.withValues(alpha: 0.5),
            indicatorColor: AppColors.primary,
            indicatorSize: TabBarIndicatorSize.label,
            labelPadding: EdgeInsets.zero,
            tabs: _sections
                .map(
                  (section) => Tab(
                    icon: Icon(section.icon, size: 20),
                    text: section.title,
                  ),
                )
                .toList(),
          ),
        ),
        body: TabBarView(
          children: _sections
              .map((section) => _GuideSection(section: section))
              .toList(),
        ),
      ),
    );
  }
}

class _GuideSection extends StatelessWidget {
  final _GuideSectionData section;

  const _GuideSection({required this.section});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 32),
      children: [
        for (final screenshot in section.screenshots) ...[
          _GuideScreenshot(screenshot: screenshot),
          const SizedBox(height: 16),
        ],
        _GuideTextCard(
          icon: section.icon,
          title: section.title,
          text: section.description,
        ),
        const SizedBox(height: 12),
        _GuideTextCard(
          icon: Icons.error_outline,
          title: '使用規範',
          text: section.guidance,
        ),
      ],
    );
  }
}

class _GuideTextCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _GuideTextCard({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.secondary.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.secondary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  text,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideScreenshot extends StatelessWidget {
  final _GuideScreenshotData screenshot;

  const _GuideScreenshot({required this.screenshot});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenshotWidth =
            constraints.maxWidth > 360 ? 360.0 : constraints.maxWidth;

        return Center(
          child: SizedBox(
            width: screenshotWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 456 / 936,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.asset(
                      screenshot.assetPath,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _GuideScreenshotCaption(label: screenshot.highlightLabel),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GuideScreenshotCaption extends StatelessWidget {
  final String label;

  const _GuideScreenshotCaption({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.secondary.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _GuideSectionData {
  final String title;
  final IconData icon;
  final String description;
  final String guidance;
  final List<_GuideScreenshotData> screenshots;

  const _GuideSectionData({
    required this.title,
    required this.icon,
    required this.description,
    required this.guidance,
    required this.screenshots,
  });
}

class _GuideScreenshotData {
  final String assetPath;
  final String highlightLabel;

  const _GuideScreenshotData({
    required this.assetPath,
    required this.highlightLabel,
  });
}
