import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../core/strings.dart';
import '../../data/udhaar_models.dart';

/// Udhaar — who owes the shop, oldest debt first.
///
/// The other half of the khata. Vendor360 already tracked what the shop owes
/// its distributor; this is the page a kirana actually keeps on paper, and
/// the one that answers whether a shop with good sales is holding any cash.
///
/// Ordered by age rather than amount on purpose: the debt to chase is the one
/// that has stood longest, and sorting by size buries a six-month-old ₹200
/// under yesterday's ₹2,000.
class UdhaarScreen extends ConsumerWidget {
  const UdhaarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final s = ref.watch(stringsProvider);
    final book = ref.watch(udhaarBookProvider);

    return Scaffold(
      backgroundColor: v360.colors.canvas,
      body: Column(
        children: <Widget>[
          PackHeader(
            title: s.udhaar,
            leading: V360IconButton(
              icon: Icons.arrow_back_rounded,
              color: v360.colors.onBand,
              semanticLabel: 'Back',
              onPressed: () => context.go('/'),
            ),
            figure: Text(
              book.value?.outstanding.display ?? '—',
              style: v360.text.display.copyWith(color: v360.colors.onBand),
            ),
            figureCaption: s.owedToYou,
            facts: <PackFact>[
              PackFact('${book.value?.customers ?? 0}', s.customers),
              PackFact(
                book.value == null || book.value!.oldestDays == 0
                    ? '—'
                    : s.daysOld(book.value!.oldestDays),
                s.oldest,
              ),
            ],
          ),
          Expanded(
            child: RefreshIndicator(
              color: v360.colors.accent,
              onRefresh: () async {
                HapticFeedback.lightImpact();
                ref.invalidate(udhaarBookProvider);
              },
              child: book.when(
                loading: () => ListView(
                  padding: EdgeInsets.all(v360.spacing.gutter),
                  children: const <Widget>[V360Skeleton(height: 220)],
                ),
                error: (error, _) => EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not open the book',
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
                    if (data.isEmpty)
                      EmptyState(
                        icon: Icons.menu_book_outlined,
                        title: s.nobodyOwes,
                        body: 'Add a customer when you give goods on credit, '
                            'and what they owe is counted here.',
                      )
                    else
                      V360Card(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: <Widget>[
                            for (var i = 0; i < data.rows.length; i++) ...<Widget>[
                              if (i > 0) Divider(indent: v360.spacing.lg),
                              _DebtorRow(row: data.rows[i], strings: s),
                            ],
                          ],
                        ),
                      ),
                    SizedBox(height: v360.spacing.lg),
                    V360Button.secondary(
                      label: s.addCustomer,
                      leadingIcon: Icons.person_add_alt_1_outlined,
                      expand: true,
                      onPressed: () => _addCustomer(context, ref, s),
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

  Future<void> _addCustomer(
    BuildContext context,
    WidgetRef ref,
    Strings s,
  ) async {
    final name = TextEditingController();
    final phone = TextEditingController();

    final added = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.addCustomer),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: s.customerName),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              // Optional on purpose: a paper khata says "Suresh, corner
              // house", and a form that demands a number before it will
              // record a debt is a form the shopkeeper stops using.
              decoration: InputDecoration(labelText: s.phoneOptional),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.save),
          ),
        ],
      ),
    );

    if (added != true || name.text.trim().isEmpty) return;

    try {
      final customer = await ref.read(marketplaceProvider).addCustomer(
            name: name.text.trim(),
            phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
          );
      ref.invalidate(udhaarBookProvider);
      if (!context.mounted) return;
      context.go('/udhaar/${customer.id}');
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }
}

class _DebtorRow extends StatelessWidget {
  const _DebtorRow({required this.row, required this.strings});

  final UdhaarRow row;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Semantics(
      button: true,
      label: '${row.customer.name}, ${row.owed.display}, '
          '${strings.daysOld(row.daysOutstanding)}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => context.go('/udhaar/${row.customer.id}'),
        child: Padding(
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
                    Text(
                      row.customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: v360.text.titleS.copyWith(color: colors.ink),
                    ),
                    const SizedBox(height: 3),
                    // Colour only where it means something: a debt standing
                    // longer than a month gets the attention square, the rest
                    // just say how old they are.
                    row.stale
                        ? StatusMark(
                            label: strings.daysOld(row.daysOutstanding),
                            color: colors.warning,
                            dense: true,
                          )
                        : Text(
                            strings.daysOld(row.daysOutstanding),
                            style: v360.text.caption
                                .copyWith(color: colors.inkMuted),
                          ),
                  ],
                ),
              ),
              SizedBox(width: v360.spacing.sm),
              Text(
                row.owed.display,
                style: v360.text.titleS
                    .copyWith(color: colors.ink)
                    .weight(FontWeight.w700)
                    .narrow(86),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.inkSubtle),
            ],
          ),
        ),
      ),
    );
  }
}
