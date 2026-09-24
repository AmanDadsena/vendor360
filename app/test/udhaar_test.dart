import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:vendor360/app/providers.dart';
import 'package:vendor360/data/api_client.dart';
import 'package:vendor360/data/offline_queue.dart';
import 'package:vendor360/data/udhaar_models.dart';
import 'package:vendor360/features/udhaar/reminder.dart';
import 'package:vendor360_core/vendor360_core.dart';

/// The customer credit book on the client.
///
/// The balance and its age come from the server, computed there once, so
/// these tests check the reading of them — and that a shopkeeper with no
/// signal still sees a book rather than an error.
void main() {
  ProviderContainer offline() => ProviderContainer(
        overrides: [
          offlineQueueProvider.overrideWithValue(OfflineQueue.inMemory()),
          apiClientProvider.overrideWithValue(ApiClient(
            client: MockClient(
              (_) async => throw const SocketException('offline'),
            ),
          )),
        ],
      );

  test('a book parses its rows, ages and staleness', () {
    final book = UdhaarBook.fromJson(<String, dynamic>{
      'outstanding': 560.0,
      'customers': 2,
      'oldest_days': 76,
      'rows': <Object?>[
        <String, dynamic>{
          'customer': <String, dynamic>{'id': 'c1', 'name': 'Ramesh Kale'},
          'owed': 240.0,
          'days_outstanding': 76,
          'stale': true,
        },
        <String, dynamic>{
          'customer': <String, dynamic>{
            'id': 'c2',
            'name': 'Anita Joshi',
            'phone': '9822011002',
          },
          'owed': 320.0,
          'days_outstanding': 4,
          'stale': false,
        },
      ],
    });

    expect(book.outstanding.display, '₹560');
    expect(book.rows.first.customer.name, 'Ramesh Kale');
    expect(book.rows.first.stale, isTrue);
    expect(book.rows.last.customer.phone, '9822011002');
  });

  test('a customer with one name still gets a mark', () {
    expect(const Customer(id: 'c', name: 'Suresh').initials, 'SU');
    expect(const Customer(id: 'c', name: 'Suresh Patil').initials, 'SP');
  });

  test('a statement keeps the order the server sent', () {
    final statement = UdhaarStatement.fromJson(<String, dynamic>{
      'customer': <String, dynamic>{'id': 'c1', 'name': 'Ramesh'},
      'owed': 240.0,
      'days_outstanding': 76,
      'entries': <Object?>[
        <String, dynamic>{
          'id': 'e2',
          'kind': 'payment',
          'amount': 100.0,
          'occurred_at': '2026-09-20T10:00:00Z',
        },
        <String, dynamic>{
          'id': 'e1',
          'kind': 'credit',
          'amount': 340.0,
          'occurred_at': '2026-07-10T10:00:00Z',
          'note': 'atta',
        },
      ],
    });

    expect(statement.entries.map((e) => e.kind), ['payment', 'credit']);
    expect(statement.entries.last.isCredit, isTrue);
    expect(statement.entries.last.note, 'atta');
  });

  test('with no signal the book degrades to the seeded one', () async {
    final container = offline();
    addTearDown(container.dispose);

    final book = await container.read(marketplaceProvider).udhaarBook();

    // Degrades rather than throwing: a shopkeeper at the counter still needs
    // to know roughly who owes what.
    expect(book.rows, isNotEmpty);
    expect(book.outstanding.rupees, greaterThan(0));
    // Oldest first, as the server orders it.
    expect(book.rows.first.daysOutstanding,
        greaterThanOrEqualTo(book.rows.last.daysOutstanding));
  });

  test('recording an entry never degrades quietly', () async {
    final container = offline();
    addTearDown(container.dispose);

    // A debt the shopkeeper was told was recorded, that does not exist, is
    // the failure this book cannot afford.
    await expectLater(
      container.read(marketplaceProvider).recordUdhaar(
            customerId: 'c1',
            kind: 'credit',
            amount: 100,
          ),
      throwsA(isA<Object>()),
    );
  });

  group('the reminder the shopkeeper sends', () {
    final since = DateTime(2026, 9, 12);

    String message(AppLanguage language) => reminderMessage(
          shopName: 'Kumar General Stores',
          customerName: 'Suresh',
          owed: Money.rupees(320),
          since: since,
          language: language,
        );

    test('names the shop, the amount and the date', () {
      final text = message(AppLanguage.english);
      expect(text, contains('Kumar General Stores'));
      expect(text, contains('Suresh'));
      expect(text, contains('₹320'));
      expect(text, contains('12 Sep'));
    });

    test('is written in the shop language, since the customer reads it', () {
      expect(message(AppLanguage.hindi), contains('बकाया'));
      expect(message(AppLanguage.marathi), contains('बाकी'));
      // The amount survives translation.
      expect(message(AppLanguage.hindi), contains('₹320'));
    });

    test('asks rather than threatens', () {
      final text = message(AppLanguage.english).toLowerCase();
      expect(text, contains('please'));
      expect(text, isNot(contains('immediately')));
      expect(text, isNot(contains('legal')));
    });
  });
}
