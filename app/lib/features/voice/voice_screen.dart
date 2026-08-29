import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vendor360_core/vendor360_core.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../core/strings.dart';
import '../../data/models.dart';

/// Voice-to-inventory capture.
///
/// The flow is capture → parse → **confirm** → commit, and the confirm step is
/// not optional. ASR is imperfect, so the guide requires the vendor to see what
/// was heard before it touches inventory; the backend enforces the same rule by
/// refusing to commit a low-confidence parse regardless of what the client asks
/// for.
///
/// Speech capture itself is stubbed. The TRD specifies Bhashini for ASR, which
/// needs credentials this prototype does not have, so the orb produces a
/// realistic utterance from a sample set and the transcript field accepts any
/// text. Everything downstream — parsing, confidence, correction, commit — is
/// the real pipeline running against the real backend, so swapping in Bhashini
/// means replacing `_capture` and nothing else.
class VoiceScreen extends ConsumerStatefulWidget {
  const VoiceScreen({super.key});

  @override
  ConsumerState<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends ConsumerState<VoiceScreen> {
  final _transcript = TextEditingController();
  final _random = Random();

  bool _listening = false;
  bool _parsing = false;
  VoiceParseResult? _result;
  List<ParsedLine> _lines = <ParsedLine>[];
  String? _error;

  /// Sample utterances in all three languages, including the awkward ones —
  /// a missing verb, a missing quantity — so the confirm path is reachable in
  /// a demo rather than only the happy path.
  static const Map<AppLanguage, List<String>> _samples = {
    AppLanguage.hindi: <String>[
      '20 doodh packet aur 5 kilo chawal beche',
      'बीस दूध पैकेट और पांच किलो चावल बेचे',
      '10 kilo tamatar kharab ho gaya',
      '50 doodh packet aaya',
      'bees doodh packet',
      '3 kilo pyaz aur 2 litre tel liya',
    ],
    AppLanguage.marathi: <String>[
      'दहा किलो कांदा विकले',
      'पाच लिटर तेल घेतला',
      'वीस दूध पॅकेट विकले',
      'तीन किलो साखर विकली',
    ],
    AppLanguage.english: <String>[
      'sold 12 eggs and 2 packets of biscuits',
      'restocked 30 kg rice',
      '5 litre cooking oil wasted',
      'sold 8 bread',
    ],
  };

  @override
  void dispose() {
    _transcript.dispose();
    super.dispose();
  }

  /// Stands in for Bhashini. Returns a transcript and an ASR confidence.
  Future<({String text, double confidence})> _capture(AppLanguage language) async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    final pool = _samples[language]!;
    return (
      text: pool[_random.nextInt(pool.length)],
      // Real ASR rarely returns certainty. Varying this is what makes the
      // review path show up honestly rather than only on contrived input.
      confidence: 0.62 + _random.nextDouble() * 0.36,
    );
  }

  Future<void> _startListening() async {
    final language = ref.read(languageProvider);
    HapticFeedback.mediumImpact();
    setState(() {
      _listening = true;
      _result = null;
      _lines = <ParsedLine>[];
      _error = null;
    });

    final heard = await _capture(language);
    if (!mounted) return;

    _transcript.text = heard.text;
    HapticFeedback.selectionClick();
    setState(() => _listening = false);
    await _parse(asrConfidence: heard.confidence);
  }

