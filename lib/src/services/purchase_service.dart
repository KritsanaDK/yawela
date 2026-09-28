import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

typedef LoadCachedEntitlement = Future<bool> Function();

typedef PersistEntitlement =
    Future<void> Function({
      required String productId,
      required String transactionId,
    });

/// Coordinates the single, lifetime premium purchase with the platform store.
///
/// The medicine database remains the source of truth for app data. This service
/// only owns store state and the cached premium entitlement supplied through
/// [loadCachedEntitlement] and [persistEntitlement].
class PurchaseService extends ChangeNotifier {
  PurchaseService({
    required this.loadCachedEntitlement,
    required this.persistEntitlement,
    InAppPurchase? inAppPurchase,
  }) : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance;

  static const String premiumProductId = String.fromEnvironment(
    'PREMIUM_PRODUCT_ID',
    defaultValue: 'medireminder.premium.lifetime.v1',
  );

  static const Set<String> _allowedProductIds = <String>{premiumProductId};

  final LoadCachedEntitlement loadCachedEntitlement;
  final PersistEntitlement persistEntitlement;
  final InAppPurchase _inAppPurchase;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Future<void> _purchaseUpdateQueue = Future<void>.value();
  Future<void>? _initialization;
  final Set<String> _persistedPurchaseKeys = <String>{};

  ProductDetails? _premiumProduct;
  bool _isPremium = false;
  bool _storeAvailable = false;
  bool _isPurchasePending = false;
  bool _productFound = false;
  bool _initialized = false;
  bool _disposed = false;
  int _loadingOperations = 0;
  String? _localizedPrice;
  String? _errorMessage;

  bool get isPremium => _isPremium;

  bool get storeAvailable => _storeAvailable;

  bool get isLoading => _loadingOperations > 0;

  bool get isPurchasePending => _isPurchasePending;

  String? get localizedPrice => _localizedPrice;

  bool get productFound => _productFound;

  String? get errorMessage => _errorMessage;

  /// Loads the offline entitlement, then connects to and queries the store.
  ///
  /// The purchase stream is subscribed synchronously before the first await so
  /// unfinished transactions from an earlier app session are not missed.
  Future<void> initialize() {
    _ensureNotDisposed();
    _subscribeToPurchaseUpdates();

    if (_initialized) {
      return Future<void>.value();
    }

    final runningInitialization = _initialization;
    if (runningInitialization != null) {
      return runningInitialization;
    }

    final initialization = _initializeStore();
    _initialization = initialization;
    return initialization;
  }

  Future<void> _initializeStore() async {
    _errorMessage = null;
    _beginLoading();

    try {
      try {
        final cachedEntitlement = await loadCachedEntitlement();
        // Never overwrite an entitlement that may have arrived from the
        // purchase stream while the cached value was being loaded.
        if (cachedEntitlement) {
          _isPremium = true;
          _notifySafely();
        }
      } on Object catch (error, stackTrace) {
        _recordFailure(
          'Unable to load the saved premium status.',
          error,
          stackTrace,
        );
      }

      try {
        _storeAvailable = await _inAppPurchase.isAvailable();
      } on Object catch (error, stackTrace) {
        _storeAvailable = false;
        _clearProduct();
        _recordFailure(
          'The app store is currently unavailable.',
          error,
          stackTrace,
        );
        return;
      }

      if (!_storeAvailable) {
        _clearProduct();
        _errorMessage ??= 'The app store is currently unavailable.';
        _notifySafely();
        return;
      }

      try {
        final response = await _inAppPurchase.queryProductDetails(
          _allowedProductIds,
        );
        _premiumProduct = _findPremiumProduct(response.productDetails);
        _productFound = _premiumProduct != null;
        _localizedPrice = _premiumProduct?.price;

        final queryError = response.error;
        if (queryError != null) {
          _errorMessage = _iapErrorMessage(
            queryError,
            fallback: 'Unable to load premium purchase information.',
          );
        } else if (!_productFound) {
          _errorMessage = response.notFoundIDs.contains(premiumProductId)
              ? 'The premium product is not configured for this app.'
              : 'The premium product is currently unavailable.';
        }
        _notifySafely();
      } on Object catch (error, stackTrace) {
        _clearProduct();
        _recordFailure(
          'Unable to load premium purchase information.',
          error,
          stackTrace,
        );
      }
    } finally {
      _initialized = true;
      _initialization = null;
      _endLoading();
    }
  }

