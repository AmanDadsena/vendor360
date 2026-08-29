import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vendor360_core/vendor360_core.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../core/strings.dart';

/// Language choice, then phone + OTP.
///
/// Language comes first, deliberately: every screen after this — including the
/// one asking for a phone number — should already be in the vendor's own
/// language. Asking for it later would mean the sign-in flow is the one part
/// of the product a low-literacy user has to navigate in English.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _phone = TextEditingController(text: '9876510000');
  final _code = TextEditingController();

  _Step _step = _Step.language;
  AppLanguage _language = AppLanguage.hindi;
  String? _devCode;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    ref.read(languageProvider.notifier).value = _language;

    final code = await ref
        .read(sessionProvider.notifier)
        .requestOtp(_phone.text.trim());

    if (!mounted) return;
    if (code != null || ref.read(sessionProvider).error == null) {
      setState(() {
        _devCode = code;
        _step = _Step.code;
        // Prefilled while the backend exposes the code, so a demo is one tap
        // rather than a transcription exercise. Cleared the moment a real SMS
        // gateway is wired in.
        if (code != null) _code.text = code;
      });
    }
  }

  Future<void> _verify() async {
    final ok = await ref.read(sessionProvider.notifier).verify(
          phone: _phone.text.trim(),
          code: _code.text.trim(),
          language: _language,
        );
    if (ok && mounted) {
      ref.read(languageProvider.notifier).value = _language;
    }
  }

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final s = Strings(_language);
    final session = ref.watch(sessionProvider);

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(v360.spacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(height: v360.spacing.x4),
                  const V360Reveal(child: _Brandmark()),
                  SizedBox(height: v360.spacing.x3),

                  V360Reveal(
                    delayIndex: 1,
                    child: Text(
                      s.welcome,
                      textAlign: TextAlign.center,
                      style: v360.text.titleL.copyWith(color: colors.ink),
                    ),
                  ),
                  SizedBox(height: v360.spacing.sm),
                  V360Reveal(
                    delayIndex: 2,
                    child: Text(
                      s.welcomeDetail,
                      textAlign: TextAlign.center,
                      style: v360.text.body.copyWith(color: colors.inkMuted),
                    ),
                  ),
                  SizedBox(height: v360.spacing.x3),

                  AnimatedSwitcher(
                    duration: v360.motion.base,
                    switchInCurve: v360.motion.standard,
                    switchOutCurve: v360.motion.standard,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.05, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: _step == _Step.language
                        ? _LanguageStep(
                            key: const ValueKey('language'),
                            selected: _language,
                            onSelect: (lang) => setState(() => _language = lang),
                            onContinue: () => setState(() => _step = _Step.phone),
                            strings: s,
                          )
                        : _step == _Step.phone
                            ? _PhoneStep(
                                key: const ValueKey('phone'),
                                controller: _phone,
                                loading: session.loading,
                                onSubmit: _sendCode,
                                onBack: () => setState(() => _step = _Step.language),
                                strings: s,
                              )
                            : _CodeStep(
                                key: const ValueKey('code'),
                                controller: _code,
                                loading: session.loading,
                                devCode: _devCode,
                                onSubmit: _verify,
                                onBack: () => setState(() => _step = _Step.phone),
                                strings: s,
                              ),
                  ),

                  if (session.error != null) ...<Widget>[
                    SizedBox(height: v360.spacing.lg),
                    V360Banner(
                      icon: Icons.wifi_off_rounded,
                      title: session.error!,
                      tone: V360BannerTone.danger,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Step { language, phone, code }

class _Brandmark extends StatefulWidget {
  const _Brandmark();

  @override
  State<_Brandmark> createState() => _BrandmarkState();
}

class _BrandmarkState extends State<_Brandmark> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Column(
      children: <Widget>[
        AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) {
            final scale = 1.0 + (_ctrl.value * 0.08);
            final shadowOp = 0.15 + (_ctrl.value * 0.25);
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[colors.accent, colors.voice],
                  ),
                  borderRadius: BorderRadius.circular(V360Radius.xl),
                  boxShadow: [
                    BoxShadow(
                      color: colors.accent.withValues(alpha: shadowOp),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: child,
              ),
            );
          },
          child: const Icon(Icons.storefront_rounded, size: 38, color: Colors.white),
        ),
        SizedBox(height: v360.spacing.lg),
        Text(
          'Vendor360',
          style: v360.text.display.copyWith(color: colors.ink, fontSize: 30),
        ),
        Text(
          'PREDICTIVE INTELLIGENCE FOR LOCAL VENDORS',
          textAlign: TextAlign.center,
          style: v360.text.label.copyWith(color: colors.inkSubtle),
        ),
      ],
    );
  }
}