  Future<void> _parse({double asrConfidence = 1.0}) async {
    final text = _transcript.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _parsing = true;
      _error = null;
    });

    try {
      final result = await ref.read(repositoryProvider).parseUtterance(
            transcript: text,
            language: ref.read(languageProvider).code,
            asrConfidence: asrConfidence,
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _lines = result.lines;
        _parsing = false;
      });
    } catch (error) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      setState(() {
        _parsing = false;
        _error = 'Could not reach the server. Your entry is safe — try again.';
      });
    }
  }

  Future<void> _confirm() async {
    final lines = _lines;
    if (lines.isEmpty) return;

    try {
      await ref.read(repositoryProvider).confirmVoiceLines(lines);
      ref.read(syncProvider.notifier).refresh();
      ref.invalidate(inventoryProvider);
      ref.invalidate(dashboardProvider);

      if (!mounted) return;
      HapticFeedback.lightImpact();
      final saved = lines.length;
      setState(() {
        _result = null;
        _lines = <ParsedLine>[];
        _transcript.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$saved ${saved == 1 ? 'entry' : 'entries'} saved')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Saved locally. It will sync when you are back online.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final s = ref.watch(stringsProvider);
    final language = ref.watch(languageProvider);
    final hasResult = _result != null && _lines.isNotEmpty;

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(v360.spacing.gutter),
          children: <Widget>[
            _LanguageSwitcher(current: language),
            SizedBox(height: v360.spacing.xxl),

            if (!hasResult) ...<Widget>[
              Center(
                child: Column(
                  children: <Widget>[
                    Text(
                      _listening ? s.listening : s.speakNow,
                      style: v360.text.titleL.copyWith(color: colors.ink),
                    ),
                    SizedBox(height: v360.spacing.sm),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: v360.spacing.xxl),
                      child: Text(
                        s.voiceExample,
                        textAlign: TextAlign.center,
                        style: v360.text.caption.copyWith(color: colors.inkMuted),
                      ),
                    ),
                    SizedBox(height: v360.spacing.x3),
                    VoiceOrb(
                      listening: _listening,
                      processing: _parsing,
                      onTap: _listening ? null : _startListening,
                      size: 104,
                    ),
                  ],
                ),
              ),
              SizedBox(height: v360.spacing.x3),
              _TranscriptField(
                controller: _transcript,
                onSubmit: () => _parse(),
                busy: _parsing,
              ),
            ],

            if (_error != null) ...<Widget>[
              SizedBox(height: v360.spacing.lg),
              V360Banner(
                icon: Icons.cloud_off_rounded,
                title: _error!,
                tone: V360BannerTone.warning,
              ),
            ],

            if (hasResult) ...<Widget>[
              _ReviewHeader(result: _result!, strings: s),
              SizedBox(height: v360.spacing.lg),

              for (var i = 0; i < _lines.length; i++)
                V360Reveal(
                  delayIndex: i,
                  child: ConfidenceRow(
                    skuName: _lines[i].skuName,
                    quantity: _lines[i].qty,
                    unit: _lines[i].unit,
                    confidence: _lines[i].confidence,
                    needsReview: _lines[i].needsReview,
                    movementLabel: _movementLabel(_lines[i].movement),
                    isKnownItem: _lines[i].knownItem,
                    matchedText: _lines[i].matchedText,
                    onIncrement: () => setState(() => _lines[i].qty += 1),
                    onDecrement: () => setState(
                      () => _lines[i].qty = (_lines[i].qty - 1).clamp(1, 99999),
                    ),
                    onRemove: () => setState(() => _lines.removeAt(i)),
                  ),
                ),

              SizedBox(height: v360.spacing.lg),
              V360Button.primary(
                label: s.confirmAndSave,
                expand: true,
                leadingIcon: Icons.check_rounded,
                onPressed: _confirm,
              ),
              SizedBox(height: v360.spacing.sm),
              V360Button.secondary(
                label: s.tryAgain,
                expand: true,
                onPressed: () => setState(() {
                  _result = null;
                  _lines = <ParsedLine>[];
                  _transcript.clear();
                }),
              ),
            ],

            SizedBox(height: v360.spacing.x5),
          ],
        ),
      ),
    );
  }

  String _movementLabel(String movement) => switch (movement) {
        'restock' => 'Restock',
        'wastage' => 'Waste',
        _ => 'Sale',
      };
}

class _LanguageSwitcher extends ConsumerWidget {
  const _LanguageSwitcher({required this.current});

  final AppLanguage current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return V360Segmented<AppLanguage>(
      value: current,
      // TC-V05: switching mid-session must change the language of subsequent
      // captures, so this writes straight to the provider that both the ASR
      // locale and the on-screen strings read from.
      onChanged: (value) => ref.read(languageProvider.notifier).value = value,
      segments: <V360Segment<AppLanguage>>[
        for (final language in AppLanguage.values)
          V360Segment<AppLanguage>(
            value: language,
            label: language.nativeName,
          ),
      ],
    );
  }
}

class _TranscriptField extends StatelessWidget {
  const _TranscriptField({
    required this.controller,
    required this.onSubmit,
    required this.busy,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Typing is the documented fallback for when ASR struggles with an
        // accent or the market is too loud (PRD 7), not the primary path.
        const SectionLabel('Or type it'),
        SizedBox(height: v360.spacing.sm),
        TextField(
          controller: controller,
          minLines: 2,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmit(),
          style: v360.text.body.copyWith(color: colors.ink),
          decoration: InputDecoration(
            hintText: '20 doodh packet aur 5 kilo chawal beche',
            hintStyle: v360.text.body.copyWith(color: colors.inkSubtle),
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
        SizedBox(height: v360.spacing.md),
        V360Button.secondary(
          label: 'Read this',
          expand: true,
          loading: busy,
          leadingIcon: Icons.auto_awesome_rounded,
          onPressed: onSubmit,
        ),
      ],
    );
  }
}

class _ReviewHeader extends StatelessWidget {
  const _ReviewHeader({required this.result, required this.strings});

  final VoiceParseResult result;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          strings.checkBeforeSaving,
          style: v360.text.titleL.copyWith(color: colors.ink),
        ),
        SizedBox(height: v360.spacing.sm),

        // The raw transcript stays visible above the parse, so the vendor can
        // see what was heard, not only what was understood.
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(v360.spacing.lg),
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: BorderRadius.circular(V360Radius.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.hearing_rounded, size: 16, color: colors.inkMuted),
              SizedBox(width: v360.spacing.sm),
              Expanded(
                child: Text(
                  '"${result.transcript}"',
                  style: v360.text.body.copyWith(
                    color: colors.inkMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),

        if (result.needsReview) ...<Widget>[
          SizedBox(height: v360.spacing.md),
          V360Banner(
            icon: Icons.error_outline_rounded,
            title: 'Some words were unclear',
            body: 'Check the highlighted rows before saving. '
                'Nothing is recorded until you confirm.',
            tone: V360BannerTone.warning,
          ),
        ],
      ],
    );
  }
}