  /// Starts the non-consumable lifetime purchase flow.
  ///
  /// The returned store result only confirms that the purchase sheet launched;
  /// the final outcome is processed from the purchase stream.
  Future<void> buyLifetime() async {
    _ensureNotDisposed();
    await initialize();
    if (!_storeAvailable || _premiumProduct == null) {
      await _refreshStoreConnection();
    }

    if (_isPremium || _isPurchasePending) {
      return;
    }

    final product = _premiumProduct;
    if (!_storeAvailable) {
      _setError('The app store is currently unavailable.');
      return;
    }
    if (product == null) {
      _setError('The premium product is currently unavailable.');
      return;
    }

    _errorMessage = null;
    _isPurchasePending = true;
    _beginLoading();

    try {
      final launched = await _inAppPurchase.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      if (!launched) {
        _isPurchasePending = false;
        _setError('The purchase could not be started. Please try again.');
      }
    } on Object catch (error, stackTrace) {
      _isPurchasePending = false;
      _recordFailure(
        'The purchase could not be started. Please try again.',
        error,
        stackTrace,
      );
    } finally {
      _endLoading();
    }
  }

  /// Requests restoration of previous non-consumable purchases.
  ///
  /// Restored purchases are validated and delivered through the same purchase
  /// stream as new purchases.
  Future<void> restorePurchases() async {
    _ensureNotDisposed();
    await initialize();
    if (!_storeAvailable) {
      await _refreshStoreConnection();
    }

    if (!_storeAvailable) {
      _setError('The app store is currently unavailable.');
      return;
    }

    _errorMessage = null;
    _beginLoading();
    try {
      await _inAppPurchase.restorePurchases();
    } on Object catch (error, stackTrace) {
      _recordFailure(
        'Previous purchases could not be restored. Please try again.',
        error,
        stackTrace,
      );
    } finally {
      _endLoading();
    }
  }

