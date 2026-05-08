import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_localizations.dart';
import '../theme/app_colors.dart';

/// First-time tutorial shown when an owner activates "options" on a service.
///
/// Three slides explain the three configurable behaviors behind each choice:
///   1. Demander via WhatsApp
///   2. Galerie de designs
///   3. Sous-options
///
/// Persisted via SharedPreferences key `_seenKey` so it shows only once.
class ServiceOptionsTutorialDialog extends StatefulWidget {
  const ServiceOptionsTutorialDialog({super.key});

  static const _seenKey = 'hasSeenServiceOptionsTutorial_v1';

  /// Show the dialog only if the user has never seen it before.
  /// Returns immediately when the flag is already set.
  static Future<void> showIfNeeded(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seenKey) == true) return;
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      barrierDismissible: false,
      builder: (_) => const ServiceOptionsTutorialDialog(),
    );
    await prefs.setBool(_seenKey, true);
  }

  @override
  State<ServiceOptionsTutorialDialog> createState() =>
      _ServiceOptionsTutorialDialogState();
}

class _ServiceOptionsTutorialDialogState
    extends State<ServiceOptionsTutorialDialog> {
  final PageController _pageController = PageController();
  int _index = 0;

  static const _slideCount = 4;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _slideCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _skip() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final media = MediaQuery.of(context);
    final isLast = _index == _slideCount - 1;

    final slides = <_Slide>[
      _Slide(
        illustrationBuilder: (key) => _KebabIntroIllustration(key: key),
        accent: AppColors.brand600,
        title: l?.tr('tutorial_options_intro_title') ??
            'Personnalisez chaque choix',
        body: l?.tr('tutorial_options_intro_body') ??
            'Sur chaque choix, appuyez sur ⋮ pour révéler 3 options : Galerie, Sous-options et Demande WhatsApp.',
      ),
      _Slide(
        illustrationBuilder: (key) => _GalleryIllustration(key: key),
        accent: Colors.purple,
        title:
            l?.tr('tutorial_options_gallery_title') ?? 'Galerie de designs',
        body: l?.tr('tutorial_options_gallery_body') ??
            'Proposez des photos ou vidéos pour que vos clients choisissent un modèle visuellement (nail art, coiffure, maquillage…).',
      ),
      _Slide(
        illustrationBuilder: (key) => _SubOptionsIllustration(key: key),
        accent: AppColors.brand600,
        title: l?.tr('tutorial_options_suboptions_title') ?? 'Sous-options',
        body: l?.tr('tutorial_options_suboptions_body') ??
            'Créez plusieurs étapes de choix imbriquées. Le client est guidé naturellement (ex : Coupe → Couleur → Finition).',
      ),
      _Slide(
        illustrationBuilder: (key) => _WhatsAppIllustration(key: key),
        accent: const Color(0xFF25D366),
        title: l?.tr('tutorial_options_whatsapp_title') ??
            'Demander via WhatsApp',
        body: l?.tr('tutorial_options_whatsapp_body') ??
            'Quand un client choisit une option personnalisée, il est redirigé sur WhatsApp avec un récap automatique des choix déjà faits — pour finaliser ensemble.',
      ),
    ];

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: math.max(40, media.padding.top + 24),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ─── Header (skip button) ───
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Pill: title at the very top of the modal
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      l?.tr('tutorial_options_eyebrow') ?? 'Astuce',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppColors.secondary500,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _skip,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.secondary500,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      l?.tr('tutorial_options_skip') ?? 'Passer',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ─── Slides ───
            SizedBox(
              height: 420,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _index = i),
                itemCount: _slideCount,
                itemBuilder: (_, i) => _SlideView(slide: slides[i]),
              ),
            ),
            // ─── Page indicator ───
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slideCount, (i) {
                  final active = i == _index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 6,
                    width: active ? 22 : 6,
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.brand600
                          : AppColors.secondary200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
            // ─── Footer button ───
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand600,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    isLast
                        ? (l?.tr('tutorial_options_finish') ?? 'C\'est parti')
                        : (l?.tr('tutorial_options_next') ?? 'Suivant'),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// Slide
// ════════════════════════════════════════════════════════════════════════

class _Slide {
  final Widget Function(Key? key) illustrationBuilder;
  final Color accent;
  final String title;
  final String body;
  const _Slide({
    required this.illustrationBuilder,
    required this.accent,
    required this.title,
    required this.body,
  });
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        children: [
          // Illustration container
          Container(
            height: 220,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  slide.accent.withValues(alpha: 0.10),
                  slide.accent.withValues(alpha: 0.02),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: slide.illustrationBuilder(ValueKey(slide.title)),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.brand950,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: Text(
              slide.body,
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                color: AppColors.secondary600,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// Illustration 1 — WhatsApp
// ════════════════════════════════════════════════════════════════════════

class _WhatsAppIllustration extends StatefulWidget {
  const _WhatsAppIllustration({super.key});

  @override
  State<_WhatsAppIllustration> createState() => _WhatsAppIllustrationState();
}

class _WhatsAppIllustrationState extends State<_WhatsAppIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // Stagger phases inside a single 1500ms run
  static const _wa = Color(0xFF25D366);
  static const _waDark = Color(0xFF075E54);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double _phase(double start, double end) {
    final t = ((_ctrl.value - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final phoneT = _phase(0.0, 0.30);
        final lineSvc = _phase(0.30, 0.50);
        final lineChoice1 = _phase(0.45, 0.65);
        final lineChoice2 = _phase(0.60, 0.80);
        final lineCustom = _phase(0.75, 1.0);

        return Center(
          child: Transform.scale(
            scale: 0.85 + 0.15 * phoneT,
            child: Opacity(
              opacity: phoneT,
              child: Container(
                width: 178,
                height: 196,
                decoration: BoxDecoration(
                  color: const Color(0xFFECE5DD),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFD9D2C9), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Phone header (salon receiver)
                    Container(
                      height: 34,
                      decoration: const BoxDecoration(
                        color: _waDark,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(17),
                          topRight: Radius.circular(17),
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: _wa,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.storefront,
                                size: 11, color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Mon Salon',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                    // Outgoing message bubble (client → salon)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 154),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCF8C6),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(10),
                                topRight: Radius.circular(10),
                                bottomLeft: Radius.circular(10),
                                bottomRight: Radius.circular(2),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 2,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _msgLine(
                                  t: lineSvc,
                                  text: '📌 Coupe femme',
                                  bold: true,
                                ),
                                const SizedBox(height: 3),
                                _msgLine(
                                  t: lineChoice1,
                                  text: '✅ Long',
                                ),
                                const SizedBox(height: 3),
                                _msgLine(
                                  t: lineChoice2,
                                  text: '✅ Châtain',
                                ),
                                const SizedBox(height: 5),
                                _msgLine(
                                  t: lineCustom,
                                  text: '✨ Finition sur mesure',
                                  highlight: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _msgLine({
    required double t,
    required String text,
    bool bold = false,
    bool highlight = false,
  }) {
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, (1 - t) * 4),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            height: 1.25,
            fontWeight: bold || highlight ? FontWeight.w700 : FontWeight.w500,
            color: highlight
                ? _waDark
                : const Color(0xFF1F2A1B),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// Illustration 2 — Galerie
// ════════════════════════════════════════════════════════════════════════

class _GalleryIllustration extends StatefulWidget {
  const _GalleryIllustration({super.key});

  @override
  State<_GalleryIllustration> createState() => _GalleryIllustrationState();
}

class _GalleryIllustrationState extends State<_GalleryIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  static const _purple = Colors.purple;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double _phase(double start, double end) {
    final t = ((_ctrl.value - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeOutBack.transform(t);
  }

  // Selected card highlight reveals at the end
  double _selectedPhase() {
    final t = ((_ctrl.value - 0.7) / 0.3).clamp(0.0, 1.0);
    return Curves.easeOut.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final selT = _selectedPhase();
        return Center(
          child: SizedBox(
            width: 200,
            height: 180,
            child: Stack(
              children: [
                // 4 cards in a 2x2 grid, staggered
                Positioned(
                  left: 8,
                  top: 8,
                  child: _card(
                    t: _phase(0.0, 0.4),
                    icon: Icons.cut,
                    color: const Color(0xFFEDE7F6),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: _card(
                    t: _phase(0.15, 0.55),
                    icon: Icons.brush,
                    color: const Color(0xFFFCE4EC),
                  ),
                ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: _card(
                    t: _phase(0.3, 0.7),
                    icon: Icons.face_retouching_natural,
                    color: const Color(0xFFE0F7FA),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: _card(
                    t: _phase(0.45, 0.85),
                    icon: Icons.spa,
                    color: const Color(0xFFFFF3E0),
                    selectedT: selT,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _card({
    required double t,
    required IconData icon,
    required Color color,
    double selectedT = 0.0,
  }) {
    return Transform.scale(
      scale: 0.6 + 0.4 * t.clamp(0.0, 1.0),
      child: Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Container(
          width: 84,
          height: 78,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Color.lerp(
                Colors.transparent,
                _purple,
                selectedT,
              )!,
              width: 2 + 1.5 * selectedT,
            ),
            boxShadow: [
              BoxShadow(
                color: _purple.withValues(alpha: 0.10 * selectedT),
                blurRadius: 12 * selectedT,
              ),
            ],
          ),
          child: Stack(
            children: [
              Center(
                child: Icon(icon, size: 30, color: _purple.withValues(alpha: 0.65)),
              ),
              if (selectedT > 0.1)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Opacity(
                    opacity: selectedT,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: _purple,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check,
                          size: 12, color: Colors.white),
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

// ════════════════════════════════════════════════════════════════════════
// Illustration 3 — Sous-options
// ════════════════════════════════════════════════════════════════════════

class _SubOptionsIllustration extends StatefulWidget {
  const _SubOptionsIllustration({super.key});

  @override
  State<_SubOptionsIllustration> createState() =>
      _SubOptionsIllustrationState();
}

class _SubOptionsIllustrationState extends State<_SubOptionsIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double _phase(double start, double end) {
    final t = ((_ctrl.value - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Center(
          child: SizedBox(
            width: 220,
            height: 200,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _step(
                  t: _phase(0.0, 0.3),
                  index: 1,
                  label: 'Coupe',
                  value: 'Femme',
                  done: true,
                ),
                _connector(t: _phase(0.25, 0.4)),
                _step(
                  t: _phase(0.35, 0.65),
                  index: 2,
                  label: 'Couleur',
                  value: 'Châtain',
                  done: true,
                ),
                _connector(t: _phase(0.6, 0.75)),
                _step(
                  t: _phase(0.7, 1.0),
                  index: 3,
                  label: 'Finition',
                  value: '',
                  done: false,
                  active: true,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _connector({required double t}) {
    return SizedBox(
      width: 18,
      height: 14,
      child: Center(
        child: ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: t.clamp(0.0, 1.0),
            child: Container(
              width: 2,
              height: 14,
              color: AppColors.brand400,
            ),
          ),
        ),
      ),
    );
  }

  Widget _step({
    required double t,
    required int index,
    required String label,
    required String value,
    bool done = false,
    bool active = false,
  }) {
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset(0, (1 - t) * 6),
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: active
                ? AppColors.brand50
                : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? AppColors.brand400
                  : AppColors.secondary200,
              width: active ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: done
                      ? AppColors.brand600
                      : (active
                          ? AppColors.brand100
                          : AppColors.secondary100),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: done
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text(
                        '$index',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: active
                              ? AppColors.brand700
                              : AppColors.secondary500,
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondary800,
                  ),
                ),
              ),
              if (value.isNotEmpty)
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: AppColors.brand700,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (active)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.brand600,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    '…',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
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

// ════════════════════════════════════════════════════════════════════════
// Illustration 0 — Intro: tap the kebab on a real-looking choice row
// ════════════════════════════════════════════════════════════════════════

class _KebabIntroIllustration extends StatefulWidget {
  const _KebabIntroIllustration({super.key});

  @override
  State<_KebabIntroIllustration> createState() =>
      _KebabIntroIllustrationState();
}

class _KebabIntroIllustrationState extends State<_KebabIntroIllustration>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;   // overall slide timeline
  late final AnimationController _pulse;  // pulse halo around kebab
  late final AnimationController _tap;    // finger press scale at the kebab moment

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _tap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ctrl.forward();
      // Repeat pulse halo continuously to invite the eye
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _pulse.repeat();
      });
      // Tap pulse animation right before menu opens
      Future.delayed(const Duration(milliseconds: 850), () async {
        if (!mounted) return;
        await _tap.forward();
        if (!mounted) return;
        await _tap.reverse();
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _pulse.dispose();
    _tap.dispose();
    super.dispose();
  }

  double _phase(double start, double end) {
    final t = ((_ctrl.value - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_ctrl, _pulse, _tap]),
      builder: (_, __) {
        final rowT = _phase(0.0, 0.20);
        final menuT = _phase(0.45, 0.65);
        final item1T = _phase(0.62, 0.80);
        final item2T = _phase(0.74, 0.90);
        final item3T = _phase(0.86, 1.0);

        // Halo pulse 0..1..0
        final pulseT = (math.sin(_pulse.value * math.pi * 2) + 1) / 2;
        // Tap scale: when active, kebab shrinks slightly
        final tapScale = 1.0 - 0.18 * _tap.value;

        return Center(
          child: SizedBox(
            width: 240,
            height: 200,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                // ── Choice row mock — mirrors service_form_dialog.dart styling ──
                Positioned(
                  top: 14,
                  left: 0,
                  right: 0,
                  child: Opacity(
                    opacity: rowT,
                    child: Transform.translate(
                      offset: Offset(0, (1 - rowT) * 6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // The text field (matches OutlineInputBorder, fontSize 12, padding 8/8)
                            Expanded(
                              child: Container(
                                height: 36,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppColors.secondary200,
                                    width: 1,
                                  ),
                                ),
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'choix 1',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.secondary800,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            // Kebab with halo + tap pulse
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: [
                                  // Halo pulse (radiating circle)
                                  Container(
                                    width: 24 + pulseT * 16,
                                    height: 24 + pulseT * 16,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.brand500.withValues(
                                          alpha: 0.22 * (1 - pulseT)),
                                    ),
                                  ),
                                  // The kebab icon at its real size + tap scale
                                  Transform.scale(
                                    scale: tapScale,
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(
                                        Icons.more_vert,
                                        size: 18,
                                        color: AppColors.secondary400,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 2),
                            // Close button (just like the real row)
                            const Icon(
                              Icons.close,
                              size: 16,
                              color: AppColors.secondary400,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // ── Pop-up menu opening below the kebab ──
                Positioned(
                  top: 56,
                  right: 18,
                  child: Opacity(
                    opacity: menuT,
                    child: Transform.translate(
                      offset: Offset(0, (1 - menuT) * 8),
                      child: Container(
                        width: 184,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.14),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _menuItem(
                              t: item1T,
                              icon: Icons.photo_library,
                              color: Colors.purple,
                              label: 'Galerie',
                            ),
                            _menuItem(
                              t: item2T,
                              icon: Icons.account_tree,
                              color: AppColors.brand600,
                              label: 'Sous-options',
                            ),
                            _menuItem(
                              t: item3T,
                              icon: Icons.chat_bubble,
                              color: const Color(0xFF25D366),
                              label: 'WhatsApp',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _menuItem({
    required double t,
    required IconData icon,
    required Color color,
    required String label,
  }) {
    return Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset((1 - t) * 8, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondary800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
