import 'package:test/test.dart';
import 'package:vendor360_core/vendor360_core.dart';

void main() {
  group('Quantity', () {
    test('adds and subtracts within a unit', () {
      expect((const Quantity(5, 'kg') + const Quantity(3, 'kg')).amount, 8);
      expect((const Quantity(5, 'kg') - const Quantity(3, 'kg')).amount, 2);
    });

    test('refuses to mix units', () {
      // The offline merge adds deltas from separate devices. Adding kilograms
      // to packets is a bug a bare double cannot catch.
      expect(
        () => const Quantity(5, 'kg') + const Quantity(3, 'pkt'),
        throwsArgumentError,
      );
    });

    test('floors at zero', () {
      expect(const Quantity(-4, 'kg').floored.amount, 0);
      expect(const Quantity(4, 'kg').floored.amount, 4);
    });

    test('trims a trailing .0 when displaying', () {
      expect(const Quantity(5, 'kg').display, '5 kg');
      expect(const Quantity(5.5, 'kg').display, '5.5 kg');
    });
  });

  group('Money', () {
    test('stores paise, not floating rupees', () {
      expect(Money.rupees(10.10).paise, 1010);
      // The failure a double would produce: 0.1 + 0.2 != 0.3.
      final sum = Money.rupees(0.1) + Money.rupees(0.2);
      expect(sum, Money.rupees(0.3));
    });

    test('groups digits the Indian way', () {
      expect(Money.rupees(1234567).display, '₹12,34,567');
      expect(Money.rupees(45678).display, '₹45,678');
      expect(Money.rupees(999).display, '₹999');
    });

    test('multiplies by a quantity', () {
      expect((Money.rupees(24) * 20).display, '₹480');
    });
  });

  group('Confidence', () {
    test('flags anything below the review threshold', () {
      expect(const Confidence(0.9).needsReview, isFalse);
      expect(const Confidence(0.6).needsReview, isTrue);
    });

    test('bands are ordered', () {
      expect(const Confidence(0.95).band, ConfidenceBand.high);
      expect(const Confidence(0.8).band, ConfidenceBand.medium);
      expect(const Confidence(0.6).band, ConfidenceBand.low);
      expect(const Confidence(0.3).band, ConfidenceBand.veryLow);
    });
  });

  group('ShelfLife', () {
    final today = DateTime(2026, 8, 29);

    test('counts days remaining', () {
      expect(
        ShelfLife(expiresOn: DateTime(2026, 9, 1), today: today).daysLeft,
        3,
      );
    });

    test('detects expiry', () {
      final past = ShelfLife(expiresOn: DateTime(2026, 8, 28), today: today);
      expect(past.isExpired, isTrue);
      expect(past.urgency, ExpiryUrgency.expired);
      expect(past.label, 'Expired yesterday');
    });

    test('discount steepens as the window closes', () {
      int discount(int daysOut) => ShelfLife(
            expiresOn: today.add(Duration(days: daysOut)),
            today: today,
          ).suggestedDiscountPct;

      expect(discount(0), 50);
      expect(discount(1), 40);
      expect(discount(3), 20);
      expect(discount(10), 0);
      // Monotonic: a later expiry never earns a deeper markdown.
      expect(discount(1) > discount(2), isTrue);
    });

    test('ignores the time of day', () {
      final life = ShelfLife(
        expiresOn: DateTime(2026, 8, 30, 3),
        today: DateTime(2026, 8, 29, 23),
      );
      expect(life.daysLeft, 1);
    });
  });

  group('InventoryItem', () {
    final today = DateTime(2026, 8, 29);

    InventoryItem item({
      double qty = 50,
      double reorder = 20,
      DateTime? expires,
    }) =>
        InventoryItem(
          id: 'i',
          skuName: 'Milk',
          category: 'dairy',
          quantity: Quantity(qty, 'pkt'),
          reorderPoint: reorder,
          unitCost: Money.rupees(24),
          unitPrice: Money.rupees(28),
          shelfLifeDays: 3,
          expiresOn: expires,
        );

    test('flags low stock against the dynamic threshold', () {
      expect(item(qty: 50).isLow, isFalse);
      expect(item(qty: 20).isLow, isTrue);
      expect(item(qty: 12).isLow, isTrue);
    });

    test('state reports the most urgent fact', () {
      // Low and expired at once must report expired: it is the fact that
      // changes what the vendor does next.
      final expired = item(qty: 5, expires: DateTime(2026, 8, 27));
      expect(expired.state(today), StockState.expired);

      expect(item(qty: 0).state(today), StockState.out);
      expect(item(qty: 10).state(today), StockState.low);
      expect(item(qty: 90).state(today), StockState.healthy);
    });

    test('values stock at cost', () {
      expect(item(qty: 20).valueAtCost, Money.rupees(480));
    });

    test('days of cover is null at zero demand', () {
      expect(item().daysOfCover(0), isNull);
      expect(item(qty: 50).daysOfCover(10), 5);
    });
  });

  group('StockMovement', () {
    test('sale and wastage decrement, restock increments', () {
      expect(MovementKind.sale.sign, -1);
      expect(MovementKind.wastage.sign, -1);
      expect(MovementKind.restock.sign, 1);
    });

    test('delta carries the sign', () {
      final sale = StockMovement(
        id: 'm',
        itemId: 'i',
        kind: MovementKind.sale,
        quantity: const Quantity(5, 'pkt'),
        occurredAt: DateTime(2026, 8, 29),
      );
      expect(sale.delta.amount, -5);
    });

    test('low confidence needs review', () {
      final heard = StockMovement(
        id: 'm',
        itemId: 'i',
        kind: MovementKind.sale,
        quantity: const Quantity(5, 'pkt'),
        occurredAt: DateTime(2026, 8, 29),
        source: CaptureSource.voice,
        confidence: const Confidence(0.5),
      );
      expect(heard.needsReview, isTrue);
    });
  });

  group('HealthScore', () {
    HealthScore score(List<double> values) => HealthScore(
          score: 80,
          band: ScoreBand.strong,
          provisional: false,
          daysOfHistory: 90,
          explanation: '',
          components: [
            ScoreComponent(
              key: 'consistency', label: 'Sales consistency',
              value: values[0], weight: 0.4,
              contribution: values[0] * 0.4, detail: '',
            ),
            ScoreComponent(
              key: 'turnover', label: 'Inventory turnover',
              value: values[1], weight: 0.4,
              contribution: values[1] * 0.4, detail: '',
            ),
            ScoreComponent(
              key: 'waste', label: 'Waste control',
              value: values[2], weight: 0.2,
              contribution: values[2] * 0.2, detail: '',
            ),
          ],
        );

    test('identifies strongest and weakest', () {
      final s = score([90, 60, 75]);
      expect(s.strongest.key, 'consistency');
      expect(s.weakest.key, 'turnover');
    });

    test('detects a uniformly strong profile', () {
      expect(score([99, 98, 97]).isUniformlyStrong, isTrue);
      expect(score([99, 60, 97]).isUniformlyStrong, isFalse);
    });

    test('maps wire bands', () {
      expect(scoreBandFrom('at_risk'), ScoreBand.atRisk);
      expect(scoreBandFrom('anything else'), ScoreBand.provisional);
    });
  });

  group('Forecast', () {
    Forecast forecast(List<(double, String?, double)> spec) => Forecast(
          itemId: 'i',
          skuName: 'Ladoo',
          category: 'sweets',
          headline: '',
          modelVersion: 'v1',
          usedFallback: false,
          historyDays: 90,
          days: [
            for (var i = 0; i < spec.length; i++)
              ForecastDay(
                on: DateTime(2026, 9, 1).add(Duration(days: i)),
                predicted: spec[i].$1,
                lower: spec[i].$1 * 0.8,
                upper: spec[i].$1 * 1.2,
                driver: spec[i].$2,
                driverEffect: spec[i].$3,
              ),
          ],
        );

    test('totals and peaks', () {
      final f = forecast([(10, null, 0), (30, 'Diwali', 1.2), (20, null, 0)]);
      expect(f.total, 60);
      expect(f.peak!.predicted, 30);
    });

    test('dominant driver is the strongest by magnitude', () {
      final f = forecast([
        (10, 'Rain', 0.2),
        (30, 'Diwali', 1.2),
        (20, 'Rain', 0.3),
      ]);
      expect(f.dominantDriver, 'Diwali');
    });

    test('weak signals are not shown as drivers', () {
      final f = forecast([(10, 'Rain', 0.02)]);
      expect(f.days.first.hasSignal, isFalse);
    });

    test('maxPredicted never returns zero', () {
      expect(forecast([(0, null, 0)]).maxPredicted, 1);
    });
  });

  group('Vendor', () {
    const v = Vendor(
      id: 'v',
      name: 'Rakesh Kumar',
      storeName: 'Kumar General Stores',
      phone: '9876500001',
      language: AppLanguage.hindi,
    );

    test('masks the phone number', () {
      expect(v.maskedPhone, '••••••0001');
      expect(v.maskedPhone.contains('98765'), isFalse);
    });

    test('initials come from the store name', () {
      expect(v.initials, 'KG');
    });

    test('language carries its speech locale and endonym', () {
      expect(AppLanguage.marathi.speechLocale, 'mr-IN');
      expect(AppLanguage.marathi.nativeName, 'मराठी');
      expect(languageFromCode('mr'), AppLanguage.marathi);
      expect(languageFromCode('zz'), AppLanguage.hindi);
    });
  });

  _packQuantityTests();
  _approxTests();
}

