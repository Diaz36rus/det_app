import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_theme.dart';
import 'brand_logo_fit.dart';
import 'car_brands.dart';

/// Круглая галочка в стиле моков сайта (залитый violet + check).
class PremiumCheck extends StatelessWidget {
  const PremiumCheck({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 22,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final interactive = enabled && onChanged != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: interactive ? () => onChanged!(!value) : null,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: value
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.primaryDeep],
                    )
                  : null,
              color: value ? null : AppColors.surface2,
              border: Border.all(
                color: value ? AppColors.primary : AppColors.border,
                width: 1.5,
              ),
              boxShadow: value
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.35),
                        blurRadius: 10,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: value
                ? Icon(Icons.check_rounded, size: size * 0.62, color: AppColors.onPrimary)
                : null,
          ),
        ),
      ),
    );
  }
}

/// Номер авто как на моках.
class PlateBadge extends StatelessWidget {
  const PlateBadge(this.plate, {super.key});

  final String plate;

  @override
  Widget build(BuildContext context) {
    final t = plate.trim();
    if (t.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F0F7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Text(
        t.toUpperCase(),
        style: GoogleFonts.manrope(
          color: const Color(0xFF1A1224),
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}

/// Логотип марки: цветной PNG на светлой плитке; SVG — только fallback без white-tint.
class CarBrandMark extends StatefulWidget {
  const CarBrandMark(
    this.makeModel, {
    super.key,
    this.size = 48,
  });

  final String? makeModel;
  final double size;

  static String brandInitials(String? makeModel) {
    final raw = (makeModel ?? '').trim();
    if (raw.isEmpty) return 'АВ';
    final parts = raw.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return 'АВ';
    final a = parts.first;
    if (parts.length == 1) {
      return a.length >= 2 ? a.substring(0, 2).toUpperCase() : a.toUpperCase();
    }
    return (a[0] + parts[1][0]).toUpperCase();
  }

  @override
  State<CarBrandMark> createState() => _CarBrandMarkState();
}

class _CarBrandMarkState extends State<CarBrandMark> {
  String? _asset;
  double _glyphScale = 1.0;

  @override
  void initState() {
    super.initState();
    _bindAsset();
  }

  @override
  void didUpdateWidget(covariant CarBrandMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.makeModel != widget.makeModel) _bindAsset();
  }

  void _bindAsset() {
    final asset = CarBrands.assetPathFor(widget.makeModel);
    _asset = asset;
    if (asset == null) {
      _glyphScale = 1.0;
      return;
    }
    if (asset.endsWith('.png')) {
      _glyphScale = 1.0;
      return;
    }
    final cached = BrandLogoFit.cached(asset);
    if (cached != null) {
      _glyphScale = cached;
      return;
    }
    _glyphScale = 1.0;
    BrandLogoFit.resolve(asset).then((scale) {
      if (!mounted || _asset != asset) return;
      if ((scale - _glyphScale).abs() < 0.01) return;
      setState(() => _glyphScale = scale);
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final asset = _asset;
    final pad = size * 0.06;
    final isPng = asset != null && asset.endsWith('.png');
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Декодируем с запасом под retina — иначе мелкие PNG мылятся на 60–84px.
    final cachePx = (size * dpr * 2.0).round().clamp(96, 512);
    // Единая светлая плитка под цветные эмблемы (и ч/б SVG fallback).
    const plate = Color(0xFFF2F4F7);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: plate,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: asset == null
          ? Text(
              CarBrandMark.brandInitials(widget.makeModel),
              style: GoogleFonts.manrope(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.32,
                letterSpacing: 0.4,
              ),
            )
          : Padding(
              padding: EdgeInsets.all(pad),
              child: isPng
                  ? Image.asset(
                      asset,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      isAntiAlias: true,
                      cacheWidth: cachePx,
                      errorBuilder: (_, __, ___) {
                        final stem = asset.split('/').last.replaceAll('.png', '');
                        final svg = '${CarBrands.assetDir}/$stem.svg';
                        return SvgPicture.asset(
                          svg,
                          width: size,
                          height: size,
                          fit: BoxFit.contain,
                          // Без white-tint: чёрный SI на светлой плитке.
                          placeholderBuilder: (_) => Text(
                            CarBrandMark.brandInitials(widget.makeModel),
                            style: GoogleFonts.manrope(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: size * 0.28,
                            ),
                          ),
                        );
                      },
                    )
                  : Transform.scale(
                      scale: _glyphScale,
                      child: SvgPicture.asset(
                        asset,
                        width: size,
                        height: size,
                        fit: BoxFit.contain,
                        allowDrawingOutsideViewBox: false,
                        placeholderBuilder: (_) => Text(
                          CarBrandMark.brandInitials(widget.makeModel),
                          style: GoogleFonts.manrope(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: size * 0.28,
                          ),
                        ),
                      ),
                    ),
            ),
    );
  }
}

/// Пилюля статуса.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Чип мастера в стиле сайта.
class MasterPill extends StatelessWidget {
  const MasterPill({
    super.key,
    required this.label,
    this.hasValue = false,
    this.onTap,
  });

  final String label;
  final bool hasValue;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 132),
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
          decoration: BoxDecoration(
            color: hasValue
                ? AppColors.primary.withOpacity(enabled ? 0.18 : 0.1)
                : AppColors.bg.withOpacity(0.55),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: hasValue
                  ? AppColors.primary.withOpacity(enabled ? 0.55 : 0.28)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: hasValue ? AppColors.primarySoft : AppColors.surface2,
                child: Icon(
                  hasValue ? Icons.person_rounded : Icons.person_add_alt_1_rounded,
                  size: 14,
                  color: hasValue ? AppColors.primary : AppColors.textDim,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    color: hasValue
                        ? (enabled ? AppColors.text : AppColors.textMuted)
                        : AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
