
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../core/strings.dart';

/// Day close — what the day came to, and the paper to prove it.
///
/// The last question a shopkeeper asks. Cash in leads rather than sales,
/// because a sale recorded on credit is revenue and not money in the drawer,
/// and the difference is the thing worth knowing at closing time.
class DayCloseScreen extends ConsumerWidget {
  const DayCloseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final s = ref.watch(stringsProvider);
    final day = ref.watch(dayCloseProvider);
    final series = ref.watch(salesSeriesProvider);

    return Scaffold(
      backgroundColor: colors.canvas,
      body: Column(
        children: <Widget>[
          PackHeader(
            title: s.dayClose,
            subtitle: day.value == null
                ? null
                : DateFormat('EEEE, d MMMM').format(day.value!.on),
            leading: V360IconButton(
              icon: Icons.arrow_back_rounded,
              color: colors.onBand,
              semanticLabel: 'Back',
              onPressed: () => context.go('/'),
            ),
            figure: Text(
              day.value?.cashIn.display ?? '—',
              style: v360.text.display.copyWith(color: colors.onBand),
            ),
            figureCaption: s.cashIn,
            facts: <PackFact>[
              PackFact(day.value?.salesValue.display ?? '—', s.todaySales.toLowerCase()),
              PackFact('${day.value?.transactionCount ?? 0}', s.entries),
              PackFact(
                day.value?.wastageValue.display ?? '—',
                s.wasted,
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              color: colors.accent,
              onRefresh: () async {
                HapticFeedback.lightImpact();
                ref
                  ..invalidate(dayCloseProvider)
                  ..invalidate(salesSeriesProvider);
              },
              child: day.when(
                loading: () => ListView(
                  padding: EdgeInsets.all(v360.spacing.gutter),
                  children: const <Widget>[V360Skeleton(height: 240)],
                ),
                error: (error, _) => EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not close the day',
                  body: '$error',
                ),
                data: (data) => ListView(
                  padding: EdgeInsets.fromLTRB(
                    v360.spacing.gutter,
                    v360.spacing.lg,
                    v360.spacing.gutter,
                    v360.spacing.x5,
                  ),
                  children: <Widget>[
                    // Why cash in is not sales, said once, where the two
                    // numbers sit next to each other.
                    if (data.udhaarGiven.rupees > 0 ||
                        data.udhaarCollected.rupees > 0) ...<Widget>[
                      V360Card(
                        padding: EdgeInsets.symmetric(
                          horizontal: v360.spacing.lg,
                          vertical: v360.spacing.md,
                        ),
                        child: Column(
                          children: <Widget>[
                            _Line(
                              label: s.givenOnUdhaar,
                              value: '− ${data.udhaarGiven.display}',
                            ),
                            Divider(height: v360.spacing.lg),
                            _Line(
                              label: s.collectedOnUdhaar,
                              value: '+ ${data.udhaarCollected.display}',
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: v360.spacing.x3),
                    ],
                    SectionLabel(s.last14Days),
                    SizedBox(height: v360.spacing.sm),
                    V360Card(
                      child: series.when(
                        loading: () => const V360Skeleton(height: 160),
                        error: (_, _) => const SizedBox.shrink(),
                        data: (points) => SalesBars(
                          points: <SalesPointData>[
                            for (final p in points)
                              SalesPointData(
                                label: DateFormat('d').format(p.on),
                                value: p.value.rupees,
                                display: p.value.display,
                                today: DateUtils.isSameDay(p.on, data.on),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (data.topItems.isNotEmpty) ...<Widget>[
                      SizedBox(height: v360.spacing.x3),
                      SectionLabel(s.soldMost),
                      SizedBox(height: v360.spacing.sm),
                      V360Card(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: <Widget>[
                            for (var i = 0; i < data.topItems.length; i++) ...[
                              if (i > 0) Divider(indent: v360.spacing.lg),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: v360.spacing.lg,
                                  vertical: v360.spacing.md,
                                ),
                                child: _Line(
                                  label: data.topItems[i].skuName,
                                  caption: data.topItems[i].quantity.display,
                                  value: data.topItems[i].value.display,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: v360.spacing.x3),
                    SectionLabel(s.takeItWithYou),
                    SizedBox(height: v360.spacing.sm),
                    _ExportRow(
                      label: s.daySheet,
                      icon: Icons.description_outlined,
                      path: '/reports/day-close.pdf',
                      filename: 'day-close.pdf',
                      mime: 'application/pdf',
                    ),
                    SizedBox(height: v360.spacing.sm),
                    _ExportRow(
                      label: s.creditReport,
                      icon: Icons.verified_outlined,
                      path: '/reports/credit.pdf',
                      filename: 'credit-report.pdf',
                      mime: 'application/pdf',
                    ),
                    SizedBox(height: v360.spacing.sm),
                    _ExportRow(
                      label: s.ledgerWorkbook,
                      icon: Icons.table_chart_outlined,
                      path: '/reports/ledger.xlsx',
                      filename: 'vendor360-ledger.xlsx',
                      mime: 'application/vnd.openxmlformats-officedocument'
                          '.spreadsheetml.sheet',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.caption});

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: v360.text.body.copyWith(color: colors.ink)),
              if (caption != null)
                Text(
                  caption!,
                  style: v360.text.caption.copyWith(color: colors.inkMuted),
                ),
            ],
          ),
        ),
        Text(
          value,
          style: v360.text.titleS
              .copyWith(color: colors.ink)
              .weight(FontWeight.w700)
              .narrow(86),
        ),
      ],
    );
  }
}

/// One file the shopkeeper can hand to someone else.
///
/// Fetched with the session's own token and passed to the share sheet, so it
/// reaches WhatsApp, Drive, a printer or an email without the app ever
/// sending anything itself. Where the platform has no share sheet — a
/// desktop browser — it says so rather than failing silently.
class _ExportRow extends ConsumerStatefulWidget {
  const _ExportRow({
    required this.label,
    required this.icon,
    required this.path,
    required this.filename,
    required this.mime,
  });

  final String label;
  final IconData icon;
  final String path;
  final String filename;
  final String mime;

  @override
  ConsumerState<_ExportRow> createState() => _ExportRowState();
}

class _ExportRowState extends ConsumerState<_ExportRow> {
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final Uint8List bytes =
          await ref.read(marketplaceProvider).reportFile(widget.path);
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile.fromData(
              bytes,
              name: widget.filename,
              mimeType: widget.mime,
            ),
          ],
          fileNameOverrides: <String>[widget.filename],
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not prepare ${widget.filename} here. '
            'It works on the phone app.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return V360Button.secondary(
      label: widget.label,
      leadingIcon: widget.icon,
      expand: true,
      loading: _busy,
      onPressed: _busy ? null : _share,
    );
  }
}
