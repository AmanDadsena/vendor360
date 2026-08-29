import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../data/models.dart';

/// OCR receipt intake.
///
/// A photograph of a supplier receipt becomes stock, with expiry dates already
/// computed from each item's category — the vendor never types a shelf life.
///
/// Camera capture and the OCR engine itself are stubbed: the TRD names
/// Tesseract or a cloud OCR service, neither of which this prototype has
/// credentials or a device camera for on the web target. The sample receipts
/// below feed the same parser the real engine would, so line extraction,
/// confidence flagging, total reconciliation and expiry computation are all
/// the production path. Swapping in a real engine means replacing `_capture`.
class ReceiptScreen extends ConsumerStatefulWidget {
  const ReceiptScreen({super.key});

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
  final _text = TextEditingController();

  bool _scanning = false;
  bool _parsing = false;
  ReceiptResult? _result;
  double _ocrConfidence = 0.94;
  String? _error;

  /// Sample receipts, including a deliberately poor one so the review path is
  /// demonstrable rather than only the clean case.
  static const List<({String label, String text, double confidence})> _samples = [
    (
      label: 'Clear photo',
      confidence: 0.94,
      text: '''SHREE BALAJI TRADERS
GST NO: 27AABCT1234M1Z5
Invoice No: 4471    Date: 29/08/2026
Item              Qty   Rate   Amount
Amul Milk 500ml    20   24.00   480.00
Tata Salt 1kg       5   22.00   110.00
Parle Biscuits     12   10.00   120.00
Fresh Tomato 1kg    8   30.00   240.00
Surf Excel 1kg      3  120.00   360.00
TOTAL                          1310.00''',
    ),
    (
      label: 'Blurry / angled',
      confidence: 0.52,
      text: '''MARKET YARD WHOLESALE
Date: 29/08/2026
Onion 1kg          25   28.00   700.00
Potato 1kg         30   24.00   720.00
Xyzq Unknwn 5OO     2   15.00    30.00
TOTAL                          1450.00''',
    ),
    (
      label: 'Missing a line',
      confidence: 0.91,
      text: '''PUNE DAIRY SUPPLY
Date: 29/08/2026
Amul Milk 500ml    40   24.00   960.00
Amul Curd 400g     15   20.00   300.00
TOTAL                          1560.00''',
    ),
  ];

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _capture(({String label, String text, double confidence}) sample) async {
    HapticFeedback.selectionClick();
    setState(() {
      _scanning = true;
      _result = null;
      _error = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;

    _text.text = sample.text;
    _ocrConfidence = sample.confidence;
    setState(() => _scanning = false);
    await _parse();
  }

  Future<void> _parse() async {
    if (_text.text.trim().isEmpty) return;
    setState(() {
      _parsing = true;
      _error = null;
    });

    try {
      final result = await ref.read(repositoryProvider).parseReceipt(
            rawText: _text.text,
            ocrConfidence: _ocrConfidence,
          );
      if (!mounted) return;
      setState(() {
        _result = result;
        _parsing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _parsing = false;
        _error = 'Could not reach the server. Try again when you have signal.';
      });
    }
  }

  Future<void> _commit() async {
    HapticFeedback.mediumImpact();
    try {
      await ref.read(repositoryProvider).commitReceipt(
            rawText: _text.text,
            ocrConfidence: _ocrConfidence,
          );
      ref.invalidate(inventoryProvider);
      ref.invalidate(dashboardProvider);
      ref.invalidate(expiryProvider);

      if (!mounted) return;
      final added = _result!.lines.where((l) => !l.needsReview && l.skuName != null).length;
      setState(() {
        _result = null;
        _text.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$added items added to stock')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not save. Nothing was changed.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final result = _result;

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/'),
        ),
        title: Text('Scan receipt', style: v360.text.titleM.copyWith(color: colors.ink)),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            v360.spacing.gutter, 0, v360.spacing.gutter, v360.spacing.x5,
          ),
          children: <Widget>[
            if (result == null) ...<Widget>[
              _ScanFrame(scanning: _scanning || _parsing),
              SizedBox(height: v360.spacing.xl),
              const SectionLabel('Sample receipts'),
              SizedBox(height: v360.spacing.sm),
              Text(
                'No camera on this build — pick a receipt to run through the '
                'same reader a photo would use.',
                style: v360.text.caption.copyWith(color: colors.inkMuted),
              ),
              SizedBox(height: v360.spacing.md),
              for (final sample in _samples) ...<Widget>[
                V360Button.secondary(
                  label: sample.label,
                  expand: true,
                  leadingIcon: Icons.receipt_long_outlined,
                  onPressed: _scanning ? null : () => _capture(sample),
                ),
                SizedBox(height: v360.spacing.sm),
              ],
            ],

            if (_error != null) ...<Widget>[
              SizedBox(height: v360.spacing.lg),
              V360Banner(
                icon: Icons.cloud_off_rounded,
                title: _error!,
                tone: V360BannerTone.warning,
              ),
            ],

            if (result != null) _ReceiptReview(
              result: result,
              onCommit: _commit,
              onDiscard: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _result = null;
                  _text.clear();
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame({required this.scanning});

  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(V360Radius.lg),
        border: Border.all(
          color: scanning ? colors.accent : colors.hairline,
          width: scanning ? 2 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            scanning ? Icons.document_scanner_rounded : Icons.photo_camera_outlined,
            size: 40,
            color: scanning ? colors.accent : colors.inkSubtle,
          ),
          SizedBox(height: v360.spacing.md),
          Text(
            scanning ? 'Reading receipt…' : 'Point at a wholesale receipt',
            style: v360.text.bodyStrong.copyWith(
              color: scanning ? colors.accentText : colors.inkMuted,
            ),
          ),
          if (scanning) ...<Widget>[
            SizedBox(height: v360.spacing.md),
            SizedBox(
              width: 140,
              child: LinearProgressIndicator(
                backgroundColor: colors.hairline,
                valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReceiptReview extends StatelessWidget {
  const _ReceiptReview({
    required this.result,
    required this.onCommit,
    required this.onDiscard,
  });

  final ReceiptResult result;
  final VoidCallback onCommit;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final dateFormat = DateFormat('d MMM');
    final readyCount =
        result.lines.where((l) => !l.needsReview && l.skuName != null).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          result.supplier ?? 'Receipt',
          style: v360.text.titleL.copyWith(color: colors.ink),
        ),
        SizedBox(height: v360.spacing.xs),
        Text(
          '${result.lines.length} lines read · '
          '${(result.overallConfidence * 100).round()}% average confidence',
          style: v360.text.caption.copyWith(color: colors.inkMuted),
        ),
        SizedBox(height: v360.spacing.lg),

        // The total check catches the one failure per-row confidence cannot:
        // a line the reader never saw has no row to be unconfident about.
        if (!result.totalMatches)
          V360Banner(
            icon: Icons.calculate_outlined,
            title: 'Total does not match',
            body: 'The receipt says ${result.statedTotal?.toStringAsFixed(2)} '
                'but the lines add up to ${result.computedTotal.toStringAsFixed(2)}. '
                'A line was probably missed — check before saving.',
            tone: V360BannerTone.danger,
          )
        else
          V360Banner(
            icon: Icons.check_circle_outline_rounded,
            title: 'Totals match',
            body: 'Lines add up to ${result.computedTotal.toStringAsFixed(2)}, '
                'the same as the receipt.',
            tone: V360BannerTone.success,
          ),

        if (result.reviewCount > 0) ...<Widget>[
          SizedBox(height: v360.spacing.md),
          V360Banner(
            icon: Icons.error_outline_rounded,
            title: '${result.reviewCount} of ${result.lines.length} lines need a check',
            body: 'The rest will be added. Unclear lines are skipped rather '
                'than guessed.',
            tone: V360BannerTone.warning,
          ),
        ],
        SizedBox(height: v360.spacing.xl),

        const SectionLabel('Items read'),
        SizedBox(height: v360.spacing.md),

        for (var i = 0; i < result.lines.length; i++)
          V360Reveal(
            delayIndex: i,
            child: _LineRow(line: result.lines[i], dateFormat: dateFormat),
          ),

        SizedBox(height: v360.spacing.lg),
        V360Button.primary(
          label: 'Add $readyCount items to stock',
          expand: true,
          leadingIcon: Icons.add_shopping_cart_rounded,
          onPressed: readyCount == 0 ? null : onCommit,
        ),
        SizedBox(height: v360.spacing.sm),
        V360Button.ghost(label: 'Discard', expand: true, onPressed: onDiscard),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.dateFormat});

  final ReceiptLine line;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final unknown = line.skuName == null;

    return Padding(
      padding: EdgeInsets.only(bottom: v360.spacing.sm),
      child: Container(
        padding: EdgeInsets.all(v360.spacing.lg),
        decoration: BoxDecoration(
          color: line.needsReview ? colors.warningSurface : colors.surface,
          borderRadius: BorderRadius.circular(V360Radius.md),
          border: Border.all(
            color: line.needsReview
                ? colors.warning.withValues(alpha: 0.4)
                : colors.hairline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        line.skuName ?? 'Not recognised',
                        style: v360.text.titleS.copyWith(
                          color: unknown ? colors.warningText : colors.ink,
                        ),
                      ),
                      Text(
                        line.raw,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: v360.text.caption.copyWith(color: colors.inkSubtle),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      '${line.qty?.toStringAsFixed(0) ?? '?'} ${line.unit ?? ''}',
                      style: v360.text.bodyStrong.copyWith(color: colors.ink),
                    ),
                    if (line.rate != null)
                      Text(
                        '@ ${line.rate!.toStringAsFixed(2)}',
                        style: v360.text.caption.copyWith(color: colors.inkMuted),
                      ),
                  ],
                ),
              ],
            ),
            SizedBox(height: v360.spacing.sm),
            Wrap(
              spacing: v360.spacing.sm,
              runSpacing: v360.spacing.xs,
              children: <Widget>[
                StatusPill(
                  label: '${(line.confidence * 100).round()}% sure',
                  tone: line.needsReview ? PillTone.attention : PillTone.healthy,
                  dense: true,
                ),
                // Expiry computed from the category, never typed — this is
                // what makes the countdown automatic from one photograph.
                if (line.expiresOn != null)
                  StatusPill(
                    label: 'Best before ${dateFormat.format(line.expiresOn!)}',
                    tone: PillTone.neutral,
                    icon: Icons.event_outlined,
                    dense: true,
                  ),
                for (final issue in line.issues)
                  StatusPill(
                    label: issue,
                    tone: PillTone.attention,
                    icon: Icons.info_outline_rounded,
                    dense: true,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