class _LanguageStep extends StatelessWidget {
  const _LanguageStep({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onContinue,
    required this.strings,
  });

  final AppLanguage selected;
  final ValueChanged<AppLanguage> onSelect;
  final VoidCallback onContinue;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;

    return V360Reveal(
      delayIndex: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionLabel(strings.chooseLanguage),
          SizedBox(height: v360.spacing.md),
          for (final language in AppLanguage.values) ...<Widget>[
            _LanguageOption(
              language: language,
              selected: language == selected,
              onTap: () => onSelect(language),
            ),
            SizedBox(height: v360.spacing.md),
          ],
          SizedBox(height: v360.spacing.sm),
          V360Button.primary(
            label: strings.sendCode,
            expand: true,
            trailingIcon: Icons.arrow_forward_rounded,
            onPressed: onContinue,
          ),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final motion = MotionScope.of(context);

    return V360Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V360Radius.md),
      child: AnimatedContainer(
        duration: motion.base,
        curve: motion.standard,
        padding: EdgeInsets.all(v360.spacing.lg),
        decoration: BoxDecoration(
          color: selected ? colors.accentSurface : colors.surface,
          borderRadius: BorderRadius.circular(V360Radius.md),
          border: Border.all(
            color: selected ? colors.accent : colors.hairline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Endonym first and largest — a picker that names languages
                  // in a language you cannot read is not a picker.
                  Text(
                    language.nativeName,
                    style: v360.text.titleM.copyWith(
                      color: selected ? colors.accentText : colors.ink,
                    ),
                  ),
                  Text(
                    language.englishName,
                    style: v360.text.caption.copyWith(color: colors.inkMuted),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? colors.accent : colors.inkSubtle,
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneStep extends StatelessWidget {
  const _PhoneStep({
    super.key,
    required this.controller,
    required this.loading,
    required this.onSubmit,
    required this.onBack,
    required this.strings,
  });

  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSubmit;
  final VoidCallback onBack;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionLabel(strings.phoneNumber),
        SizedBox(height: v360.spacing.md),
        TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          autofocus: true,
          maxLength: 10,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          style: v360.text.titleM.copyWith(color: colors.ink),
          decoration: InputDecoration(
            counterText: '',
            prefixText: '+91  ',
            prefixStyle: v360.text.titleM.copyWith(color: colors.inkMuted),
            filled: true,
            fillColor: colors.surface,
            contentPadding: EdgeInsets.all(v360.spacing.lg),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(V360Radius.md),
              borderSide: BorderSide(color: colors.hairline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(V360Radius.md),
              borderSide: BorderSide(color: colors.hairline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(V360Radius.md),
              borderSide: BorderSide(color: colors.accent, width: 2),
            ),
          ),
        ),
        SizedBox(height: v360.spacing.lg),
        V360Button.primary(
          label: strings.sendCode,
          expand: true,
          loading: loading,
          onPressed: controller.text.trim().length >= 10 ? onSubmit : null,
        ),
        SizedBox(height: v360.spacing.sm),
        V360Button.ghost(label: strings.cancel, expand: true, onPressed: onBack),
      ],
    );
  }
}

class _CodeStep extends StatelessWidget {
  const _CodeStep({
    super.key,
    required this.controller,
    required this.loading,
    required this.devCode,
    required this.onSubmit,
    required this.onBack,
    required this.strings,
  });

  final TextEditingController controller;
  final bool loading;
  final String? devCode;
  final VoidCallback onSubmit;
  final VoidCallback onBack;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionLabel(strings.enterCode),
        SizedBox(height: v360.spacing.md),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          maxLength: 6,
          textAlign: TextAlign.center,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          style: v360.text.display.copyWith(color: colors.ink, letterSpacing: 8),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: colors.surface,
            contentPadding: EdgeInsets.all(v360.spacing.lg),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(V360Radius.md),
              borderSide: BorderSide(color: colors.hairline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(V360Radius.md),
              borderSide: BorderSide(color: colors.accent, width: 2),
            ),
          ),
        ),
        if (devCode != null) ...<Widget>[
          SizedBox(height: v360.spacing.md),
          V360Banner(
            icon: Icons.info_outline_rounded,
            title: 'Prototype build',
            body: 'No SMS gateway yet, so the code is shown here: $devCode',
          ),
        ],
        SizedBox(height: v360.spacing.lg),
        V360Button.primary(
          label: strings.verify,
          expand: true,
          loading: loading,
          onPressed: controller.text.trim().length >= 4 ? onSubmit : null,
        ),
        SizedBox(height: v360.spacing.sm),
        V360Button.ghost(
          label: strings.changeNumber,
          expand: true,
          onPressed: onBack,
        ),
      ],
    );
  }
}
