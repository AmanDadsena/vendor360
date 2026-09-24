import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../core/strings.dart';
import '../../data/udhaar_models.dart';
import 'reminder.dart';

/// One customer's page of the khata.
///
/// What they owe, then every line that made it — newest first, the way a
/// shopkeeper flips back through a paper page. Both actions sit at the
/// bottom where a thumb is: goods taken, money returned.
class CustomerScreen extends ConsumerWidget {
  const CustomerScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final s = ref.watch(stringsProvider);
    final statement = ref.watch(udhaarStatementProvider(customerId));

    return Scaffold(
      backgroundColor: colors.canvas,
      body: Column(
        children: <Widget>[
          PackHeader(
            title: statement.value?.customer.name ?? '',
            subtitle: statement.value?.customer.phone,
            leading: V360IconButton(
              icon: Icons.arrow_back_rounded,
              color: colors.onBand,
              semanticLabel: 'Back',
              onPressed: () => context.go('/udhaar'),
            ),
            figure: Text(
              statement.value?.owed.display ?? '—',
              style: v360.text.display.copyWith(color: colors.onBand),
            ),
            figureCaption: (statement.value?.owed.rupees ?? 0) > 0
                ? s.owedToYou
                : s.settled,
          ),
          Expanded(
            child: statement.when(
              loading: () => Padding(
                padding: EdgeInsets.all(v360.spacing.gutter),
                child: const V360Skeleton(height: 200),
              ),
              error: (error, _) => EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Could not open this page',
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
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: V360Button.primary(
                          label: s.tookGoods,
                          size: V360ButtonSize.md,
                          expand: true,
                          onPressed: () =>
                              _record(context, ref, s, 'credit'),
                        ),
                      ),
                      SizedBox(width: v360.spacing.sm),
                      Expanded(
                        child: V360Button.tonal(
                          label: s.paidBack,
                          size: V360ButtonSize.md,
                          expand: true,
                          onPressed: () =>
                              _record(context, ref, s, 'payment'),
                        ),
                      ),
                    ],
                  ),
                  if (data.owed.rupees > 0) ...<Widget>[
                    SizedBox(height: v360.spacing.sm),
                    V360Button.ghost(
                      label: s.remind,
                      leadingIcon: Icons.send_outlined,
                      expand: true,
                      onPressed: () => _remind(context, ref, data),
                    ),
                  ],
                  SizedBox(height: v360.spacing.x3),
                  SectionLabel(s.udhaar),
                  SizedBox(height: v360.spacing.sm),
                  if (data.entries.isEmpty)
                    Text(
                      s.nobodyOwes,
                      style: v360.text.body.copyWith(color: colors.inkMuted),
                    )
                  else
                    V360Card(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: <Widget>[
                          for (var i = 0; i < data.entries.length; i++) ...[
                            if (i > 0) Divider(indent: v360.spacing.lg),
                            _EntryRow(entry: data.entries[i], strings: s),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _record(
    BuildContext context,
    WidgetRef ref,
    Strings s,
    String kind,
  ) async {
    final amount = await showRecordSheet(
      context,
      title: kind == 'credit' ? s.tookGoods : s.paidBack,
      strings: s,
    );
    if (amount == null) return;

    try {
      await ref.read(marketplaceProvider).recordUdhaar(
            customerId: customerId,
            kind: kind,
            amount: amount.rupees,
            note: amount.note,
          );
      ref
        ..invalidate(udhaarStatementProvider(customerId))
        ..invalidate(udhaarBookProvider);
      HapticFeedback.mediumImpact();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  Future<void> _remind(
    BuildContext context,
    WidgetRef ref,
    UdhaarStatement data,
  ) async {
    final vendor = ref.read(sessionProvider).vendor;
    final message = reminderMessage(
      shopName: vendor?.storeName ?? 'the shop',
      customerName: data.customer.name,
      owed: data.owed,
      since: DateTime.now().subtract(Duration(days: data.daysOutstanding)),
      language: ref.read(languageProvider),
    );

    // The app composes; the shopkeeper sends. Nothing leaves the phone
    // until they choose where it goes.
    await SharePlus.instance.share(ShareParams(text: message));
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.strings});

  final UdhaarEntry entry;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final credit = entry.isCredit;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: v360.spacing.lg,
        vertical: v360.spacing.md,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                StatusMark(
                  label: credit ? strings.tookGoods : strings.paidBack,
                  color: credit ? colors.warning : colors.accent,
                  dense: true,
                ),
                const SizedBox(height: 3),
                Text(
                  <String?>[
                    DateFormat('d MMM').format(entry.occurredAt),
                    entry.note,
                  ].whereType<String>().join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: v360.text.caption.copyWith(color: colors.inkMuted),
                ),
              ],
            ),
          ),
          Text(
            // A payment reads as money coming back, so it is signed.
            '${credit ? '' : '− '}${entry.amount.display}',
            style: v360.text.titleS
                .copyWith(color: credit ? colors.ink : colors.accentText)
                .weight(FontWeight.w700)
                .narrow(86),
          ),
        ],
      ),
    );
  }
}

/// What a record sheet returns: an amount and, when the shopkeeper bothered,
/// what it was for.
class RecordedAmount {
  const RecordedAmount(this.rupees, this.note);

  final double rupees;
  final String? note;
}

/// Amount first, keypad open, note optional.
///
/// One field is what this needs. Asking for a category or an item list before
/// a debt can be written down is how a paper khata beats an app.
Future<RecordedAmount?> showRecordSheet(
  BuildContext context, {
  required String title,
  required Strings strings,
}) {
  final amount = TextEditingController();
  final note = TextEditingController();

  return showModalBottomSheet<RecordedAmount>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final v360 = context.v360;
      final colors = v360.colors;

      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: EdgeInsets.all(v360.spacing.xxl),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(V360Radius.xl),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.hairline,
                      borderRadius: BorderRadius.circular(V360Radius.pill),
                    ),
                  ),
                ),
                SizedBox(height: v360.spacing.lg),
                SectionLabel(title),
                SizedBox(height: v360.spacing.md),
                TextField(
                  controller: amount,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  style: v360.text.figure.copyWith(color: colors.ink),
                  decoration: InputDecoration(
                    prefixText: '₹ ',
                    prefixStyle: v360.text.figure.copyWith(
                      color: colors.inkMuted,
                    ),
                    labelText: strings.amount,
                  ),
                ),
                SizedBox(height: v360.spacing.md),
                TextField(
                  controller: note,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: strings.whatFor),
                ),
                SizedBox(height: v360.spacing.xl),
                V360Button.primary(
                  label: strings.save,
                  expand: true,
                  onPressed: () {
                    final value = double.tryParse(amount.text.trim());
                    if (value == null || value <= 0) {
                      Navigator.of(context).pop();
                      return;
                    }
                    Navigator.of(context).pop(
                      RecordedAmount(
                        value,
                        note.text.trim().isEmpty ? null : note.text.trim(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