  void _subscribeToPurchaseUpdates() {
    if (_purchaseSubscription != null) {
      return;
    }

    _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
      _enqueuePurchaseUpdates,
      onError: (Object error, StackTrace stackTrace) {
        _isPurchasePending = false;
        _recordFailure(
          'Purchase updates are temporarily unavailable.',
          error,
          stackTrace,
        );
      },
    );
  }

  Future<void> _refreshStoreConnection() {
    _initialized = false;
    return initialize();
  }

  void _enqueuePurchaseUpdates(List<PurchaseDetails> purchases) {
    _purchaseUpdateQueue = _purchaseUpdateQueue.then((_) async {
      try {
        for (final purchase in purchases) {
          await _handlePurchase(purchase);
        }
      } on Object catch (error, stackTrace) {
        _isPurchasePending = false;
        _recordFailure(
          'The purchase could not be processed. It will be retried.',
          error,
          stackTrace,
        );
      }
    });
  }

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    var canCompletePurchase = false;

    switch (purchase.status) {
      case PurchaseStatus.pending:
        if (_isAllowedProduct(purchase)) {
          _errorMessage = null;
          _isPurchasePending = true;
          _notifySafely();
        }
        return;

      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        _isPurchasePending = true;
        _beginLoading();
        try {
          if (!_isAllowedProduct(purchase)) {
            _isPurchasePending = false;
            _setError('The store returned an unsupported premium product.');
            canCompletePurchase = true;
            break;
          }

          final verified = await _verifyPurchaseForMvp(purchase);
          if (!verified) {
            _isPurchasePending = false;
            _setError('The premium purchase could not be verified.');
            canCompletePurchase = true;
            break;
          }

          final identity = _purchaseIdentity(purchase);
          if (identity == null) {
            throw StateError(
              'The store did not provide a stable transaction identifier.',
            );
          }
          if (!_persistedPurchaseKeys.contains(identity.deduplicationKey)) {
            // Persist first. If this throws, the transaction intentionally
            // remains unfinished so the store can redeliver it later.
            await persistEntitlement(
              productId: purchase.productID,
              transactionId: identity.transactionId,
            );
            _persistedPurchaseKeys.add(identity.deduplicationKey);
          }

          _isPremium = true;
          _isPurchasePending = false;
          _errorMessage = null;
          canCompletePurchase = true;
          _notifySafely();
        } on Object catch (error, stackTrace) {
          // Keep the pending state: the transaction was deliberately not
          // completed and the store can redeliver it for recovery.
          _isPurchasePending = true;
          _recordFailure(
            'Premium was purchased but could not be saved. It will be retried.',
            error,
            stackTrace,
          );
        } finally {
          _endLoading();
        }
        break;

      case PurchaseStatus.error:
        _isPurchasePending = false;
        _errorMessage = _iapErrorMessage(
          purchase.error,
          fallback: 'The purchase could not be completed.',
        );
        canCompletePurchase = true;
        _notifySafely();
        break;

      case PurchaseStatus.canceled:
        _isPurchasePending = false;
        _errorMessage = null;
        canCompletePurchase = true;
        _notifySafely();
        break;
    }

    if (canCompletePurchase && purchase.pendingCompletePurchase) {
      await _completePurchaseSafely(purchase);
    }
  }

  /// MVP verification boundary.
  ///
  /// This client-only implementation trusts a successful/restored status from
  /// the platform plugin and verifies only the product allow-list. It is not
  /// tamper-proof. Before selling at scale, replace this method with backend
  /// verification of [PurchaseDetails.verificationData.serverVerificationData]
  /// and return a signed entitlement for offline caching.
  Future<bool> _verifyPurchaseForMvp(PurchaseDetails purchase) {
    final isDeliveredStatus =
        purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored;
    return Future<bool>.value(isDeliveredStatus && _isAllowedProduct(purchase));
  }

  Future<void> _completePurchaseSafely(PurchaseDetails purchase) async {
    try {
      await _inAppPurchase.completePurchase(purchase);
    } on Object catch (error, stackTrace) {
      _recordFailure(
        'The store could not finish this transaction. It will be retried.',
        error,
        stackTrace,
      );
    }
  }

  ProductDetails? _findPremiumProduct(List<ProductDetails> products) {
    for (final product in products) {
      if (product.id == premiumProductId) {
        return product;
      }
    }
    return null;
  }

  bool _isAllowedProduct(PurchaseDetails purchase) {
    return _allowedProductIds.contains(purchase.productID);
  }

  ({String transactionId, String deduplicationKey})? _purchaseIdentity(
    PurchaseDetails purchase,
  ) {
    final purchaseId = purchase.purchaseID?.trim();
    if (purchaseId != null && purchaseId.isNotEmpty) {
      return (
        transactionId: purchaseId,
        deduplicationKey: '${purchase.productID}:$purchaseId',
      );
    }

    final verificationData = purchase.verificationData.serverVerificationData;
    if (verificationData.isNotEmpty) {
      final fingerprint = _stableFingerprint(verificationData);
      final transactionId = 'receipt:$fingerprint';
      return (
        transactionId: transactionId,
        deduplicationKey: '${purchase.productID}:$transactionId',
      );
    }
    return null;
  }

  String _stableFingerprint(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return '${value.length}-${hash.toRadixString(16)}';
  }

  String _iapErrorMessage(IAPError? error, {required String fallback}) {
    final message = error?.message.trim();
    return message == null || message.isEmpty ? fallback : message;
  }

  void _clearProduct() {
    _premiumProduct = null;
    _productFound = false;
    _localizedPrice = null;
    _notifySafely();
  }

  void _beginLoading() {
    _loadingOperations += 1;
    _notifySafely();
  }

  void _endLoading() {
    if (_loadingOperations > 0) {
      _loadingOperations -= 1;
    }
    _notifySafely();
  }

  void _setError(String message) {
    _errorMessage = message;
    _notifySafely();
  }

  void _recordFailure(String message, Object error, StackTrace stackTrace) {
    _errorMessage = message;
    if (kDebugMode) {
      debugPrint('$message\n$error\n$stackTrace');
    }
    _notifySafely();
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('PurchaseService has already been disposed.');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final subscription = _purchaseSubscription;
    _purchaseSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
