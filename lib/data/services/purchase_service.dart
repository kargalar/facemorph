import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:collection/collection.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../config/app_constants.dart';

class PurchaseService {
  final InAppPurchase _store = InAppPurchase.instance;

  Stream<List<PurchaseDetails>> get purchases => _store.purchaseStream;

  Future<ProductDetails?> loadPremiumProduct() async {
    if (!await _store.isAvailable()) return null;
    final response = await _store.queryProductDetails({
      AppConstants.premiumProductId,
    });
    return response.productDetails.firstOrNull;
  }

  Future<bool> buy(ProductDetails product) => _store.buyNonConsumable(
    purchaseParam: PurchaseParam(productDetails: product),
  );

  Future<void> restore() => _store.restorePurchases();

  Future<void> verify(PurchaseDetails purchase) async {
    await FirebaseFunctions.instanceFor(
      region: 'europe-west1',
    ).httpsCallable('verifyPremiumPurchase').call({
      'productId': purchase.productID,
      'source': purchase.verificationData.source,
      'verificationData': purchase.verificationData.serverVerificationData,
    });
  }

  Future<void> complete(PurchaseDetails purchase) =>
      _store.completePurchase(purchase);
}
