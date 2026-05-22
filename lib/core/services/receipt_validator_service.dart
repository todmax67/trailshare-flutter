import 'dart:io' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Risultato della validazione server-side di un receipt.
///
/// Restituito da [ReceiptValidatorService.validateApple]; usato da
/// [SubscriptionManager] per decidere se attivare lo stato Pro.
class ReceiptValidationResult {
  /// `true` se il receipt è autentico E l'abbonamento è ancora attivo
  /// (non scaduto, non rimborsato, non cancellato).
  final bool valid;

  /// Product ID dell'abbonamento (es. `trailshare_pro_monthly`). `null`
  /// se nessun Pro trovato nel receipt.
  final String? productId;

  /// Timestamp epoch ms di scadenza dell'abbonamento. Utile per
  /// schedulare un re-check prima della scadenza.
  final int? expiresAtMs;

  /// `true` se siamo nel periodo di trial gratuito (14gg per yearly).
  final bool isInTrial;

  /// `true` solo per errori che ci hanno fatto fallback "trust client":
  /// significa che la verifica non è stata possibile (rete, server giù)
  /// e abbiamo deciso di non bloccare l'utente.
  final bool isFallback;

  /// Messaggio diagnostico per debug. Mai mostrato all'utente.
  final String? debugMessage;

  const ReceiptValidationResult({
    required this.valid,
    this.productId,
    this.expiresAtMs,
    this.isInTrial = false,
    this.isFallback = false,
    this.debugMessage,
  });

  /// Costruisce il risultato di "fallback trust" usato quando la chiamata
  /// alla Cloud Function fallisce per motivi non imputabili all'utente.
  /// Restituisce valid=true così non blocchiamo legitimi pagatori per un
  /// problema di rete; la verifica vera arriverà con webhook in futuro.
  factory ReceiptValidationResult.fallbackTrust(
    String? productId,
    String reason,
  ) {
    return ReceiptValidationResult(
      valid: true,
      productId: productId,
      isFallback: true,
      debugMessage: reason,
    );
  }

  /// Risultato "non valido" (receipt rifiutato da Apple, abbonamento
  /// scaduto, rimborsato, ecc.).
  factory ReceiptValidationResult.invalid(String reason) {
    return ReceiptValidationResult(
      valid: false,
      debugMessage: reason,
    );
  }
}

/// Wrapper sulla Cloud Function `validateAppleReceipt` (deployata in
/// `functions/index.js`, region `europe-west3`).
///
/// Pattern: chiama il backend, gestisce gli errori in modo graceful.
/// Se la chiamata fallisce per motivi infrastrutturali (timeout/network),
/// usa la strategia "fallback trust": non blocca l'utente legittimo.
/// La verifica autorevole arriverà eventualmente con i webhook App Store
/// Server Notifications V2 (TODO 6.B5).
class ReceiptValidatorService {
  ReceiptValidatorService._();
  static final ReceiptValidatorService _instance =
      ReceiptValidatorService._();
  factory ReceiptValidatorService() => _instance;

  static const String _region = 'europe-west3';
  static const String _functionName = 'validateAppleReceipt';

  late final FirebaseFunctions _functions =
      FirebaseFunctions.instanceFor(region: _region);

  /// Valida un receipt Apple. [serverVerificationData] è la stringa
  /// base64 ottenuta da `purchase.verificationData.serverVerificationData`.
  Future<ReceiptValidationResult> validateApple({
    required String serverVerificationData,
    required String productId,
  }) async {
    if (!Platform.isIOS) {
      // Sicurezza: la funzione è solo per iOS. Android passa per
      // un'altra cloud function (validateGoogleReceipt, futuro).
      return ReceiptValidationResult.fallbackTrust(
        productId,
        'platform_not_ios',
      );
    }

    try {
      final callable = _functions.httpsCallable(
        _functionName,
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 20),
        ),
      );
      final response = await callable.call<Map<String, dynamic>>({
        'receipt': serverVerificationData,
        'productId': productId,
      });
      final data = response.data;
      debugPrint('[ReceiptValidator] response: $data');

      return ReceiptValidationResult(
        valid: data['valid'] == true,
        productId: data['productId'] as String?,
        expiresAtMs: (data['expiresAtMs'] as num?)?.toInt(),
        isInTrial: data['isInTrial'] == true,
        debugMessage: data['valid'] == true
            ? 'apple_receipt_validated'
            : 'apple_status_${data['appleStatus'] ?? 'unknown'}',
      );
    } on FirebaseFunctionsException catch (e) {
      // Errore HTTPS: distinguiamo tra "il receipt è invalido" (auth/
      // invalid-argument) e "non siamo riusciti a verificare" (unavailable).
      debugPrint(
        '[ReceiptValidator] FirebaseFunctionsException '
        'code=${e.code} message=${e.message}',
      );
      if (e.code == 'invalid-argument' || e.code == 'unauthenticated') {
        return ReceiptValidationResult.invalid('cf_${e.code}');
      }
      return ReceiptValidationResult.fallbackTrust(
        productId,
        'cf_${e.code}',
      );
    } catch (e) {
      debugPrint('[ReceiptValidator] unexpected error: $e');
      return ReceiptValidationResult.fallbackTrust(
        productId,
        'cf_unexpected_${e.runtimeType}',
      );
    }
  }
}