void _packQuantityTests() {
  group('PackQuantity', () {
    test('rounds up to whole cases — never leaves the shop short', () {
      final plan = PackQuantity.forShortfall(
        shortfall: 12, packSize: 10, unit: 'kg',
      );

      expect(plan.packs, 2);
      expect(plan.quantity, 20);
      expect(plan.surplusOver(12), 8);
      expect(plan.moqApplied, isFalse);
    });

    test('an exact multiple has no surplus', () {
      final plan = PackQuantity.forShortfall(
        shortfall: 20, packSize: 10, unit: 'kg',
      );

      expect(plan.packs, 2);
      expect(plan.surplusOver(20), 0);
    });

    test('a minimum order raises the count and says so', () {
      final plan = PackQuantity.forShortfall(
        shortfall: 3, packSize: 10, unit: 'kg', moqPacks: 4,
      );

      expect(plan.packs, 4);
      expect(plan.moqApplied, isTrue,
          reason: 'the count came from the minimum, not from need');
    });

    test('a minimum below what is needed does not apply', () {
      final plan = PackQuantity.forShortfall(
        shortfall: 100, packSize: 10, unit: 'kg', moqPacks: 2,
      );

      expect(plan.packs, 10);
      expect(plan.moqApplied, isFalse);
    });

    test('no shortfall still respects the minimum', () {
      final plan = PackQuantity.forShortfall(
        shortfall: 0, packSize: 12, unit: 'pkt', moqPacks: 1,
      );

      expect(plan.packs, 1);
      expect(plan.moqApplied, isTrue);
    });

    test('a zero pack size is rejected rather than dividing by zero', () {
      expect(
        () => PackQuantity.forShortfall(
          shortfall: 5, packSize: 0, unit: 'kg',
        ),
        throwsArgumentError,
      );
    });

    test('converts to a Quantity that keeps its unit', () {
      final plan = PackQuantity.forShortfall(
        shortfall: 5, packSize: 12, unit: 'pkt',
      );

      expect(plan.asQuantity, const Quantity(12, 'pkt'));
      expect(() => plan.asQuantity + const Quantity(1, 'kg'), throwsArgumentError);
    });

    test('costs are per case, not per unit', () {
      final plan = PackQuantity.forShortfall(
        shortfall: 12, packSize: 10, unit: 'kg',
      );

      expect(plan.costAt(420), 840);
    });

    test('reads the way a wholesaler quotes it', () {
      final plan = PackQuantity.forShortfall(
        shortfall: 12, packSize: 10, unit: 'kg',
      );

      expect(plan.packDisplay, '2 × 10 kg');
      expect(plan.display, '2 cases · 20 kg');
    });

    test('one case is singular', () {
      final plan = PackQuantity.forShortfall(
        shortfall: 4, packSize: 10, unit: 'kg',
      );

      expect(plan.display, '1 case · 10 kg');
    });

    test('editing the count by hand clears the minimum flag', () {
      final plan = PackQuantity.forShortfall(
        shortfall: 3, packSize: 10, unit: 'kg', moqPacks: 4,
      );

      expect(plan.copyWith(packs: 6).moqApplied, isFalse);
      expect(plan.copyWith(packs: 6).quantity, 60);
    });
  });
}

void _approxTests() {
  group('Quantity.approx', () {
    test('drops decimals once the fraction is noise rather than stock', () {
      expect(const Quantity(528.79, 'kg').approx, '529 kg');
      expect(const Quantity(1453.3, 'kg').approx, '1453 kg');
      expect(const Quantity(94.51, 'pkt').approx, '95 pkt');
    });

    test('keeps one decimal below ten, where the fraction is real', () {
      expect(const Quantity(2.46, 'pc').approx, '2.5 pc');
      expect(const Quantity(6.49, 'pc').approx, '6.5 pc');
      expect(const Quantity(0.4, 'kg').approx, '0.4 kg');
    });

    test('never renders a trailing .0', () {
      expect(const Quantity(5.0, 'kg').approx, '5 kg');
      expect(const Quantity(0.0, 'pc').approx, '0 pc');
    });

    test('leaves the precise display alone', () {
      // The shelf-count case still gets its two decimals.
      expect(const Quantity(2.46, 'pc').display, '2.46 pc');
    });
  });
}
