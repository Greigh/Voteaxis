import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voteaxis/services/contribute_links.dart';

void main() {
  test('US storefronts may link out to web checkout', () {
    expect(
      ContributeLinks.canLinkOutToWebCheckout(const Locale('en', 'US')),
      isTrue,
    );
    expect(
      ContributeLinks.canLinkOutToWebCheckout(const Locale('en', 'PR')),
      isTrue,
    );
  });

  test('non-US storefronts do not get an in-app checkout CTA', () {
    expect(
      ContributeLinks.canLinkOutToWebCheckout(const Locale('en', 'GB')),
      isFalse,
    );
    expect(
      ContributeLinks.canLinkOutToWebCheckout(const Locale('en')),
      isFalse,
    );
  });

  test('contribute page is the marketing-site checkout', () {
    expect(
      ContributeLinks.pageUri.toString(),
      'https://voteaxis.org/contribute',
    );
  });
}
