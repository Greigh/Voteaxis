import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';

/// Year-1 contributions are a web checkout. Cycle Pass, accounts, and StoreKit
/// IAP tips for non-US storefronts stay deferred until contribution data says
/// we need a paid depth tier.
class ContributeLinks {
  ContributeLinks._();

  static final pageUri = Uri.parse(AppConfig.contributeUrl);

  static const _usStorefronts = {'US', 'UM', 'PR', 'GU', 'VI', 'AS', 'MP'};

  /// US App Store may link out to web checkout. Other storefronts wait for
  /// an IAP tip consumable — do not put a purchase CTA in the app there.
  static bool canLinkOutToWebCheckout([Locale? locale]) {
    final code = (locale ?? WidgetsBinding.instance.platformDispatcher.locale)
        .countryCode
        ?.toUpperCase();
    return code != null && _usStorefronts.contains(code);
  }

  static Future<bool> openContributePage({
    Future<bool> Function(Uri uri)? launch,
  }) {
    final opener = launch ?? _launch;
    return opener(pageUri);
  }

  static Future<bool> _launch(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
