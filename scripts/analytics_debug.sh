#!/usr/bin/env bash
# Accende o spegne la modalita' debug di Firebase Analytics sul dispositivo
# Android collegato, per far comparire l'app in DebugView.
#
# Perche' esiste: DebugView NON mostra il traffico normale. Mostra solo i
# dispositivi su cui la modalita' e' stata accesa a mano, e non e' una cosa che
# si attiva dall'app — si attiva dal dispositivo. Il 2026-08-17 la schermata
# vuota e' stata scambiata per "la strumentazione non funziona", quando invece
# non era mai stata accesa.
#
# E serve la build di RELEASE: in debug la raccolta e' spenta di proposito
# (growth_analytics_service.dart, `granted && !kDebugMode`), o le decine di hot
# restart dello sviluppo sporcherebbero retention e coorti.
#
# Uso:
#   scripts/analytics_debug.sh on
#   scripts/analytics_debug.sh off
set -euo pipefail

PKG="com.trailshare.app"

if ! command -v adb >/dev/null 2>&1; then
  echo "adb non trovato nel PATH." >&2
  echo "Di solito sta in ~/Library/Android/sdk/platform-tools" >&2
  exit 1
fi

if [ -z "$(adb devices | sed '1d' | grep -w device || true)" ]; then
  echo "Nessun dispositivo collegato e autorizzato." >&2
  echo "Collega il telefono, attiva il debug USB, e accetta il dialogo che" >&2
  echo "compare sullo schermo." >&2
  exit 1
fi

case "${1:-}" in
  on)
    adb shell setprop debug.firebase.analytics.app "$PKG"
    echo "Modalita' debug ACCESA per $PKG."
    echo
    echo "Ora riapri l'app: DebugView si popola in pochi secondi."
    echo "Se resta vuota, il consenso ad Analytics non e' stato dato:"
    echo "controlla in Impostazioni -> Privacy dentro l'app."
    ;;
  off)
    adb shell setprop debug.firebase.analytics.app .none.
    echo "Modalita' debug SPENTA. Il dispositivo torna a mandare come tutti."
    ;;
  *)
    echo "Uso: $0 on|off" >&2
    exit 2
    ;;
esac
