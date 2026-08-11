import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_theme.dart';
import '../responsive.dart';
import 'preview_config.dart';
import 'preview_renderer.dart';

/// Превью оклейки: цвет кузова + хром. Пока только визуал для клиента.
class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  static const _renderer = PlaceholderPreviewRenderer();

  PreviewConfig _config = PreviewConfig(
    bodyColor: kPreviewBodyColors.first.color,
  );

  void _set(PreviewConfig next) => setState(() => _config = next);

  @override
  Widget build(BuildContext context) {
    final mobile = AppResponsive.isMobile(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: mobile ? _buildMobile() : _buildDesktop(),
    );
  }

  Widget _buildDesktop() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Превью', style: AppTheme.pageTitle),
              const SizedBox(width: 12),
              Text(
                'Как будет выглядеть после оклейки',
                style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 14),
              ),
              const Spacer(),
              Text(
                'черновик · 2D',
                style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 5, child: _previewStage()),
                const SizedBox(width: 16),
                SizedBox(width: 300, child: _controlsPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobile() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text('Превью', style: AppTheme.pageTitle),
        const SizedBox(height: 4),
        Text(
          'Как будет выглядеть после оклейки',
          style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 13),
        ),
        const SizedBox(height: 14),
        SizedBox(height: 280, child: _previewStage()),
        const SizedBox(height: 14),
        _controlsPanel(),
      ],
    );
  }

  Widget _previewStage() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.border),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1A2332),
            AppColors.surface2,
          ],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 48),
              child: _renderer.build(context, _config),
            ),
          ),
          Positioned(
            left: 12,
            top: 10,
            child: Text(
              'generic sedan · ${_config.camera.label}',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: PreviewCamera.values.map((cam) {
                final on = _config.camera == cam;
                return ChoiceChip(
                  label: Text(cam.label),
                  selected: on,
                  onSelected: (_) => _set(_config.copyWith(camera: cam)),
                  selectedColor: AppColors.primary.withOpacity(0.35),
                  labelStyle: GoogleFonts.manrope(
                    color: on ? AppColors.text : AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  backgroundColor: AppColors.surface,
                  side: BorderSide(color: on ? AppColors.primary : AppColors.border),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlsPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ЦВЕТ КУЗОВА',
              style: GoogleFonts.manrope(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in kPreviewBodyColors)
                  _ColorSwatch(
                    color: c.color,
                    label: c.name,
                    selected: _config.bodyColor.value == c.color.value,
                    onTap: () => _set(_config.copyWith(bodyColor: c.color)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _selectedColorName(),
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 20),
            Text(
              'ХРОМ',
              style: GoogleFonts.manrope(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Притемнение — затемнение хрома, не тонировка стёкол',
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 11, height: 1.3),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: PreviewChrome.values.map((ch) {
                final on = _config.chrome == ch;
                return ChoiceChip(
                  label: Text(ch.shortLabel),
                  selected: on,
                  onSelected: (_) => _set(_config.copyWith(chrome: ch)),
                  selectedColor: AppColors.primary.withOpacity(0.35),
                  labelStyle: GoogleFonts.manrope(
                    color: on ? AppColors.text : AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  backgroundColor: AppColors.surface,
                  side: BorderSide(color: on ? AppColors.primary : AppColors.border),
                  showCheckmark: false,
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Text(
              _config.chrome.label,
              style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                'Пока только превью для клиента.\n'
                'Создание заказа из конфигурации — позже.\n'
                '3D-модель подключится к этому же экрану.',
                style: GoogleFonts.manrope(color: AppColors.textDim, fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _selectedColorName() {
    for (final c in kPreviewBodyColors) {
      if (c.color.value == _config.bodyColor.value) return c.name;
    }
    return 'Свой цвет';
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.primary : Colors.white.withOpacity(0.25),
              width: selected ? 2.5 : 1,
            ),
            boxShadow: selected
                ? [BoxShadow(color: AppColors.primary.withOpacity(0.45), blurRadius: 8)]
                : null,
          ),
        ),
      ),
    );
  }
}
