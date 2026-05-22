#!/usr/bin/env python3
"""Costruisce translations.json mappando 174 stringhe italiane → IT/EN + chiave.

Logica:
- Stringhe ricorrenti note → riusa chiave già esistente in app_it.arb
- Nuove → genera chiave camelCase semantica + traduzione EN

Output: scripts/i18n_auto/translations.json
"""
from __future__ import annotations
import json
from pathlib import Path

# Mappatura globale: original_italian → (key, en, placeholders)
# Le chiavi già esistenti in .arb vengono SKIPPATE all'append ma usate per il replace.
COMMON: dict[str, tuple[str, str, list[str]]] = {
    "Annulla": ("cancel", "Cancel", []),
    "Salva": ("save", "Save", []),
    "Elimina": ("delete", "Delete", []),
    "Riprova": ("retry", "Retry", []),
    "Chiudi": ("close", "Close", []),
    "Conferma": ("confirm", "Confirm", []),
    "Modifica": ("edit", "Edit", []),
    "Errore": ("error", "Error", []),
    "Nessun contatto": ("noContacts", "No contacts", []),
    "Nessun dato disponibile": ("noDataAvailable", "No data available", []),
}

# Per ogni stringa hardcoded → traduzione mirata.
# Format: {italian_original: (key, en, placeholders_for_dart_call)}
TRANSLATIONS: dict[str, tuple[str, str, list[str]]] = {
    # ─── emergency_contacts_page ───
    "${c.name} non riceverà più notifiche Lifeline.":
        ("contactNoMoreLifelineNotif", "{name} will no longer receive Lifeline notifications.", ["c.name"]),

    # ─── settings_page ───
    "Aggiungi un nuovo profilo business (rifugio, noleggio, ecc.)":
        ("settingsAddBusinessProfileSub", "Add a new business profile (hut, rental, etc.)", []),
    "Inserisci ID business per testare il profilo":
        ("settingsEnterBusinessId", "Enter business ID to test the profile", []),

    # ─── community_track_detail_page ───
    "Segui e registra":
        ("trackFollowAndRecord", "Follow and record", []),
    "Traccia troppo corta per essere seguita":
        ("trackTooShortToFollow", "Track too short to be followed", []),

    # ─── discover_page ───
    "Servizio GPS disattivato. Attivalo nelle impostazioni del telefono.":
        ("gpsServiceDisabled", "GPS service is off. Enable it in your phone settings.", []),
    "Permessi di localizzazione non concessi. Abilitali nelle Impostazioni per centrare la mappa.":
        ("locationPermissionDenied", "Location permission denied. Enable it in Settings to center the map.", []),
    "Impossibile ottenere la posizione (timeout GPS). Riprova all'aperto.":
        ("locationTimeout", "Cannot get position (GPS timeout). Try again outdoors.", []),

    # ─── discover_filter_sheet ───
    "Solo sentieri circolari":
        ("filterOnlyCircular", "Only circular trails", []),
    "Solo sentieri lineari":
        ("filterOnlyLinear", "Only linear trails", []),
    "Tutti i sentieri":
        ("filterAllTrails", "All trails", []),
    "Solo rifugi":
        ("filterOnlyHuts", "Huts only", []),
    "Tutte le difficoltà":
        ("filterAllDifficulties", "All difficulties", []),

    # ─── trail_conditions_section ───
    "Devi effettuare il login per segnalare":
        ("loginRequiredToReport", "You must sign in to report", []),
    "Eliminare segnalazione?":
        ("deleteReportQuestion", "Delete report?", []),
    "La tua segnalazione verrà rimossa.":
        ("reportWillBeRemoved", "Your report will be removed.", []),
    "Errore durante l'eliminazione":
        ("deleteError", "Error during deletion", []),
    "Segnala una condizione":
        ("reportCondition", "Report a condition", []),

    # ─── trail_photos_section ───
    "Foto del sentiero":
        ("trailPhotos", "Trail photos", []),
    "Nessuna foto ancora":
        ("noPhotosYet", "No photos yet", []),
    "Aggiungi foto":
        ("addPhoto", "Add photo", []),
    "Caricamento foto…":
        ("uploadingPhoto", "Uploading photo…", []),
    "Errore caricamento foto":
        ("photoUploadError", "Photo upload error", []),
    "Eliminare foto?":
        ("deletePhotoQuestion", "Delete photo?", []),

    # ─── trail_photo_viewer ───
    "Foto":
        ("photo", "Photo", []),
    "Condividi":
        ("share", "Share", []),
    "Aggiungi una didascalia…":
        ("addCaption", "Add a caption…", []),
    "Salvato":
        ("savedShort", "Saved", []),
    "Errore salvataggio":
        ("saveError", "Save error", []),

    # ─── poi_editor_sheet ───
    "Aggiungi POI":
        ("addPoi", "Add POI", []),  # già esiste
    "Nome del POI":
        ("poiName", "POI name", []),
    "Descrizione (opzionale)":
        ("descriptionOptional", "Description (optional)", []),
    "Seleziona un tipo":
        ("selectType", "Select a type", []),
    "POI creato":
        ("poiCreated", "POI created", []),

    # ─── poi_detail_sheet ───
    "Segnalato da":
        ("reportedBy", "Reported by", []),
    "Eliminare POI?":
        ("deletePoiQuestion", "Delete POI?", []),
    "POI eliminato":
        ("poiDeleted", "POI deleted", []),
    "Apri in mappa":
        ("openInMap", "Open in map", []),
    "Indicazioni":
        ("directions", "Directions", []),

    # ─── review_editor_sheet ───
    "Lascia una recensione":
        ("leaveReview", "Leave a review", []),
    "Modifica la tua recensione":
        ("editYourReview", "Edit your review", []),
    "Tocca le stelle per dare una valutazione":
        ("tapStarsToRate", "Tap stars to rate", []),
    "Cosa ti è piaciuto? Cosa miglioreresti? (opzionale)":
        ("reviewPlaceholder", "What did you like? What could be improved? (optional)", []),
    "Pubblica":
        ("publish", "Publish", []),
    "Recensione pubblicata":
        ("reviewPublished", "Review published", []),
    "Errore pubblicazione":
        ("publishError", "Publish error", []),
    "Devi essere loggato":
        ("mustBeLoggedIn", "You must be signed in", []),
    "Aggiungi un titolo":
        ("addATitle", "Add a title", []),

    # ─── wishlist_button ───
    "Aggiunto ai preferiti":
        ("addedToWishlist", "Added to wishlist", []),
    "Rimosso dai preferiti":
        ("removedFromWishlist", "Removed from wishlist", []),
    "Errore":
        ("error", "Error", []),

    # ─── group_customize_page ───
    "Errore nel salvataggio del colore":
        ("colorSaveError", "Error saving color", []),
    "Errore durante il caricamento":
        ("uploadError", "Error during upload", []),
    "Rimuovere il logo?":
        ("removeLogoQuestion", "Remove logo?", []),
    "Rimuovere la copertina?":
        ("removeCoverQuestion", "Remove cover?", []),
    "Errore export: $e":
        ("genericErrorWith", "Error: {message}", ["e.toString()"]),
    "Esporta membri":
        ("exportMembers", "Export members", []),
    "Errore nel salvataggio":
        ("saveErrorGeneric", "Error during save", []),

    # ─── group_members_page ───
    "Tutti i membri":
        ("allMembers", "All members", []),
    "Rimuovere membro?":
        ("removeMemberQuestion", "Remove member?", []),
    "Membro rimosso":
        ("memberRemoved", "Member removed", []),
    "Promuovi ad admin":
        ("promoteToAdmin", "Promote to admin", []),

    # ─── business_create_page ───
    "Crea il tuo Spazio Pro":
        ("createBusinessSpace", "Create your Pro Space", []),
    "Nome del business":
        ("businessName", "Business name", []),
    "Tipo di attività":
        ("businessType", "Business type", []),
    "Continua":
        ("continueAction", "Continue", []),
    "Salvataggio in corso…":
        ("savingInProgress", "Saving…", []),

    # ─── business_edit_page ───
    "Profilo aggiornato":
        ("profileUpdated", "Profile updated", []),
    "Errore: $e":
        ("genericErrorWith", "Error: {message}", ["e.toString()"]),
    "Modifica profilo":
        ("editProfile", "Edit profile", []),
    "Descrizione breve (per le card)":
        ("shortDescriptionForCards", "Short description (for cards)", []),
    "Via / Località":
        ("streetLocation", "Street / Location", []),
    "Città":
        ("city", "City", []),
    "Posizione aggiornata. Salva per applicare.":
        ("positionUpdatedSaveToApply", "Position updated. Save to apply.", []),
    "Non impostato":
        ("notSet", "Not set", []),

    # ─── business_profile_page ───
    "Recensioni":
        ("reviews", "Reviews", []),
    "Galleria":
        ("gallery", "Gallery", []),
    "Servizi":
        ("services", "Services", []),
    "Contatti":
        ("contacts", "Contacts", []),
    "Apri sito":
        ("openWebsite", "Open website", []),
    "Chiama":
        ("call", "Call", []),

    # ─── business_reviews_page ───
    "Nessuna recensione ancora":
        ("noReviewsYet", "No reviews yet", []),
    "Grazie per la tua recensione!":
        ("thanksForReview", "Thanks for your review!", []),
    "Elimina la tua recensione?":
        ("deleteYourReviewQuestion", "Delete your review?", []),

    # ─── business_services_manager_page ───
    "Aggiungi un servizio":
        ("addService", "Add a service", []),
    "Nessun servizio configurato":
        ("noServicesConfigured", "No services configured", []),
    "Modifica servizio":
        ("editService", "Edit service", []),
    "Elimina servizio":
        ("deleteService", "Delete service", []),
    "Disponibilità":
        ("availability", "Availability", []),
    "Prezzo":
        ("price", "Price", []),

    # ─── admin_panel_page ───
    "Pannello admin":
        ("adminPanel", "Admin panel", []),
    "Gestione utenti":
        ("userManagement", "User management", []),
    "Statistiche database":
        ("databaseStats", "Database stats", []),
    "Import sentieri":
        ("importTrails", "Import trails", []),
    "Migrazione geohash":
        ("geohashMigration", "Geohash migration", []),
    "Ricalcola statistiche":
        ("recalculateStats", "Recalculate stats", []),
    "Stats utenti":
        ("userStats", "User stats", []),

    # ─── database_stats_page ───
    "Caricamento statistiche...":
        ("loadingStats", "Loading stats...", []),
    "Errore: $_error":
        ("genericErrorWith", "Error: {message}", ["_error.toString()"]),
    "Sentieri Pubblici":
        ("publicTrails", "Public Trails", []),
    "Utenti Registrati":
        ("registeredUsers", "Registered Users", []),
    "Tracce Registrate":
        ("recordedTracks", "Recorded Tracks", []),
    "Cheers/Traccia":
        ("cheersPerTrack", "Cheers/Track", []),
    "Elevazione Sentieri":
        ("trailElevation", "Trail Elevation", []),
    "Nessuna traccia pubblicata":
        ("noPublishedTrack", "No published track", []),
    "Nessun utente registrato":
        ("noRegisteredUser", "No registered user", []),

    # ─── trail_import_page ───
    "Import sentieri":
        ("importTrails", "Import trails", []),  # già definita sopra
    "Avvia import":
        ("startImport", "Start import", []),
    "Import in corso...":
        ("importInProgress", "Import in progress...", []),
    "Aggiorna trail già importati":
        ("updateAlreadyImported", "Update already imported trails", []),
    "Termini di ricerca (uno per riga)":
        ("searchTermsOnePerLine", "Search terms (one per line)", []),
    "Apri Spazio Pro":
        ("openProSpace", "Open Pro Space", []),

    # ─── segment_detail_page ───
    "Classifica":
        ("leaderboard", "Leaderboard", []),
    "Nessun tempo registrato":
        ("noRecordedTime", "No recorded time", []),
    "Tempo personale":
        ("personalTime", "Personal time", []),
    "Posizione":
        ("position", "Position", []),

    # ─── widgets/track_charts_widget extras ───
    # già coperti

    # ─── trail_photo_viewer extras ───
    "Vedi tutte":
        ("seeAll", "See all", []),

    # ─── share_card_widget ───
    "Condividi traccia":
        ("shareTrack", "Share track", []),
    "Salvato in galleria":
        ("savedToGallery", "Saved to gallery", []),

    # ─── interactive_track_map ───
    "Apri in app esterna":
        ("openInExternalApp", "Open in external app", []),
    "Nessuna app disponibile":
        ("noAppAvailable", "No app available", []),
    "Tipo mappa":
        ("mapType", "Map type", []),

    # ─── track_tags_editor ───
    "Aggiungi tag":
        ("addTag", "Add tag", []),

    # ─── share_track_to_group_sheet ───
    "Condividi nel gruppo":
        ("shareInGroup", "Share in group", []),

    # ─── poi_editor_sheet ───
    "Aggiungi POI qui":
        ("addPoiHere", "Add POI here", []),  # già esiste

    # Fallback per stringhe non mappate: skip dal translations.json finale
}


