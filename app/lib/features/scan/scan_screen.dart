import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../core/strings.dart';
import '../../data/demo_data.dart';
import '../../data/models.dart';
import '../inventory/inventory_screen.dart';

/// Scan a pack and log it.
///
/// On a phone the camera reads the code and the shelf row opens in the same
/// sheet the inventory list uses. On a laptop there is no camera, so the
/// screen says so and offers the field to type the number into — the same
/// rule the voice screen follows. Every path below the lookup is identical,
/// which is why the fallback is a line of text rather than a second flow.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _typed = TextEditingController();

  MobileScannerController? _camera;
  bool _busy = false;
  String? _lastCode;
  BarcodeHit? _hit;
  String? _miss;

  @override
  void initState() {
    super.initState();
    if (ref.read(cameraSupportProvider).canScan) {
      _camera = MobileScannerController(
        // One symbology family: kirana packs carry EAN and UPC, and narrowing
        // the set makes the read faster and stops a stray QR code on a poster
        // being treated as a product.
        formats: const <BarcodeFormat>[
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upcA,
          BarcodeFormat.upcE,
        ],
      );
    }
  }

  @override
  void dispose() {
    _typed.dispose();
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _lookUp(String raw) async {
    final code = normaliseBarcode(raw);
    if (code == null || _busy) return;
    // The camera fires many times a second at the same pack; only the first
    // read of a given code does any work.
    if (code == _lastCode) return;

    setState(() {
      _busy = true;
      _lastCode = code;
      _hit = null;
      _miss = null;
    });

    final hit = await ref.read(repositoryProvider).scanBarcode(code);
    if (!mounted) return;

    setState(() {
      _busy = false;
      _hit = hit;
      _miss = hit == null ? code : null;
    });

    if (hit == null) {
      HapticFeedback.heavyImpact();
      return;
    }

    HapticFeedback.mediumImpact();
    final item = hit.item;
    if (item != null) {
      await showQuickEditSheet(context, item);
      if (mounted) ref.invalidate(inventoryProvider);
    }
  }

  void _reset() {
    setState(() {
      _lastCode = null;
      _hit = null;
      _miss = null;
      _typed.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final s = ref.watch(stringsProvider);
    final camera = _camera;

    return Scaffold(
      backgroundColor: colors.canvas,
      body: Column(
        children: <Widget>[
          PackHeader(
            title: s.scan,
            subtitle: camera == null ? null : s.pointAtTheBarcode,
            leading: V360IconButton(
              icon: Icons.arrow_back_rounded,
              color: colors.onBand,
              semanticLabel: 'Back',
              onPressed: () => context.go('/'),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(v360.spacing.gutter),
              children: <Widget>[
                if (camera != null)
                  _Viewfinder(controller: camera, onCode: _lookUp)
                else
                  StatusMark(label: s.noCameraHere, color: colors.warning),

                SizedBox(height: v360.spacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _typed,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: s.barcodeNumber),
                        onSubmitted: _lookUp,
                      ),
                    ),
                    SizedBox(width: v360.spacing.sm),
                    V360Button.secondary(
                      label: s.lookUp,
                      loading: _busy,
                      onPressed: _busy ? null : () => _lookUp(_typed.text),
                    ),
                  ],
                ),

                if (_miss != null) ...<Widget>[
                  SizedBox(height: v360.spacing.lg),
                  V360Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        StatusMark(
                          label: s.codeNotRecognised,
                          color: colors.danger,
                        ),
                        SizedBox(height: v360.spacing.xs),
                        Text(
                          _miss!,
                          style:
                              v360.text.body.copyWith(color: colors.inkMuted),
                        ),
                        SizedBox(height: v360.spacing.sm),
                        Text(
                          s.looseGoodsHaveNoCode,
                          style:
                              v360.text.caption.copyWith(color: colors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_hit != null && !_hit!.onTheShelf) ...<Widget>[
                  SizedBox(height: v360.spacing.lg),
                  _Unstocked(hit: _hit!, onDone: _reset),
                ],

                SizedBox(height: v360.spacing.x3),
                SectionLabel(s.codesOnYourShelf),
                SizedBox(height: v360.spacing.sm),
                // Real codes, printed as bars. On a laptop this is what the
                // scan flow can be demonstrated against at all: point a phone
                // at the screen.
                const _ShelfCodes(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The camera, framed as a window in the page rather than a full-bleed sheet.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder({required this.controller, required this.onCode});

  final MobileScannerController controller;
  final void Function(String code) onCode;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;

    return ClipRRect(
      borderRadius: BorderRadius.circular(V360Radius.md),
      child: SizedBox(
        height: 220,
        child: MobileScanner(
          controller: controller,
          onDetect: (capture) {
            for (final barcode in capture.barcodes) {
              final value = barcode.rawValue;
              if (value != null && value.isNotEmpty) {
                onCode(value);
                return;
              }
            }
          },
          errorBuilder: (context, error) => ColoredBox(
            color: v360.colors.surfaceMuted,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(v360.spacing.lg),
                child: Text(
                  // A camera that exists but will not open: permission
                  // refused, or in use elsewhere. Saying so is more use than
                  // a black rectangle.
                  'The camera did not open. Type the code below instead.',
                  textAlign: TextAlign.center,
                  style:
                      v360.text.caption.copyWith(color: v360.colors.inkMuted),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pack the catalogue knows but this shop has never stocked.
class _Unstocked extends ConsumerStatefulWidget {
  const _Unstocked({required this.hit, required this.onDone});

  final BarcodeHit hit;
  final VoidCallback onDone;

  @override
  ConsumerState<_Unstocked> createState() => _UnstockedState();
}

class _UnstockedState extends ConsumerState<_Unstocked> {
  bool _saving = false;

  Future<void> _add() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final hit = widget.hit;
    try {
      await ref.read(repositoryProvider).createItem(
            skuName: hit.skuName,
            category: hit.category,
            unit: hit.unit,
          );
      ref.invalidate(inventoryProvider);
      messenger.showSnackBar(
        SnackBar(content: Text('${hit.skuName} added to your shelf')),
      );
      widget.onDone();
    } catch (error) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not add it. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final s = ref.watch(stringsProvider);

    return V360Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          StatusMark(label: s.notOnYourShelfYet, color: colors.warning),
          SizedBox(height: v360.spacing.sm),
          Text(
            widget.hit.skuName,
            style: v360.text.titleM
                .copyWith(color: colors.ink)
                .weight(FontWeight.w700),
          ),
          Text(
            widget.hit.category,
            style: v360.text.caption.copyWith(color: colors.inkMuted),
          ),
          SizedBox(height: v360.spacing.md),
          V360Button.primary(
            label: s.addToShelf,
            expand: true,
            loading: _saving,
            onPressed: _saving ? null : _add,
          ),
        ],
      ),
    );
  }
}

/// The codes this shop's own packs carry.
class _ShelfCodes extends ConsumerWidget {
  const _ShelfCodes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final items = ref.watch(inventoryProvider).value ?? DemoData.items;
    // Three, not a dozen. Each one needs the full width of the page to be
    // readable: 95 modules across a 130px column is 1.4 pixels a module at
    // 1x, which looks like a barcode and will not scan.
    final scannable =
        items.where((i) => Ean13.isValid(i.barcode ?? '')).take(3).toList();

    if (scannable.isEmpty) {
      return Text(
        'Nothing on your shelf carries a code yet.',
        style: v360.text.caption.copyWith(color: colors.inkMuted),
      );
    }

    return V360Card(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          for (var i = 0; i < scannable.length; i++) ...<Widget>[
            if (i > 0) Divider(indent: v360.spacing.lg),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: v360.spacing.lg,
                vertical: v360.spacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    scannable[i].skuName,
                    style: v360.text.body.copyWith(color: colors.ink),
                  ),
                  SizedBox(height: v360.spacing.sm),
                  PrintedBarcode(code: scannable[i].barcode!, height: 44),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