def main() -> None:
    manifest_path = Path("scripts/i18n_auto/manifest.json")
    out_path = Path("scripts/i18n_auto/translations.json")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    # Carica le translations già esistenti per il pilota (paywall_sheet) — preservale
    existing = {}
    if out_path.exists():
        try:
            existing = json.loads(out_path.read_text(encoding="utf-8"))
        except Exception:
            existing = {}

    out: dict[str, list[dict]] = {}
    # Preserva pilota
    for f, items in existing.items():
        if "paywall_sheet" in f:
            out[f] = items

    skipped = []
    for f, items in manifest.items():
        if "paywall_sheet" in f:
            continue
        for it in items:
            original = it["original"]
            if original in TRANSLATIONS:
                key, en, placeholders = TRANSLATIONS[original]
            elif original.strip() in COMMON:
                key, en, placeholders = COMMON[original.strip()]
            else:
                skipped.append((f, it["line"], original))
                continue
            out.setdefault(f, []).append({
                "line": it["line"],
                "original": original,
                "key": key,
                "en": en,
                "wrapper": it["wrapper"],
                "has_interp": it["has_interp"],
                "placeholders": placeholders,
            })

    out_path.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
    total = sum(len(v) for v in out.values())
    print(f"Generate {total} traduzioni in {len(out)} file → {out_path}")
    print(f"Skippate {len(skipped)} stringhe non mappate (da gestire dopo):")
    for f, l, s in skipped[:20]:
        print(f"  {f}:{l} → {s[:80]}")
    if len(skipped) > 20:
        print(f"  ... e altre {len(skipped) - 20}")


if __name__ == "__main__":
    main()
