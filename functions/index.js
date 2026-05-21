// File: functions/index.js (VERSIONE CORRETTA E COMPLETA)

const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const { onCall, onRequest } = require("firebase-functions/v2/https");
const functions = require("firebase-functions");
const { logger } = require("firebase-functions");
const { defineSecret } = require('firebase-functions/params');
const { GeoPoint, FieldPath } = require("firebase-admin/firestore");
const axios = require('axios');
admin.initializeApp();
const db = admin.firestore();
const storage = admin.storage();
setGlobalOptions({ region: "europe-west3" });
const orsApiKey = defineSecret('ORS_API_KEY');
const stravaClientId = defineSecret('STRAVA_CLIENT_ID');
const stravaClientSecret = defineSecret('STRAVA_CLIENT_SECRET');
const stravaWebhookVerifyToken = defineSecret('STRAVA_WEBHOOK_VERIFY_TOKEN');

// ===================================================================
// FUNZIONI HELPER
// ===================================================================

const activityGroupMap = {
    'trekking': 'trekking', 'camminata': 'trekking', 'alpinismo': 'trekking', 'scialpinismo': 'trekking',
    'trail-running': 'run', 'corsa': 'run',
    'bike': 'bike', 'mtb': 'bike', 'ebike': 'bike',
};

function getWeekKey(date) {
    const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
    d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay() || 7));
    const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
    const weekNo = Math.ceil((((d - yearStart) / 86400000) + 1) / 7);
    return `${d.getUTCFullYear()}-W${String(weekNo).padStart(2, '0')}`;
}

const XP_PER_KM = 10;
const XP_PER_100M_ELEVATION = 20;
const XP_BONUS_SHARE = 50;
const XP_FOR_SAVING_TRACK = 25;


// ===================================================================
// FUNZIONE PER LA DASHBOARD
// ===================================================================

exports.getProfileDashboardStats = onCall(async (request) => {
    if (!request.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Devi essere loggato.');
    }
    const userId = request.auth.uid;
    logger.info(`Calcolo statistiche dashboard per l'utente: ${userId}`);

    const tracksRef = db.collection('users').doc(userId).collection('tracks');
    const tracksSnapshot = await tracksRef.get();

    // Inizializza le strutture dati per le statistiche
    let totalDistance = 0, totalElevationGain = 0, totalDuration = 0;
    let activityTypes = {};
    let longestTrack = { name: 'Nessuna traccia', distance: 0 };
    let highestElevationTrack = { name: 'Nessuna traccia', elevationGain: 0 };
    let longestDurationTrack = { name: 'Nessuna traccia', duration: 0 };

    // Strutture per le time series
    const timeSeries = {
        byDay: {},   // "YYYY-MM-DD": { distance: {...}, elevation: {...} }
        byWeek: {},  // "YYYY-WXX": { distance: {...}, elevation: {...} }
        byMonth: {}  // "YYYY-MM": { distance: {...}, elevation: {...} }
    };

    if (tracksSnapshot.empty) {
        // Ritorna i dati vuoti
        return {
            totalTracks: 0, totalDistance, totalElevationGain, totalDuration,
            activityTypes, longestTrack, highestElevationTrack, longestDurationTrack,
            timeSeries // timeSeries sarà { byDay: {}, byWeek: {}, byMonth: {} }
        };
    }

    // Conta solo le tracce realmente registrate (escludi planner-only).
    let realTracksCount = 0;
    tracksSnapshot.forEach(doc => {
        try {
            const track = doc.data();
            if (!track) return;
            // Escludi le tracce pianificate (Planner ORS): non sono
            // attività svolte, non devono concorrere a totali, record
            // e time series del dashboard.
            if (track.isPlanned === true) return;
            realTracksCount += 1;

            // --- Statistiche Totali (solo tracce non pianificate) ---
            totalDistance += track.distance || 0;
            totalElevationGain += track.elevationGain || 0;
            totalDuration += track.duration || 0;
            if ((track.distance || 0) > longestTrack.distance) longestTrack = { name: track.name, distance: (track.distance || 0) };
            if ((track.elevationGain || 0) > highestElevationTrack.elevationGain) highestElevationTrack = { name: track.name, elevationGain: (track.elevationGain || 0) };
            if ((track.duration || 0) > longestDurationTrack.duration) longestDurationTrack = { name: track.name, duration: (track.duration || 0) };
            
            const type = track.activityType || 'trekking';
            activityTypes[type] = (activityTypes[type] || 0) + 1;

            // --- Statistiche TimeSeries ---
            let activityDate;
            if (track.recordedAt) {
                activityDate = new Date(track.recordedAt);
            } else if (track.createdAt && track.createdAt.toDate) {
                activityDate = track.createdAt.toDate();
            } else {
                return; // Salta la traccia se non ha data
            }

            if (activityDate && !isNaN(activityDate.getTime())) {
                const distanceKm = (track.distance || 0) / 1000;
                const elevation = track.elevationGain || 0;
                const group = activityGroupMap[type] || 'trekking';

                const dayKey = activityDate.toISOString().split('T')[0]; // "YYYY-MM-DD"
                const weekKey = getWeekKey(activityDate); // "YYYY-WXX"
                const monthKey = `${activityDate.getFullYear()}-${String(activityDate.getMonth() + 1).padStart(2, '0')}`; // "YYYY-MM"

                // Funzione helper per aggregare i dati
                const aggregate = (series, key) => {
                    if (!series[key]) {
                        series[key] = {
                            distance: { all: 0, trekking: 0, bike: 0, run: 0 },
                            elevation: { all: 0, trekking: 0, bike: 0, run: 0 }
                        };
                    }
                    series[key].distance.all += distanceKm;
                    series[key].distance[group] += distanceKm;
                    series[key].elevation.all += elevation;
                    series[key].elevation[group] += elevation;
                };

                aggregate(timeSeries.byDay, dayKey);
                aggregate(timeSeries.byWeek, weekKey);
                aggregate(timeSeries.byMonth, monthKey);
            }
        } catch (e) {
            logger.error(`Errore nel processare la traccia ${doc.id}:`, e);
        }
    });

    return {
        totalTracks: realTracksCount,
        totalDistance,
        totalElevationGain,
        totalDuration,
        activityTypes,
        longestTrack,
        highestElevationTrack,
        longestDurationTrack,
        timeSeries // Ritorna gli oggetti aggregati
    };
});

// ===================================================================
// FUNZIONI TRIGGER (onTrackCreate, oncheerCreated, etc.)
// ===================================================================

exports.onTrackCreate = onDocumentCreated("users/{userId}/tracks/{trackId}", async (event) => {
    const snap = event.data;
    if (!snap) {
        logger.log("Nessun dato per l'evento onTrackCreate.");
        return null;
    }
    const trackData = snap.data();
    const { userId } = event.params;
    const userProfileRef = db.collection("user_profiles").doc(userId);

    // --- 1. Logica per gli XP (ORA COMPLETA) ---
    let totalXpGained = XP_FOR_SAVING_TRACK; // XP base per il salvataggio

    if (trackData.distance) {
        totalXpGained += Math.round((trackData.distance / 1000) * XP_PER_KM);
    }
    if (trackData.elevationGain) {
        totalXpGained += Math.round((trackData.elevationGain / 100) * XP_PER_100M_ELEVATION);
    }
    if (trackData.isPublic) {
        totalXpGained += XP_BONUS_SHARE;
    }
    // --- FINE LOGICA XP ---

    if (totalXpGained > 0) {
        logger.info(`Assegnazione di ${totalXpGained} XP all'utente ${userId}.`);
        // Usiamo set con { merge: true } per creare il campo se non esiste, più sicuro di update
        await userProfileRef.set({
            xp: admin.firestore.FieldValue.increment(totalXpGained)
        }, { merge: true });
    }

    // --- 2. LOGICA Aggiornamento Progressi Sfide (invariata) ---
    logger.info(`Controllo progressi sfide per l'utente ${userId}...`);
    
    const participantSnapshot = await db.collectionGroup("participants").where("userId", "==", userId).get();

    if (participantSnapshot.empty) {
        logger.info("L'utente non è iscritto a nessuna sfida. Termino.");
        return null;
    }
    
    for (const participantDoc of participantSnapshot.docs) {
        const challengeRef = participantDoc.ref.parent.parent;
        if (!challengeRef) continue;
        const challengeDoc = await challengeRef.get();

        if (!challengeDoc.exists) continue;

        const challengeData = challengeDoc.data();
        if (challengeData.endDate.toDate() < new Date()) {
            continue;
        }

        // Controllo per tipo di attività
        if (challengeData.activityType && challengeData.activityType !== 'all') {
            const trackActivityGroup = activityGroupMap[trackData.activityType] || 'trekking';
            if (trackActivityGroup !== challengeData.activityType) {
                logger.info(`Sfida ${challengeDoc.id} saltata: richiede '${challengeData.activityType}', ma l'attività è '${trackActivityGroup}'.`);
                continue;
            }
        }

        let progressUpdate = 0;
        switch (challengeData.type) {
            case "ELEVATION_TOTAL":
                progressUpdate = trackData.elevationGain || 0;
                break;
            case "DISTANCE_TOTAL":
                progressUpdate = trackData.distance || 0;
                break;
            default:
                continue;
        }

        if (progressUpdate > 0) {
            logger.info(`Aggiorno progresso di ${progressUpdate} per la sfida ${challengeDoc.id}.`);
            await participantDoc.ref.update({
                progress: admin.firestore.FieldValue.increment(progressUpdate)
            });
        }
    }

    return null;
});

// ===================================================================
// TRIGGER: Aggiornamento Traccia (per sfide quando traccia completata)
// ===================================================================
exports.onTrackUpdate = onDocumentUpdated("users/{userId}/tracks/{trackId}", async (event) => {
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    const { userId } = event.params;

    // Evita loop: processa solo se la traccia passa da "pending" a "completa"
    // oppure se distance/elevationGain cambiano da 0 a un valore positivo
    const wasIncomplete = !beforeData.distance || beforeData.distance === 0 || beforeData.isPending === true;
    const isNowComplete = afterData.distance && afterData.distance > 0 && afterData.isPending !== true;

    if (!wasIncomplete || !isNowComplete) {
        logger.info(`[onTrackUpdate] Traccia ${event.params.trackId} non richiede aggiornamento sfide (wasIncomplete: ${wasIncomplete}, isNowComplete: ${isNowComplete})`);
        return null;
    }

    logger.info(`[onTrackUpdate] Traccia ${event.params.trackId} completata per utente ${userId}. Aggiorno sfide...`);

    // --- Logica Aggiornamento Progressi Sfide (identica a onTrackCreate) ---
    const participantSnapshot = await db.collectionGroup("participants").where("userId", "==", userId).get();

    if (participantSnapshot.empty) {
        logger.info("[onTrackUpdate] L'utente non è iscritto a nessuna sfida. Termino.");
        return null;
    }
    
    for (const participantDoc of participantSnapshot.docs) {
        const challengeRef = participantDoc.ref.parent.parent;
        if (!challengeRef) continue;
        const challengeDoc = await challengeRef.get();

        if (!challengeDoc.exists) continue;

        const challengeData = challengeDoc.data();
        
        // Verifica che la sfida non sia scaduta
        if (challengeData.endDate.toDate() < new Date()) {
            logger.info(`[onTrackUpdate] Sfida ${challengeDoc.id} scaduta, skip.`);
            continue;
        }

        // Controllo per tipo di attività
        if (challengeData.activityType && challengeData.activityType !== 'all') {
            const trackActivityGroup = activityGroupMap[afterData.activityType] || 'trekking';
            if (trackActivityGroup !== challengeData.activityType) {
                logger.info(`[onTrackUpdate] Sfida ${challengeDoc.id} saltata: richiede '${challengeData.activityType}', ma l'attività è '${trackActivityGroup}'.`);
                continue;
            }
        }

        let progressUpdate = 0;
        switch (challengeData.type) {
            case "ELEVATION_TOTAL":
                progressUpdate = afterData.elevationGain || 0;
                break;
            case "DISTANCE_TOTAL":
                progressUpdate = afterData.distance || 0;
                break;
            default:
                continue;
        }

        if (progressUpdate > 0) {
            logger.info(`[onTrackUpdate] Aggiorno progresso di ${progressUpdate} per la sfida ${challengeDoc.id}.`);
            await participantDoc.ref.update({
                progress: admin.firestore.FieldValue.increment(progressUpdate)
            });
        }
    }

    return null;
});

exports.oncheersCreated = onDocumentCreated("published_tracks/{trackId}/cheers/{userId}", async (event) => {
    const trackId = event.params.trackId;
    const creatingUserId = event.params.userId;

    const trackRef = admin.firestore().collection("published_tracks").doc(trackId);
    
    // 1. Increment Counter
    await trackRef.update({ cheerCount: admin.firestore.FieldValue.increment(1) });
    logger.info(`Contatore cheer incrementato per traccia ${trackId}`);

    // 2. Fetch Track Data
    const trackDoc = await trackRef.get();
    if (!trackDoc.exists) { 
        logger.error(`Traccia ${trackId} non trovata durante il cheer.`); 
        return null; 
    }
    
    const trackData = trackDoc.data();
    const ownerId = trackData.originalOwnerId;

    // DEBUG LOGGING: See exactly what IDs are being compared
    logger.info(`Cheer Debug: CreatingUser=${creatingUserId}, TrackOwner=${ownerId}`);

    // 3. Check for Self-Cheer
    // Ensure both are strings and trimmed for safety
    if (String(ownerId).trim() === String(creatingUserId).trim()) { 
        logger.info("Notifica auto-incitamento saltata (Utente ha messo like alla propria traccia)."); 
        return null; 
    }

    // 4. Fetch Owner Profile for FCM Tokens
    const ownerProfileRef = admin.firestore().collection("user_profiles").doc(ownerId);
    const ownerProfileDoc = await ownerProfileRef.get();
    
    if (!ownerProfileDoc.exists) { 
        logger.warn(`Profilo non trovato per il proprietario della traccia ${ownerId}.`); 
        return null; 
    }
    
    const ownerProfileData = ownerProfileDoc.data();
    const tokens = ownerProfileData.fcmTokens;

    if (!tokens || tokens.length === 0) { 
        logger.info(`Nessun token FCM valido per l'utente ${ownerId}. Notifica non inviata.`); 
        return null; 
    }

    // 5. Fetch Giver Profile for Username
    const giverProfileDoc = await admin.firestore().collection("user_profiles").doc(creatingUserId).get();
    const giverUsername = giverProfileDoc.exists ? giverProfileDoc.data().username : "Un utente";

    // 6. Prepare Notification
    const messageBody = {
        notification: {
            title: "❤️ Nuovo cheer!",
            body: `${giverUsername} ha apprezzato il tuo percorso: "${trackData.name || 'Senza nome'}"`,
        },
        data: { 
            trackId: trackId, 
            type: "kudos" // Changed 'cheer' to 'kudos' to match client listener if needed, or keep 'cheer'
        },
    };

    logger.info(`Invio notifica a ${ownerId} su ${tokens.length} dispositivi.`);

    // 7. Send Notification
    const multicastMessage = { ...messageBody, tokens: tokens };
    const response = await admin.messaging().sendEachForMulticast(multicastMessage);

    // 8. Clean up invalid tokens
    if (response.failureCount > 0) {
        const tokensToDelete = [];
        response.responses.forEach((result, index) => {
            const error = result.error;
            if (error) {
                logger.error(`Errore invio a token: ${error.code}`, error);
                if (error.code === 'messaging/registration-token-not-registered' || 
                    error.code === 'messaging/invalid-registration-token') {
                    tokensToDelete.push(tokens[index]);
                }
            }
        });

        if (tokensToDelete.length > 0) {
            logger.info(`Rimozione di ${tokensToDelete.length} token invalidi.`);
            await ownerProfileRef.update({
                fcmTokens: admin.firestore.FieldValue.arrayRemove(...tokensToDelete)
            });
        }
    }

    return null;
});

/// Epic 3.2 — Quando un partecipante di una sfida di gruppo aggiorna
/// le sue standings, verifica se ha raggiunto il target. In quel caso:
///  1. marca la sfida come completata sul doc parent (completedAt/By)
///  2. manda FCM a tutti i membri del gruppo "🏆 X ha vinto la sfida!"
/// La prima scrittura vince (campo completedAt assente ≠ presente).
exports.onChallengeStandingUpdated = onDocumentWritten(
    "groups/{groupId}/challenges/{challengeId}/standings/{userId}",
    async (event) => {
        const after = event.data && event.data.after && event.data.after.exists
            ? event.data.after.data()
            : null;
        if (!after) return null;
        const newValue = Number(after.value || 0);
        if (newValue <= 0) return null;

        const { groupId, challengeId, userId } = event.params;
        const challengeRef = admin.firestore()
            .collection("groups").doc(groupId)
            .collection("challenges").doc(challengeId);

        try {
            // Transaction per evitare double-mark se due saves arrivano contemporanei.
            const completedNow = await admin.firestore().runTransaction(async (tx) => {
                const cSnap = await tx.get(challengeRef);
                if (!cSnap.exists) return false;
                const c = cSnap.data();
                if (c.completedAt) return false; // già vinta
                const target = Number(c.target || 0);
                if (target <= 0 || newValue < target) return false;
                tx.update(challengeRef, {
                    completedAt: admin.firestore.FieldValue.serverTimestamp(),
                    completedByUserId: userId,
                    completedByUsername: after.username || "Utente",
                });
                return true;
            });
            if (!completedNow) return null;

            // Carica gruppo per nome + member tokens
            const groupSnap = await admin.firestore()
                .collection("groups").doc(groupId).get();
            if (!groupSnap.exists) return null;
            const group = groupSnap.data();
            const memberIds = Array.isArray(group.memberIds)
                ? group.memberIds : [];
            const cSnap = await challengeRef.get();
            const challenge = cSnap.data();
            const winnerName = after.username || "Un membro";

            logger.info(
                `[groupChallenge] vinta da ${winnerName} ` +
                `(gid=${groupId} cid=${challengeId}). Notifico ${memberIds.length} membri.`
            );

            for (const memberId of memberIds) {
                try {
                    const profileRef = admin.firestore()
                        .collection("user_profiles").doc(memberId);
                    const profileSnap = await profileRef.get();
                    if (!profileSnap.exists) continue;
                    const tokens = profileSnap.data().fcmTokens;
                    if (!tokens || tokens.length === 0) continue;
                    const isWinner = memberId === userId;
                    const message = {
                        notification: {
                            title: isWinner
                                ? `🏆 Hai vinto la sfida!`
                                : `🏆 Sfida ${group.name || "di gruppo"} vinta!`,
                            body: isWinner
                                ? `Hai completato "${challenge.title}" nel gruppo ${group.name || ""}`
                                : `${winnerName} ha completato "${challenge.title}"`,
                        },
                        data: {
                            type: "group_challenge_won",
                            groupId: groupId,
                            challengeId: challengeId,
                        },
                        tokens: tokens,
                    };
                    const response = await admin.messaging()
                        .sendEachForMulticast(message);
                    if (response.failureCount > 0) {
                        const toDelete = [];
                        response.responses.forEach((r, i) => {
                            if (r.error && (
                                r.error.code === "messaging/registration-token-not-registered" ||
                                r.error.code === "messaging/invalid-registration-token"
                            )) {
                                toDelete.push(tokens[i]);
                            }
                        });
                        if (toDelete.length > 0) {
                            await profileRef.update({
                                fcmTokens: admin.firestore.FieldValue
                                    .arrayRemove(...toDelete),
                            });
                        }
                    }
                } catch (e) {
                    logger.error(`[groupChallenge] FCM member ${memberId} error: ${e}`);
                }
            }
        } catch (e) {
            logger.error('[groupChallenge] tx error', e);
        }
        return null;
    }
);

/// Epic 3.6 — Notifica FCM quando un utente viene menzionato in un
/// commento. Il client salva `mentions: { username: uid }` nel doc al
/// momento dell'addComment; qui basta leggere la mappa e inviare a
/// ciascun uid (skipping self-mention).
exports.onCommentCreated = onDocumentCreated(
    "published_tracks/{trackId}/comments/{commentId}",
    async (event) => {
        const trackId = event.params.trackId;
        const snap = event.data;
        if (!snap) return null;
        const comment = snap.data();
        const mentions = comment.mentions || {};
        const mentionedUids = Object.values(mentions).filter(Boolean);
        if (mentionedUids.length === 0) return null;

        const authorId = String(comment.userId || "");
        const authorUsername = comment.username || "Un utente";

        const trackDoc = await admin.firestore()
            .collection("published_tracks").doc(trackId).get();
        const trackName = trackDoc.exists
            ? (trackDoc.data().name || "una traccia")
            : "una traccia";

        for (const uid of mentionedUids) {
            // Skip self-mention
            if (String(uid).trim() === authorId.trim()) {
                logger.info(`Mention self-skip per ${uid}`);
                continue;
            }
            try {
                const profileRef = admin.firestore()
                    .collection("user_profiles").doc(uid);
                const profileDoc = await profileRef.get();
                if (!profileDoc.exists) continue;
                const tokens = profileDoc.data().fcmTokens;
                if (!tokens || tokens.length === 0) continue;

                const message = {
                    notification: {
                        title: "💬 Ti hanno menzionato",
                        body: `${authorUsername} ti ha citato in un commento su "${trackName}"`,
                    },
                    data: {
                        type: "mention",
                        trackId: trackId,
                        commentId: event.params.commentId,
                    },
                    tokens: tokens,
                };
                const response = await admin.messaging()
                    .sendEachForMulticast(message);
                logger.info(
                    `Mention notify uid=${uid}: ` +
                    `success=${response.successCount} fail=${response.failureCount}`
                );

                // Pulizia token invalidi (stesso pattern di oncheersCreated)
                if (response.failureCount > 0) {
                    const toDelete = [];
                    response.responses.forEach((r, i) => {
                        if (r.error && (
                            r.error.code === "messaging/registration-token-not-registered" ||
                            r.error.code === "messaging/invalid-registration-token"
                        )) {
                            toDelete.push(tokens[i]);
                        }
                    });
                    if (toDelete.length > 0) {
                        await profileRef.update({
                            fcmTokens: admin.firestore.FieldValue
                                .arrayRemove(...toDelete),
                        });
                    }
                }
            } catch (e) {
                logger.error(`Mention notify error per ${uid}: ${e}`);
            }
        }
        return null;
    }
);

exports.onCheerDeleted = onDocumentDeleted("published_tracks/{trackId}/cheers/{userId}", (event) => {
    // ... il codice di questa funzione rimane invariato
    const trackId = event.params.trackId;
    const trackRef = admin.firestore().collection("published_tracks").doc(trackId);
    functions.logger.info(`Contatore cheer decrementato per traccia ${trackId}`);
    return trackRef.update({ cheerCount: admin.firestore.FieldValue.increment(-1) });
});

exports.sendFollowerNotification = onDocumentUpdated("user_profiles/{followedId}", async (event) => {
    // ... il codice di questa funzione rimane invariato
    if (!event.data) { return functions.logger.log("Nessun dato associato all'evento"); }
    const beforeData = event.data.before.data();
    const afterData = event.data.after.data();
    const followedId = event.params.followedId;
    const beforeFollowers = beforeData.followers || [];
    const afterFollowers = afterData.followers || [];
    if (afterFollowers.length <= beforeFollowers.length) { return null; }
    const newFollowerId = afterFollowers.find((id) => !beforeFollowers.includes(id));
    if (!newFollowerId) { return functions.logger.log("Nuovo follower non trovato."); }
    const tokens = afterData.fcmTokens;
    if (!tokens || tokens.length === 0) { return functions.logger.log(`Nessun token FCM per l'utente ${followedId}.`); }
    const followerProfileDoc = await admin.firestore().collection("user_profiles").doc(newFollowerId).get();
    const followerProfileData = followerProfileDoc.data();
    const followerUsername = followerProfileData ? followerProfileData.username : "Un nuovo utente";
    const messageBody = {
        notification: {
            title: "👋 Hai un nuovo follower!",
            body: `${followerUsername} ha iniziato a seguirti.`,
        },
        data: { userId: newFollowerId, type: "new_follower" },
    };
    const multicastMessage = { ...messageBody, tokens: tokens };
    functions.logger.info(`Invio notifica follower a ${followedId}`);
    return admin.messaging().sendEachForMulticast(multicastMessage);
});


// ===================================================================
// FUNZIONI SCHEDULATE (Leaderboards)
// ===================================================================
exports.calculateWeeklyLeaderboards = onSchedule("every sunday 02:00", async (event) => {
    // ... il codice di questa funzione rimane invariato
    logger.info("Inizio calcolo classifiche settimanali...");
    const oneWeekAgo = new Date();
    oneWeekAgo.setDate(oneWeekAgo.getDate() - 7);
    const oneWeekAgoTimestamp = admin.firestore.Timestamp.fromDate(oneWeekAgo);
    const usersSnapshot = await db.collection("user_profiles").get();
    if (usersSnapshot.empty) {
        logger.info("Nessun utente trovato. Calcolo terminato.");
        return null;
    }
    const batch = db.batch();
    for (const userDoc of usersSnapshot.docs) {
        const userId = userDoc.id;
        const userData = userDoc.data();
        const username = userData.username || "Utente";
        const socialCircleIds = [...(userData.following || []), userId];
        const promises = socialCircleIds.map((id) =>
            db.collection("users").doc(id).collection("tracks")
              .where("createdAt", ">=", oneWeekAgoTimestamp)
              .get()
        );
        const results = await Promise.all(promises);
        const weeklyStats = new Map();
        results.forEach((trackSnapshot, index) => {
            const currentUserId = socialCircleIds[index];
            if (trackSnapshot.empty) return;
            let totalDistance = 0, totalElevation = 0, totalXp = 0;
            trackSnapshot.forEach((trackDoc) => {
                const trackData = trackDoc.data();
                // Skip tracce pianificate dal Planner: non sono attività
                // realmente svolte, non danno XP né concorrono ai totali
                // settimanali della leaderboard.
                if (trackData.isPlanned === true) return;
                totalDistance += trackData.distance || 0;
                totalElevation += trackData.elevationGain || 0;
                totalXp += XP_FOR_SAVING_TRACK;
                totalXp += Math.round((trackData.distance / 1000) * XP_PER_KM);
                totalXp += Math.round((trackData.elevationGain / 100) * XP_PER_100M_ELEVATION);
                if (trackData.isPublic) totalXp += XP_BONUS_SHARE;
            });
            weeklyStats.set(currentUserId, {
                distance: totalDistance,
                elevation: totalElevation,
                xp: totalXp,
            });
        });
        const leaderboard = [];
        for (const id of socialCircleIds) {
            const stats = weeklyStats.get(id) || { distance: 0, elevation: 0, xp: 0 };
            const profile = (await db.collection("user_profiles").doc(id).get()).data();
            leaderboard.push({
                userId: id,
                username: profile.username || "Utente",
                avatarUrl: profile.avatarUrl || null,
                ...stats,
            });
        }
        leaderboard.sort((a, b) => b.xp - a.xp || b.distance - a.distance);
        const leaderboardRef = db.collection("leaderboards").doc(userId);
        batch.set(leaderboardRef, {
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            userLeaderboard: leaderboard,
        });
        logger.info(`Classifica calcolata per ${username} con ${leaderboard.length} partecipanti.`);
    }
    await batch.commit();
    logger.info(`Calcolo completato. ${usersSnapshot.size} classifiche sono state aggiornate.`);
    return null;
});


// ===================================================================
// FUNZIONI "CALLABLE" (joinChallenge, getActiveChallenges)
// ===================================================================

exports.joinChallenge = onCall(async (request) => {
    // ... il codice di questa funzione rimane invariato
    if (!request.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Devi essere loggato per partecipare.');
    }
    const userId = request.auth.uid;
    const { challengeId } = request.data;
    if (!challengeId) {
        throw new functions.https.HttpsError('invalid-argument', 'ID della sfida mancante.');
    }
    const challengeRef = db.collection('challenges').doc(challengeId);
    const participantRef = challengeRef.collection('participants').doc(userId);
    const userProfileRef = db.collection('user_profiles').doc(userId);
    try {
        await db.runTransaction(async (transaction) => {
            const challengeDoc = await transaction.get(challengeRef);
            const userProfileDoc = await transaction.get(userProfileRef);
            const participantDoc = await transaction.get(participantRef);
            if (!challengeDoc.exists) { throw new Error("Sfida non trovata."); }
            if (!userProfileDoc.exists) { throw new Error("Profilo utente non trovato."); }
            if (participantDoc.exists) { throw new Error("Sei già iscritto a questa sfida."); }
            const userData = userProfileDoc.data();
            transaction.set(participantRef, {
                userId: userId,
                username: userData.username || "Utente",
                avatarUrl: userData.avatarUrl || null,
                progress: 0,
                isCompleted: false,
                joinedAt: admin.firestore.FieldValue.serverTimestamp()
            });
            transaction.update(challengeRef, {
                participantCount: admin.firestore.FieldValue.increment(1)
            });
        });
        logger.info(`L'utente ${userId} si è iscritto alla sfida ${challengeId}`);
        return { success: true, message: "Iscrizione completata!" };
    } catch (error) {
        logger.error(`Errore durante l'iscrizione alla sfida ${challengeId} per l'utente ${userId}:`, error);
        throw new functions.https.HttpsError('internal', error.message || "Impossibile completare l'iscrizione.");
    }
});

exports.getActiveChallenges = onCall(async (request) => {
    if (!request.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Devi essere loggato per vedere le sfide.');
    }
    try {
        logger.info("Eseguo la query per le sfide attive sul server...");
        const challengesRef = db.collection("challenges");
        
        // --- SINTASSI CORRETTA PER L'ADMIN SDK (SERVER) ---
        const querySnapshot = await challengesRef
                                    .where("endDate", ">=", new Date())
                                    .orderBy("endDate")
                                    .get();
                                    
        if (querySnapshot.empty) {
            logger.info("Nessuna sfida attiva trovata.");
            return [];
        }

        const challenges = querySnapshot.docs.map(doc => {
            const data = doc.data();
            return {
                id: doc.id,
                ...data,
                endDate: data.endDate.toDate().toISOString(),
                createdAt: data.createdAt.toDate().toISOString()
            };
        });
        logger.info(`Trovate ${challenges.length} sfide attive.`);
        return challenges;
    } catch (error) {
        logger.error("Errore critico durante la lettura delle sfide:", error);
        throw new functions.https.HttpsError('internal', "Impossibile recuperare le sfide.");
    }
});

// ===================================================================
// --- NUOVA FUNZIONE SCHEDULATA PER LE SFIDE MENSILI ---
// ===================================================================
/// Epic 6.C3 — Benefit reminder mensile per utenti TrailShare Pro.
/// Scheduled il 1° di ogni mese alle 10:00 Europe/Rome.
///
/// Per ogni utente Pro (user_profiles.isPro=true) conta le tracce
/// dell'ultimo mese e invia una notifica FCM che ricorda il valore
/// dell'abbonamento. Riduce churn ricordando il ROI mensile.
exports.proBenefitReminderMonthly = onSchedule(
    {
        schedule: "1 of month 10:00",
        timeZone: "Europe/Rome",
        region: "europe-west3",
        timeoutSeconds: 540,
        memory: "256MiB",
    },
    async (_event) => {
        const now = new Date();
        // Range: ultimo mese completo (es. 1 luglio → conta tracce di giugno).
        const start = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        const end = new Date(now.getFullYear(), now.getMonth(), 1);
        const monthName = start.toLocaleDateString('it-IT', {
            month: 'long',
            year: 'numeric',
        });

        try {
            const proSnap = await admin.firestore()
                .collection("user_profiles")
                .where("isPro", "==", true)
                .get();
            logger.info(
                `[proBenefitReminder] ${proSnap.size} utenti Pro da processare`
            );

            for (const doc of proSnap.docs) {
                const uid = doc.id;
                const data = doc.data();
                const tokens = data.fcmTokens;
                if (!tokens || tokens.length === 0) continue;

                try {
                    const tracksSnap = await admin.firestore()
                        .collection("users").doc(uid)
                        .collection("tracks")
                        .where("createdAt", ">=", admin.firestore.Timestamp.fromDate(start))
                        .where("createdAt", "<", admin.firestore.Timestamp.fromDate(end))
                        .get();
                    const count = tracksSnap.size;
                    if (count === 0) continue; // niente da celebrare

                    const message = {
                        notification: {
                            title: `🏔️ Riepilogo ${monthName}`,
                            body: count === 1
                                ? `Hai registrato 1 traccia con TrailShare Pro. Continua così!`
                                : `Hai registrato ${count} tracce con TrailShare Pro. Continua così!`,
                        },
                        data: {
                            type: "pro_monthly_reminder",
                            month: start.toISOString().slice(0, 7),
                            tracks: String(count),
                        },
                        tokens: tokens,
                    };
                    const response = await admin.messaging()
                        .sendEachForMulticast(message);
                    logger.info(
                        `[proBenefitReminder] uid=${uid} tracce=${count} ` +
                        `success=${response.successCount} fail=${response.failureCount}`
                    );

                    // Cleanup token invalidi (stesso pattern delle altre FCM)
                    if (response.failureCount > 0) {
                        const toDelete = [];
                        response.responses.forEach((r, i) => {
                            if (r.error && (
                                r.error.code === "messaging/registration-token-not-registered" ||
                                r.error.code === "messaging/invalid-registration-token"
                            )) {
                                toDelete.push(tokens[i]);
                            }
                        });
                        if (toDelete.length > 0) {
                            await doc.ref.update({
                                fcmTokens: admin.firestore.FieldValue
                                    .arrayRemove(...toDelete),
                            });
                        }
                    }
                } catch (e) {
                    logger.error(`[proBenefitReminder] uid=${uid} error: ${e}`);
                }
            }
        } catch (e) {
            logger.error('[proBenefitReminder] global error', e);
        }
        return null;
    }
);

exports.createMonthlyChallenges = onSchedule("1 of month 00:00", async (event) => {    logger.info("Eseguo la creazione automatica delle sfide mensili...");
    const now = new Date();
    const year = now.getFullYear();
    // Ottieni il nome del mese in italiano
    const monthName = now.toLocaleString('it-IT', { month: 'long' });

    // Calcola l'ultimo giorno del mese corrente
    const endDate = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59);

    // Definiamo dei "modelli" per le nostre sfide ricorrenti
    const challengeTemplates = [
        {
            title: `Sfida di distanza di ${monthName}`,
            description: `Accumula 100 km totali in qualsiasi attività durante il mese di ${monthName}!`,
            activityType: "all",
            type: "DISTANCE_TOTAL",
            goal: 100000, // 100km in metri
        },
        {
            title: `Sfida di dislivello di ${monthName}`,
            description: `Conquista 5000 metri di dislivello positivo durante il mese di ${monthName}.`,
            activityType: "all",
            type: "ELEVATION_TOTAL",
            goal: 5000, // 5000 metri
        },
        {
            title: `Corri 50km a ${monthName}`,
            description: `Mettiti alla prova e corri per 50km questo mese.`,
            activityType: "run", // Specifica per la corsa
            type: "DISTANCE_TOTAL",
            goal: 50000, // 50km in metri
        }
    ];

    // Usiamo un batch per scrivere tutti i documenti in una sola operazione
    const batch = db.batch();

    challengeTemplates.forEach(template => {
        // Creiamo un nuovo riferimento per ogni sfida nella collection 'challenges'
        const challengeRef = db.collection('challenges').doc(); // Firestore genera un ID automatico
        
        const newChallengeData = {
            ...template,
            endDate: admin.firestore.Timestamp.fromDate(endDate),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            participantCount: 0,
            creatorId: "trailshare-admin", // ID fittizio per le sfide automatiche
            creatorUsername: "TrailShare Team",
        };
        
        batch.set(challengeRef, newChallengeData);
    });

    try {
        await batch.commit();
        logger.info(`Create con successo ${challengeTemplates.length} nuove sfide per ${monthName} ${year}.`);
        return null;
    } catch (error) {
        logger.error("Errore durante la creazione automatica delle sfide:", error);
        return null;
    }
});

exports.orsProxy = onRequest({ secrets: [orsApiKey], region: "europe-west3" }, async (req, res) => {
    const allowedOrigins = [
        'https://trailshare.app',         // Marketing site
        'https://app.trailshare.app',     // Dashboard webapp (custom domain)
        'https://trailshare.web.app',     // Dashboard webapp (Firebase default)
        'https://trailshare-5334b.web.app',
        'https://trailshare-5334b.firebaseapp.com',
        'https://localhost',              // Sviluppo Capacitor/Web HTTPS
        'capacitor://localhost'
    ];
    const origin = req.headers.origin || '';
    // Dev: localhost con qualsiasi porta (flutter run -d chrome usa porte
    // diverse a ogni run). In produzione passa solo dalla whitelist.
    const isLocalhost = /^https?:\/\/localhost(:\d+)?$/.test(origin);

    if (allowedOrigins.includes(origin) || isLocalhost) {
        res.set('Access-Control-Allow-Origin', origin);
    } else {
        console.warn(`Origin ${origin} non consentito.`);
    }
    res.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    res.set('Access-Control-Allow-Credentials', 'true');

    if (req.method === 'OPTIONS') {
        res.status(204).send('');
        return;
    }

    const orsPath = req.url.startsWith('/orsProxy') ? req.url.substring('/orsProxy'.length) : req.url;
    const orsUrl = `https://api.openrouteservice.org${orsPath}`;
    logger.info(`Proxying ${req.method} request to ${orsUrl}`);
    
   try {
        const response = await axios({
            method: req.method,
            url: orsUrl,
            data: req.body,
            headers: {
                'Authorization': orsApiKey.value(), // Usa il secret
                'Accept': req.headers.accept || 'application/json, application/geo+json, application/gpx+xml, img/png; charset=utf-8',
                'Content-Type': req.headers['content-type'] || 'application/json'
            },
            timeout: 15000
        });
        res.status(response.status).send(response.data);
    } catch (error) {
        // Logga l'errore completo per il debug
        console.error("Errore nel proxy ORS:", error.response?.status, error.response?.data || error.message);
        res.status(error.response?.status || 500).send(error.response?.data || "Errore interno del proxy.");
    }
});

exports.processGpxUpload = onDocumentCreated("pending_gpx_uploads/{uploadId}", async (event) => {
    const snap = event.data;
    if (!snap) {
        logger.log("Nessun dato per processGpxUpload.");
        return null;
    }

    const data = snap.data();
    const { userId, gpxText, fileName } = data;
    const db = admin.firestore();

    logger.info(`Processo GPX per utente ${userId}, file: ${fileName}`);

    const { default: LineString } = await import("ol/geom/LineString.js");
    const { toLonLat } = await import("ol/proj.js");
    const { GPX } = await import("ol/format/GPX.js");

    try {
        // 1. PARSARE IL GPX (Usando le stesse librerie OL sul server)
        const gpxFormat = new GPX();
        const features = gpxFormat.readFeatures(gpxText, {
            dataProjection: 'EPSG:4326',
            featureProjection: 'EPSG:3857' // Proiezione interna
        });

        const trackFeature = features.find(f => f.getGeometry().getType().includes('LineString'));
        if (!trackFeature) {
            throw new Error("Nessuna traccia valida trovata nel file.");
        }

        const trackName = trackFeature.get('name') || fileName.replace(/\.gpx$/i, '');

        // 2. ESTRARRE LE COORDINATE (Logica corretta)
        const geometry = trackFeature.getGeometry();
        let flatCoordinates = [];
        if (geometry.getType() === 'MultiLineString') {
            flatCoordinates = geometry.getCoordinates().flat();
        } else {
            flatCoordinates = geometry.getCoordinates();
        }
        
        const olPoints = []; // Per stats (EPSG:3857)
        const serializablePoints = []; // Per Firestore (EPSG:4326)

        for (const coord of flatCoordinates) {
            if (coord && typeof coord[0] === 'number' && typeof coord[1] === 'number') {
                olPoints.push(coord);
                const lonLat = toLonLat(coord);
                serializablePoints.push({
                    longitude: lonLat[0], latitude: lonLat[1],
                    altitude: coord.length > 2 ? coord[2] : null, speed: 0 
                });
            }
        }

        if (olPoints.length < 2) { throw new Error("Traccia troppo corta."); }

        // 3. CALCOLARE STATS (usando la funzione calculateTrackStats incollata)
        const { stats } = calculateTrackStats(olPoints, 0, 'trekking', { LineString });
        const startPoint = new GeoPoint(serializablePoints[0].latitude, serializablePoints[0].longitude);

        // 4. CREARE OGGETTO TRACCIA
        const newTrackData = {
            name: trackName,
            points: serializablePoints,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            recordedAt: new Date().toISOString(),
            activityType: 'trekking', difficulty: 'medio',
            distance: stats.distance,
            elevationGain: stats.elevationGain,
            startPoint: startPoint,
            isPublic: false, duration: 0, waypoints: [], heartRateData: heartRateData, photos: [],
            originalOwnerId: userId // Salva l'ID dell'utente che ha caricato
        };

        // 5. SALVARE LA TRACCIA FINALE
        await db.collection("users").doc(userId).collection("tracks").add(newTrackData);
        logger.info(`Traccia ${trackName} processata e salvata per l'utente ${userId}.`);

        // 6. Pulire la coda
        return snap.ref.delete();

    } catch (error) {
        logger.error(`Errore processando GPX ${fileName} per ${userId}:`, error);
        // Sposta in una collezione 'failed_uploads' per debug o cancella
        return snap.ref.delete(); 
    }
});

function calculateTrackStats(points, precalculatedDuration = 0, activityType = 'trekking', olModules) {
    const { LineString } = olModules;
    if (!points || points.length < 2) {
        return {
            stats: { distance: 0, maxAltitude: 0, minAltitude: 0, elevationGain: 0, elevationLoss: 0, duration: 0, movingTime: 0, avgPace: 0, avgMovingPace: 0, maxSpeed: 0, avgSpeed: 0, avgMovingSpeed: 0, vam: 0 },
            elevationChartData: { labels: [], data: [], originalPointMapping: [] },
            speedChartData: { labels: [], data: [] },
            splits: []
        };
    }

    const MOVING_SPEED_THRESHOLD_MPS = 0.22; 
    const MAX_SPEED_FILTER_MPS = { 
        trekking: 5.5, camminata: 5.5, corsa: 12, 'trail-running': 10,
        alpinismo: 4, scialpinismo: 30, bike: 33, mtb: 28, ebike: 28, default: 25
    };
    const maxSpeedForActivity = MAX_SPEED_FILTER_MPS[activityType] || MAX_SPEED_FILTER_MPS.default;

    const smoothAltitudes = (altitudes, windowSize) => {
        if (windowSize <= 1) return altitudes;
        const smoothed = [];
        for (let i = 0; i < altitudes.length; i++) {
            const start = Math.max(0, i - Math.floor(windowSize / 2));
            const end = Math.min(altitudes.length, i + Math.ceil(windowSize / 2));
            const slice = altitudes.slice(start, end);
            const avg = slice.reduce((sum, val) => sum + val, 0) / slice.length;
            smoothed.push(avg);
        }
        return smoothed;
    };

    const rawAltitudes = points.map(p => (p.length > 2 ? p[2] : 0));
    const smoothedAltitudes = smoothAltitudes(rawAltitudes, 5);

    let distance = 0, elevationGain = 0, elevationLoss = 0, maxAltitude = -Infinity, minAltitude = Infinity;
    let maxSpeed = 0, movingTimeSeconds = 0;

    const elevationChartData = { labels: [], data: [], originalPointMapping: [] };
    const speedChartData = { labels: [], data: [] };
    const splits = [];
    
    let splitTargetDistance = 1000;
    let lastSplitTotalDistance = 0; 
    let lastSplitElevationGain = 0;
    let currentSplitDurationSeconds = 0;
    
    let currentDistance = 0;
    const step = Math.max(1, Math.floor(points.length / 100));

    for (let i = 1; i < points.length; i++) {
        
        // ▼▼▼ QUESTA È LA RIGA CORRETTA ▼▼▼
        // Rimuoviamo "ol.geom." perché abbiamo importato LineString direttamente
        const segment = new LineString([points[i - 1], points[i]]);
        // ▲▲▲ --- ▲▲▲

        const segmentDistance = segment.getLength();
        currentDistance += segmentDistance;

        const speedAtPoint = points[i].length > 3 ? points[i][3] : 0;
        let segmentDuration = 0;
        if (speedAtPoint > 0.1) {
            segmentDuration = segmentDistance / speedAtPoint;
        }

        if (speedAtPoint > MOVING_SPEED_THRESHOLD_MPS) {
            movingTimeSeconds += segmentDuration;
            currentSplitDurationSeconds += segmentDuration;
        }

        if (speedAtPoint > maxSpeed && speedAtPoint < maxSpeedForActivity) {
            maxSpeed = speedAtPoint;
        }

        if (rawAltitudes[i] > maxAltitude) maxAltitude = rawAltitudes[i];
        if (rawAltitudes[i] < minAltitude) minAltitude = rawAltitudes[i];

        const diff = smoothedAltitudes[i] - smoothedAltitudes[i-1];
        if (diff > 0.1) elevationGain += diff;
        else if (diff < -0.1) elevationLoss += Math.abs(diff);

        // --- Start Split Logic ---
        if (currentDistance >= splitTargetDistance) {
            const splitDistance = currentDistance - lastSplitTotalDistance;
            let finalSplitDurationSeconds = currentSplitDurationSeconds;
            
            if (finalSplitDurationSeconds < 1 && precalculatedDuration === 0) {
                finalSplitDurationSeconds = splitDistance * 0.9; // Stima 15min/km (0.9s/m)
            }

            splits.push({
                number: splits.length + 1,
                distance: splitDistance,
                duration: finalSplitDurationSeconds * 1000,
                elevationGain: elevationGain - lastSplitElevationGain
            });

            // Reset per il prossimo split
            splitTargetDistance += 1000;
            lastSplitTotalDistance = currentDistance;
            lastSplitElevationGain = elevationGain;
            currentSplitDurationSeconds = 0; 
        }
        // --- End Split Logic ---
        
        if (i % step === 0 || i === points.length - 1) {
            const distanceKmLabel = (currentDistance / 1000).toFixed(1);
            elevationChartData.labels.push(distanceKmLabel);
            elevationChartData.data.push(smoothedAltitudes[i].toFixed(1));
            speedChartData.labels.push(distanceKmLabel);
            speedChartData.data.push((speedAtPoint * 3.6).toFixed(1));
        }
    } // --- END OF FOR LOOP ---
    
    distance = currentDistance;

    // --- Logica per l'ultimo split parziale ---
    const finalSplitDistance = currentDistance - lastSplitTotalDistance;
    if (finalSplitDistance > 1) {
        let finalSplitDurationSeconds = currentSplitDurationSeconds;
        if (finalSplitDurationSeconds < 1 && precalculatedDuration === 0) {
            finalSplitDurationSeconds = finalSplitDistance * 0.9;
        }

        splits.push({
            number: splits.length + 1,
            distance: finalSplitDistance,
            duration: finalSplitDurationSeconds * 1000,
            elevationGain: elevationGain - lastSplitElevationGain
        });
    }

    const distanceKm = distance / 1000;
    const totalDurationSeconds = precalculatedDuration / 1000;
    
    const avgSpeed = (totalDurationSeconds > 0) ? (distanceKm / (totalDurationSeconds / 3600)) : 0;
    const avgPace = (distanceKm > 0 && totalDurationSeconds > 0) ? (totalDurationSeconds / 60) / distanceKm : 0;
    const avgMovingSpeed = (movingTimeSeconds > 0) ? (distanceKm / (movingTimeSeconds / 3600)) : 0;
    const avgMovingPace = (distanceKm > 0 && movingTimeSeconds > 0) ? (movingTimeSeconds / 60) / distanceKm : 0;
    const durationInHours = totalDurationSeconds / 3600;
    const vam = durationInHours > 0 ? elevationGain / durationInHours : 0;

    const stats = {
        distance,
        maxAltitude: maxAltitude === -Infinity ? 0 : maxAltitude,
        minAltitude: minAltitude === Infinity ? 0 : minAltitude,
        elevationGain,
        elevationLoss,
        duration: precalculatedDuration,
        movingTime: movingTimeSeconds * 1000,
        avgPace,
        avgMovingPace,
        maxSpeed: maxSpeed * 3.6,
        avgSpeed,
        avgMovingSpeed,
        vam: vam
    };

    return { stats, elevationChartData, speedChartData, splits };
}

// ===================================================================
// NOTIFICHE GRUPPI
// ===================================================================

// Helper: invia notifica a tutti i membri del gruppo tranne il mittente
async function notifyGroupMembers(groupId, senderId, notification, data) {
    const groupDoc = await db.collection("groups").doc(groupId).get();
    if (!groupDoc.exists) {
        logger.warn(`[Groups] Gruppo ${groupId} non trovato`);
        return;
    }

    const memberIds = groupDoc.data().memberIds || [];
    // Escludi il mittente
    const recipientIds = memberIds.filter(id => id !== senderId);

    if (recipientIds.length === 0) {
        logger.info(`[Groups] Nessun destinatario per gruppo ${groupId}`);
        return;
    }

    // Raccogli tutti i token FCM
    const allTokens = [];
    const tokenOwnerMap = {}; // token -> userId per cleanup

    for (const userId of recipientIds) {
        const profileDoc = await db.collection("user_profiles").doc(userId).get();
        if (profileDoc.exists) {
            const tokens = profileDoc.data().fcmTokens || [];
            for (const token of tokens) {
                allTokens.push(token);
                tokenOwnerMap[token] = userId;
            }
        }
    }

    if (allTokens.length === 0) {
        logger.info(`[Groups] Nessun token FCM per i membri del gruppo ${groupId}`);
        return;
    }

    logger.info(`[Groups] Invio notifica a ${allTokens.length} dispositivi per gruppo ${groupId}`);

    const message = {
        notification: notification,
        data: { ...data, groupId: groupId, type: data.type || "group" },
        tokens: allTokens,
    };

    const response = await admin.messaging().sendEachForMulticast(message);

    // Cleanup token invalidi
    if (response.failureCount > 0) {
        const tokensToRemove = {};
        response.responses.forEach((result, index) => {
            if (result.error && (
                result.error.code === 'messaging/registration-token-not-registered' ||
                result.error.code === 'messaging/invalid-registration-token'
            )) {
                const token = allTokens[index];
                const userId = tokenOwnerMap[token];
                if (!tokensToRemove[userId]) tokensToRemove[userId] = [];
                tokensToRemove[userId].push(token);
            }
        });

        for (const [userId, tokens] of Object.entries(tokensToRemove)) {
            logger.info(`[Groups] Rimozione ${tokens.length} token invalidi per utente ${userId}`);
            await db.collection("user_profiles").doc(userId).update({
                fcmTokens: admin.firestore.FieldValue.arrayRemove(...tokens)
            });
        }
    }
}

// 1. Nuovo messaggio in un gruppo → notifica ai membri
exports.onGroupMessage = onDocumentCreated("groups/{groupId}/messages/{messageId}", async (event) => {
    const groupId = event.params.groupId;
    const data = event.data.data();

    // Non notificare messaggi di sistema (eventi, sfide)
    if (data.type === 'event') return null;

    const senderName = data.senderName || "Qualcuno";
    const text = data.text || "";

    const groupDoc = await db.collection("groups").doc(groupId).get();
    const groupName = groupDoc.exists ? groupDoc.data().name : "Gruppo";

    await notifyGroupMembers(groupId, data.senderId, {
        title: `💬 ${groupName}`,
        body: `${senderName}: ${text.length > 100 ? text.substring(0, 100) + '...' : text}`,
    }, {
        type: "group_message",
        messageId: event.params.messageId,
    });

    return null;
});

// 2. Nuovo evento in un gruppo → notifica ai membri
exports.onGroupEvent = onDocumentCreated("groups/{groupId}/events/{eventId}", async (event) => {
    const groupId = event.params.groupId;
    const data = event.data.data();

    const groupDoc = await db.collection("groups").doc(groupId).get();
    const groupName = groupDoc.exists ? groupDoc.data().name : "Gruppo";

    const date = data.date ? data.date.toDate() : null;
    const dateStr = date ? `${date.getDate()}/${date.getMonth() + 1} alle ${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}` : "";

    await notifyGroupMembers(groupId, data.createdBy, {
        title: `📅 Nuovo evento in ${groupName}`,
        body: `${data.title || "Nuova uscita"}${dateStr ? " - " + dateStr : ""}`,
    }, {
        type: "group_event",
        eventId: event.params.eventId,
    });

    return null;
});

// 3. Nuova sfida in un gruppo → notifica ai membri
exports.onGroupChallenge = onDocumentCreated("groups/{groupId}/challenges/{challengeId}", async (event) => {
    const groupId = event.params.groupId;
    const data = event.data.data();

    const groupDoc = await db.collection("groups").doc(groupId).get();
    const groupName = groupDoc.exists ? groupDoc.data().name : "Gruppo";

    const typeLabels = {
        distance: "distanza",
        elevation: "dislivello",
        tracks: "tracce",
        streak: "costanza",
    };

    await notifyGroupMembers(groupId, data.createdBy, {
        title: `🏆 Nuova sfida in ${groupName}`,
        body: `${data.title || "Nuova sfida"} - Tipo: ${typeLabels[data.type] || data.type}`,
    }, {
        type: "group_challenge",
        challengeId: event.params.challengeId,
    });

    return null;
});

// ===================================================================
// NOTIFICA: Richiesta accesso gruppo → notifica admin
// ===================================================================
exports.onJoinRequest = onDocumentCreated("groups/{groupId}/join_requests/{userId}", async (event) => {
    const groupId = event.params.groupId;
    const requestUserId = event.params.userId;
    const data = event.data.data();

    if (data.status !== 'pending') return null;

    const username = data.username || "Un utente";

    // Carica info gruppo
    const groupDoc = await db.collection("groups").doc(groupId).get();
    if (!groupDoc.exists) return null;
    const groupData = groupDoc.data();
    const groupName = groupData.name || "Gruppo";

    // Trova admin del gruppo
    const membersSnap = await db.collection("groups").doc(groupId)
        .collection("members")
        .where("role", "==", "admin")
        .get();

    const adminIds = membersSnap.docs.map(doc => doc.id);
    if (adminIds.length === 0) return null;

    // Raccogli token admin
    const allTokens = [];
    for (const adminId of adminIds) {
        const profileDoc = await db.collection("user_profiles").doc(adminId).get();
        if (profileDoc.exists) {
            const tokens = profileDoc.data().fcmTokens || [];
            allTokens.push(...tokens);
        }
    }

    if (allTokens.length === 0) return null;

    logger.info(`[JoinRequest] Notifica a ${allTokens.length} dispositivi admin per gruppo ${groupId}`);

    const message = {
        notification: {
            title: `🔔 Richiesta accesso a ${groupName}`,
            body: `${username} vuole unirsi al tuo gruppo`,
        },
        data: { type: "join_request", groupId: groupId, userId: requestUserId },
        tokens: allTokens,
    };

    await admin.messaging().sendEachForMulticast(message);
    return null;
});

// ===================================================================
// NOTIFICA: Approvazione richiesta → notifica al richiedente
// ===================================================================
exports.onJoinRequestApproved = onDocumentUpdated("groups/{groupId}/join_requests/{userId}", async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    // Solo quando status cambia da pending ad approved
    if (before.status === 'pending' && after.status === 'approved') {
        const userId = event.params.userId;
        const groupId = event.params.groupId;

        const groupDoc = await db.collection("groups").doc(groupId).get();
        const groupName = groupDoc.exists ? groupDoc.data().name : "Gruppo";

        const profileDoc = await db.collection("user_profiles").doc(userId).get();
        if (!profileDoc.exists) return null;

        const tokens = profileDoc.data().fcmTokens || [];
        if (tokens.length === 0) return null;

        logger.info(`[JoinApproved] Notifica approvazione a ${userId} per gruppo ${groupId}`);

        const message = {
            notification: {
                title: `✅ Richiesta approvata!`,
                body: `Sei stato accettato nel gruppo "${groupName}"`,
            },
            data: { type: "join_approved", groupId: groupId },
            tokens: tokens,
        };

        await admin.messaging().sendEachForMulticast(message);
    }

    return null;
});

// ===================================================================
// NOTIFICA: Cheers su community_tracks → notifica proprietario
// ===================================================================
exports.onCommunityCheerCreated = onDocumentCreated("community_tracks/{trackId}/cheers/{userId}", async (event) => {
    const trackId = event.params.trackId;
    const cheerUserId = event.params.userId;

    // Incrementa contatore
    const trackRef = db.collection("community_tracks").doc(trackId);
    await trackRef.update({ cheerCount: admin.firestore.FieldValue.increment(1) });

    // Carica traccia
    const trackDoc = await trackRef.get();
    if (!trackDoc.exists) return null;

    const trackData = trackDoc.data();
    const ownerId = trackData.ownerId;

    // No auto-cheer
    if (String(ownerId).trim() === String(cheerUserId).trim()) return null;

    // Token proprietario
    const ownerDoc = await db.collection("user_profiles").doc(ownerId).get();
    if (!ownerDoc.exists) return null;

    const tokens = ownerDoc.data().fcmTokens || [];
    if (tokens.length === 0) return null;

    // Username di chi ha messo cheer
    const cheererDoc = await db.collection("user_profiles").doc(cheerUserId).get();
    const cheererName = cheererDoc.exists ? cheererDoc.data().username : "Un utente";

    logger.info(`[CommunityCheer] Notifica a ${ownerId} da ${cheerUserId}`);

    const message = {
        notification: {
            title: "❤️ Nuovo cheer!",
            body: `${cheererName} ha apprezzato "${trackData.name || 'la tua traccia'}"`,
        },
        data: { type: "community_cheer", trackId: trackId },
        tokens: tokens,
    };

    await admin.messaging().sendEachForMulticast(message);
    return null;
});

// ===================================================================
// NOTIFICA: Decrementa cheers community_tracks
// ===================================================================
exports.onCommunityCheerDeleted = onDocumentDeleted("community_tracks/{trackId}/cheers/{userId}", (event) => {
    const trackId = event.params.trackId;
    return db.collection("community_tracks").doc(trackId).update({
        cheerCount: admin.firestore.FieldValue.increment(-1)
    });
});

// ===================================================================
// NOTIFICA: Amico completa attività → notifica ai follower
// ===================================================================
exports.onCommunityTrackShared = onDocumentCreated("community_tracks/{trackId}", async (event) => {
    const data = event.data.data();
    const ownerId = data.ownerId;
    const trackName = data.name || "una nuova traccia";

    // Carica profilo autore
    const ownerDoc = await db.collection("user_profiles").doc(ownerId).get();
    if (!ownerDoc.exists) return null;

    const ownerData = ownerDoc.data();
    const ownerName = ownerData.username || "Un utente";
    const followers = ownerData.followers || [];

    if (followers.length === 0) return null;

    // Raccogli token di tutti i follower
    const allTokens = [];
    const tokenOwnerMap = {};

    for (const followerId of followers) {
        const profileDoc = await db.collection("user_profiles").doc(followerId).get();
        if (profileDoc.exists) {
            const tokens = profileDoc.data().fcmTokens || [];
            for (const token of tokens) {
                allTokens.push(token);
                tokenOwnerMap[token] = followerId;
            }
        }
    }

    if (allTokens.length === 0) return null;

    logger.info(`[CommunityTrack] Notifica a ${allTokens.length} follower per ${ownerId}`);

    const message = {
        notification: {
            title: `🥾 ${ownerName} ha condiviso un percorso`,
            body: `"${trackName}" - Guarda i dettagli!`,
        },
        data: { type: "community_track", trackId: event.params.trackId },
        tokens: allTokens,
    };

    await admin.messaging().sendEachForMulticast(message);
    return null;
});

// ===================================================================
// BACKFILL: Aggiorna email/displayName/createdAt da Auth a user_profiles
// Esegui UNA VOLTA: https://europe-west3-YOUR_PROJECT.cloudfunctions.net/backfillUserEmails
// ===================================================================
exports.backfillUserEmails = onRequest({ region: "europe-west3" }, async (req, res) => {
  try {
    let nextPageToken;
    let updatedCount = 0;
    let skippedCount = 0;
    const results = [];

    do {
      const listResult = await admin.auth().listUsers(1000, nextPageToken);

      for (const userRecord of listResult.users) {
        try {
          const profileRef = db.collection("user_profiles").doc(userRecord.uid);
          const profileDoc = await profileRef.get();
          const existing = profileDoc.exists ? profileDoc.data() : {};
          const updates = {};

          // FORZA email da Auth (sovrascrive null)
          if (userRecord.email && existing.email !== userRecord.email) {
            updates.email = userRecord.email;
          }

          // Username: usa displayName se manca o è placeholder
          if (userRecord.displayName && (!existing.username || existing.username === "Utente")) {
            updates.username = userRecord.displayName;
          }

          // createdAt da Auth se manca
          if (userRecord.metadata.creationTime && !existing.createdAt) {
            updates.createdAt = admin.firestore.Timestamp.fromDate(
              new Date(userRecord.metadata.creationTime)
            );
          }

          if (Object.keys(updates).length > 0) {
            await profileRef.set(updates, { merge: true });
            updatedCount++;
            results.push("UPDATED: " + userRecord.email + " -> " + JSON.stringify(updates));
          } else {
            skippedCount++;
            results.push("SKIP: " + (userRecord.email || userRecord.uid) + " (already complete)");
          }
        } catch (err) {
          results.push("ERROR: " + userRecord.uid + " - " + err.message);
        }
      }
      nextPageToken = listResult.pageToken;
    } while (nextPageToken);

    res.json({ updated: updatedCount, skipped: skippedCount, details: results });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ═══════════════════════════════════════════════════════════════════
// BACKFILL: Aggiunge startLat/startLng alle community_tracks esistenti
// ═══════════════════════════════════════════════════════════════════
exports.backfillStartCoords = functions.https.onRequest(async (req, res) => {
  try {
    const snapshot = await admin.firestore().collection("published_tracks").get();
    let updated = 0;
    let skipped = 0;
    let errors = 0;

    for (const doc of snapshot.docs) {
      try {
        const data = doc.data();
        
        // Salta se ha già startLat
        if (data.startLat != null && data.startLng != null) {
          skipped++;
          continue;
        }

        const points = data.points;
        if (!points || !Array.isArray(points) || points.length === 0) {
          skipped++;
          continue;
        }

        const first = points[0];
        const lat = first.lat || first.latitude || first.y;
        const lng = first.lng || first.longitude || first.x;

        if (lat != null && lng != null) {
          await doc.ref.update({ startLat: lat, startLng: lng });
          updated++;
        } else {
          skipped++;
        }
      } catch (err) {
        errors++;
      }
    }

    res.json({ total: snapshot.size, updated, skipped, errors });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Fix ownerUsername nelle published_tracks (da email a username)
exports.backfillOwnerUsername = functions.https.onRequest(async (req, res) => {
  try {
    const snapshot = await admin.firestore().collection("published_tracks").get();
    let updated = 0;
    let skipped = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const username = data.ownerUsername || "";

      // Se contiene @ è un'email, va fixato
      if (username.includes("@")) {
        const ownerId = data.originalOwnerId;
        if (!ownerId) { skipped++; continue; }

        try {
          const profileDoc = await admin.firestore().collection("user_profiles").doc(ownerId).get();
          const realUsername = profileDoc.exists ? (profileDoc.data().username || "Utente") : "Utente";
          await doc.ref.update({ ownerUsername: realUsername });
          updated++;
        } catch (err) { skipped++; }
      } else {
        skipped++;
      }
    }

    res.json({ total: snapshot.size, updated, skipped });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});
// ===================================================================

// ===================================================================
// SYNC TRACCE DA GARMIN WATCH
// ===================================================================

function haversineDistance(lat1, lon1, lat2, lon2) {
    const R = 6371000;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
              Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
              Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
}

exports.syncGarminTrack = onRequest(async (req, res) => {
    if (req.method !== 'POST') {
        res.status(405).send('Method not allowed');
        return;
    }

    try {
        const data = req.body;

        if (!data || !data.userId || !data.points || !Array.isArray(data.points)) {
            logger.warn('[GarminSync] Dati invalidi ricevuti');
            res.status(400).json({ error: 'Dati invalidi' });
            return;
        }

        const userId = data.userId;
        const points = data.points;
        const name = data.name || 'Garmin TrailShare';
        const sport = data.sport || 'trekking';
        const durationMs = data.duration || 0;

        logger.info(`[GarminSync] Ricevuta traccia da ${userId}: ${points.length} punti`);

        // Calcola stats dai punti reali
        const heartRateData = {};
        let totalDistance = 0;
        let elevationGain = 0;
        let elevationLoss = 0;
        let maxElevation = -Infinity;
        let minElevation = Infinity;
        let lastLat = null, lastLon = null, lastEle = null;

        const startTime = new Date(Date.now() - durationMs);

        const decodedPoints = points.map((p, i) => {
            const lat = (p.la || 0) / 100000;
            const lon = (p.lo || 0) / 100000;
            const ele = p.al || 0;
            const hr = p.hr || 0;
            const timestamp = new Date(startTime.getTime() + (i * durationMs / Math.max(points.length - 1, 1)));

            // HR
            if (hr > 0) {
                heartRateData[timestamp.toISOString()] = hr;
            }

            // Elevazione
            if (ele > maxElevation) maxElevation = ele;
            if (ele < minElevation) minElevation = ele;

            // Distanza e dislivello
            if (lastLat !== null && lastLon !== null) {
                const dist = haversineDistance(lastLat, lastLon, lat, lon);
                if (dist > 2) {
                    totalDistance += dist;
                }

                if (lastEle !== null) {
                    const eleDiff = ele - lastEle;
                    if (eleDiff > 3) {
                        elevationGain += eleDiff;
                        lastEle = ele;
                    } else if (eleDiff < -3) {
                        elevationLoss += Math.abs(eleDiff);
                        lastEle = ele;
                    }
                } else {
                    lastEle = ele;
                }
            } else {
                lastEle = ele;
            }

            lastLat = lat;
            lastLon = lon;

            return {
                lat: lat,
                lng: lon,
                ele: ele,
                time: timestamp.toISOString(),
                speed: null,
                accuracy: null,
                heading: null,
            };
        });

        if (maxElevation === -Infinity) maxElevation = 0;
        if (minElevation === Infinity) minElevation = 0;

        const durationSecs = durationMs / 1000;
        const distanceKm = totalDistance / 1000;
        const avgSpeed = durationSecs > 0 ? (distanceKm / (durationSecs / 3600)) : 0;

        logger.info(`[GarminSync] Stats: ${totalDistance.toFixed(0)}m, D+${elevationGain.toFixed(0)}m, ${durationSecs}s, HR: ${Object.keys(heartRateData).length} campioni`);

        const trackData = {
            name: name,
            description: 'Registrata con TrailShare su Garmin',
            activityType: sport,
            points: decodedPoints,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            recordedAt: startTime,
            userId: userId,
            isPublic: false,
            isPlanned: false,
            source: 'garmin',
            heartRateData: heartRateData,
            stats: {
                distance: totalDistance,
                elevationGain: elevationGain,
                elevationLoss: elevationLoss,
                maxElevation: maxElevation,
                minElevation: minElevation,
                duration: durationMs,
                movingTime: durationMs,
                currentSpeed: 0,
                avgSpeed: avgSpeed,
                maxSpeed: 0,
            },
            photos: [],
        };

        const docRef = await db.collection('users').doc(userId).collection('tracks').add(trackData);

        logger.info(`[GarminSync] Traccia salvata: ${docRef.id}`);

        res.status(200).json({
            success: true,
            trackId: docRef.id,
            points: decodedPoints.length,
            distance: totalDistance,
            elevationGain: elevationGain,
            hrSamples: Object.keys(heartRateData).length,
        });

    } catch (error) {
        logger.error('[GarminSync] Errore:', error);
        res.status(500).json({ error: 'Errore interno' });
    }
});

// ===================================================================
// MIGRAZIONE GEOHASH per public_trails
// ===================================================================

function encodeGeohash(lat, lng, precision = 7) {
  const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
  let minLat = -90, maxLat = 90;
  let minLng = -180, maxLng = 180;
  let hash = '';
  let bit = 0;
  let ch = 0;
  let isLon = true;

  while (hash.length < precision) {
    if (isLon) {
      const mid = (minLng + maxLng) / 2;
      if (lng >= mid) { ch |= 1 << (4 - bit); minLng = mid; } else { maxLng = mid; }
    } else {
      const mid = (minLat + maxLat) / 2;
      if (lat >= mid) { ch |= 1 << (4 - bit); minLat = mid; } else { maxLat = mid; }
    }
    isLon = !isLon;
    if (bit < 4) { bit++; } else { hash += base32[ch]; bit = 0; ch = 0; }
  }
  return hash;
}

// ═══════════════════════════════════════════════════════════════════
// Epic 3.4 — Heatmap trail popolari
// ═══════════════════════════════════════════════════════════════════
// Aggrega le `published_tracks` per cella geohash precision 4
// (~20km × 20km, ~50-100 celle per coprire l'Italia) e scrive in
// `heatmap_cells/{geohash}` { count, geohash, lat, lng, updatedAt }.
//
// Strategia:
// - Schedulato la domenica alle 04:00 (dopo i leaderboards che girano alle 02:00).
// - Endpoint HTTP per bootstrap manuale (la prima volta, o dopo bulk
//   ingest tracce).
// - lat/lng di ogni cella = media dei punti di partenza delle tracce
//   che cadono dentro (centroide pesato dall'attività reale, non centro
//   geometrico della cella).
// - Pulizia: celle che non hanno più tracce vengono cancellate per
//   evitare residui zombie.
async function _aggregateHeatmap() {
  const snap = await db.collection("published_tracks").get();
  const buckets = new Map();
  for (const doc of snap.docs) {
    const d = doc.data();
    const lat = (typeof d.startLat === 'number') ? d.startLat : null;
    const lng = (typeof d.startLng === 'number') ? d.startLng : null;
    if (lat == null || lng == null) continue;
    const cell = encodeGeohash(lat, lng, 4);
    const b = buckets.get(cell) || { count: 0, sumLat: 0, sumLng: 0 };
    b.count += 1;
    b.sumLat += lat;
    b.sumLng += lng;
    buckets.set(cell, b);
  }

  const seen = new Set();
  const entries = [...buckets.entries()];
  for (let i = 0; i < entries.length; i += 400) {
    const slice = entries.slice(i, i + 400);
    const batch = db.batch();
    for (const [hash, b] of slice) {
      const ref = db.collection("heatmap_cells").doc(hash);
      batch.set(ref, {
        geohash: hash,
        count: b.count,
        lat: b.sumLat / b.count,
        lng: b.sumLng / b.count,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      seen.add(hash);
    }
    await batch.commit();
  }

  // Cella esistente non più rappresentata = traccia cancellata → delete.
  const existing = await db.collection("heatmap_cells").get();
  const stale = existing.docs.filter((d) => !seen.has(d.id));
  for (let i = 0; i < stale.length; i += 400) {
    const slice = stale.slice(i, i + 400);
    const batch = db.batch();
    slice.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }

  logger.info(
    `[heatmap] aggregated ${entries.length} cells from ${snap.size} tracks, ` +
    `deleted ${stale.length} stale`
  );
  return { cells: entries.length, tracks: snap.size, stale: stale.length };
}

exports.aggregateHeatmapWeekly = onSchedule(
  {
    schedule: "every sunday 04:00",
    timeZone: "Europe/Rome",
    region: "europe-west3",
    timeoutSeconds: 540,
    memory: "512MiB",
  },
  async (_event) => {
    try {
      await _aggregateHeatmap();
    } catch (e) {
      logger.error('[heatmap] weekly aggregation failed', e);
    }
    return null;
  }
);

exports.aggregateHeatmapNow = onRequest(
  { region: "europe-west3", cors: true, timeoutSeconds: 540, memory: "512MiB" },
  async (req, res) => {
    try {
      const r = await _aggregateHeatmap();
      res.json({ ok: true, ...r });
    } catch (e) {
      logger.error('[heatmap] manual aggregation failed', e);
      res.status(500).json({ ok: false, error: e.message });
    }
  }
);

exports.migrateGeoHash = onRequest({ timeoutSeconds: 540, memory: '1GiB' }, async (req, res) => {
  const batch_size = 500;
  let updated = 0;
  let skipped = 0;
  let failed = 0;
  let lastDoc = null;

  while (true) {
    let query = db.collection('public_trails')
      .limit(batch_size);

    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();
    if (snapshot.empty) break;

    const batch = db.batch();
    let batchCount = 0;

    for (const doc of snapshot.docs) {
      lastDoc = doc;
      const data = doc.data();

      // Skip se ha già geoHash E startPoint
      if (data.geoHash && typeof data.geoHash === 'string' && data.geoHash.length >= 4 && data.startPoint) {
        skipped++;
        continue;
      }

      // Trova coordinate
      let lat = null, lng = null;

      // 1. Da startPoint
      if (data.startPoint) {
        if (data.startPoint.latitude !== undefined) {
          lat = data.startPoint.latitude;
          lng = data.startPoint.longitude;
        } else if (data.startPoint.lat !== undefined) {
          lat = data.startPoint.lat;
          lng = data.startPoint.lng || data.startPoint.lon;
        }
      }

      // 2. Da geometry
      if (lat === null && data.geometry) {
        try {
          let coords = null;
          if (typeof data.geometry === 'string') {
            const geo = JSON.parse(data.geometry);
            coords = geo.coordinates;
          } else if (data.geometry.coordinatesJson) {
            coords = JSON.parse(data.geometry.coordinatesJson);
          }

          if (coords && coords.length > 0) {
            const first = coords[0];
            if (Array.isArray(first) && first.length >= 2) {
              lng = first[0]; // GeoJSON: [lon, lat]
              lat = first[1];
            }
          }
        } catch (e) {
          // Skip
        }
      }

      if (lat === null || lng === null || lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        failed++;
        continue;
      }

      const geoHash = encodeGeohash(lat, lng, 7);
      const updateData = { geoHash };

      // Aggiungi startPoint se mancante
      if (!data.startPoint) {
        updateData.startPoint = new GeoPoint(lat, lng);
      }

      batch.update(doc.ref, updateData);
      batchCount++;
    }

    if (batchCount > 0) {
      await batch.commit();
      updated += batchCount;
    }

    logger.info(`Progresso: ${updated} aggiornati, ${skipped} già ok, ${failed} falliti`);

    if (snapshot.docs.length < batch_size) break;
  }

  const result = { updated, skipped, failed, total: updated + skipped + failed };
  logger.info('Migrazione completata:', result);
  res.json(result);
});



// ===================================================================
// 6.B2 — RECEIPT VALIDATION (App Store / Play Billing)
// ===================================================================
//
// Riceve un receipt dal client (dopo un acquisto/restore) e lo valida
// chiamando l'API ufficiale Apple verifyReceipt.
//
// Architettura:
// 1. Client (Flutter) chiama questa funzione tramite HTTPS Callable
//    passando il receipt base64 ottenuto da:
//      purchase.verificationData.serverVerificationData
// 2. La funzione tenta production endpoint, fallback su sandbox se
//    Apple risponde status=21007 (receipt è di sandbox)
// 3. Parsiamo `latest_receipt_info`, prendiamo il transaction più
//    recente per i nostri productID Pro, e ritorniamo lo stato
// 4. (6.B3 hook) Aggiorniamo anche `users/{uid}.proStatus` su Firestore
//    così sopravvive a reinstall e ferma la pirateria client-side
//
// Pre-requisiti:
// - Firebase secret APP_STORE_SHARED_SECRET configurato:
//     `firebase functions:secrets:set APP_STORE_SHARED_SECRET`
//   Il valore si ottiene da App Store Connect:
//     My Apps > TrailShare > App Information > App-Specific Shared Secret
//   (oppure Users and Access > Integrations > In-App Purchase)

const fs = require('fs');
const path = require('path');
const {
  SignedDataVerifier,
  Environment,
} = require('@apple/app-store-server-library');

const PRO_PRODUCT_IDS = [
  'trailshare_pro_monthly',
  'trailshare_pro_yearly',
];

const APP_BUNDLE_ID = 'com.trailshare.app';

// Shared secret legacy (verifyReceipt) — non più usato dopo migrazione
// a StoreKit 2/JWS. Mantenuto come secret optional per non rompere il
// deploy esistente; verrà rimosso quando aggiungeremo i webhook V2.
const appStoreSharedSecret = defineSecret('APP_STORE_SHARED_SECRET');

// Apple root certificates (DER), caricati una volta all'avvio del
// container. Servono al SignedDataVerifier per validare la catena di
// certificati nell'header x5c del JWS.
let _appleRootCertsCache;
function getAppleRootCerts() {
  if (_appleRootCertsCache) return _appleRootCertsCache;
  const dir = path.join(__dirname, 'apple-roots');
  const files = [
    'AppleIncRootCertificate.cer',
    'AppleRootCA-G2.cer',
    'AppleRootCA-G3.cer',
  ];
  _appleRootCertsCache = files.map((f) => fs.readFileSync(path.join(dir, f)));
  return _appleRootCertsCache;
}

// Crea un verifier per uno specifico ambiente. Cached per evitare il
// parse ripetuto dei certificati ad ogni invocazione.
const _verifierCache = {};
function getVerifier(environment) {
  if (_verifierCache[environment]) return _verifierCache[environment];
  _verifierCache[environment] = new SignedDataVerifier(
    getAppleRootCerts(),
    true, // enableOnlineChecks (CRL/OCSP)
    environment,
    APP_BUNDLE_ID,
    undefined // appAppleId — serve solo per webhook V2
  );
  return _verifierCache[environment];
}

exports.validateAppleReceipt = onCall(
  { secrets: [appStoreSharedSecret] },
  async (request) => {
    if (!request.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Authentication required'
      );
    }
    const uid = request.auth.uid;
    const { receipt, productId } = request.data || {};

    if (!receipt || typeof receipt !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Missing or invalid receipt data'
      );
    }

    logger.info(
      `[validateAppleReceipt] uid=${uid} productId=${productId} ` +
        `receiptLen=${receipt.length}`
    );

    // Il receipt da StoreKit 2 è un JWS (header.payload.signature).
    // Tentiamo di decodificarlo prima come Production, fallback Sandbox
    // se Apple respinge per ambiente sbagliato.
    let decoded;
    let environmentUsed;
    try {
      const verifier = getVerifier(Environment.PRODUCTION);
      decoded = await verifier.verifyAndDecodeTransaction(receipt);
      environmentUsed = Environment.PRODUCTION;
    } catch (prodErr) {
      logger.info(
        `[validateAppleReceipt] prod verify failed (${prodErr.message}), ` +
          `trying sandbox`
      );
      try {
        const verifier = getVerifier(Environment.SANDBOX);
        decoded = await verifier.verifyAndDecodeTransaction(receipt);
        environmentUsed = Environment.SANDBOX;
      } catch (sandboxErr) {
        logger.error(
          `[validateAppleReceipt] both prod+sandbox verify failed: ` +
            `${sandboxErr.message}`
        );
        await updateProStatus(uid, {
          isPro: false,
          productId: null,
          expiresAtMs: null,
          lastError: `jws_verify_failed: ${sandboxErr.message}`,
        });
        return {
          valid: false,
          productId: null,
          expiresAtMs: null,
          jwsError: sandboxErr.message,
        };
      }
    }

    // decoded contiene il payload JWSTransactionDecodedPayload con tutti
    // i campi della transazione. Vedi:
    // https://developer.apple.com/documentation/appstoreserverapi/jwstransactiondecodedpayload
    const decodedProductId = decoded.productId;
    const expiresAtMs = decoded.expiresDate; // già in ms
    const revocationDateMs = decoded.revocationDate || null;
    const isInTrial = decoded.offerType === 1; // 1 = introductory offer
    const originalTransactionId = decoded.originalTransactionId;

    if (!PRO_PRODUCT_IDS.includes(decodedProductId)) {
      logger.warn(
        `[validateAppleReceipt] productId=${decodedProductId} ` +
          `not in PRO list`
      );
      await updateProStatus(uid, {
        isPro: false,
        productId: decodedProductId,
        expiresAtMs: null,
      });
      return { valid: false, productId: decodedProductId, expiresAtMs: null };
    }

    const now = Date.now();
    const isActive =
      expiresAtMs > now && revocationDateMs == null;

    logger.info(
      `[validateAppleReceipt] result uid=${uid} env=${environmentUsed} ` +
        `valid=${isActive} productId=${decodedProductId} ` +
        `expires=${new Date(expiresAtMs).toISOString()} trial=${isInTrial}`
    );

    await updateProStatus(uid, {
      isPro: isActive,
      productId: decodedProductId,
      expiresAtMs,
      isInTrial,
      originalTransactionId,
      revocationDateMs,
      environment: environmentUsed,
      lastError: null, // pulisce eventuali errori da validazioni precedenti
    });

    return {
      valid: isActive,
      productId: decodedProductId,
      expiresAtMs,
      isInTrial,
      originalTransactionId,
    };
  }
);

/// Aggiorna `users/{uid}.proStatus` (subdocument) con lo stato Pro
/// validato server-side. Usato sia da validateAppleReceipt che, in
/// futuro, dai webhook App Store Server Notifications.
async function updateProStatus(uid, data) {
  try {
    await db.collection('users').doc(uid).set(
      {
        proStatus: {
          ...data,
          source: 'apple_iap',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      },
      { merge: true }
    );

    // Sprint B (2026-05-10): mirror del flag isPro su user_profiles così
    // altri utenti possono leggerlo (es. cap dei gruppi derivati dal Pro
    // status dell'OWNER del gruppo, non del current user).
    // user_profiles è già public-read; isPro non è in whitelist update
    // client-side → solo admin SDK lo scrive (qui).
    const isProActive =
      data.isPro === true &&
      (data.expiresAtMs == null || data.expiresAtMs > Date.now());
    try {
      await db.collection('user_profiles').doc(uid).set(
        {
          isPro: isProActive,
          proExpiresAtMs: data.expiresAtMs ?? null,
          proUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    } catch (mirrorErr) {
      logger.error(
        `[updateProStatus] user_profiles mirror failed for uid=${uid}`,
        mirrorErr
      );
    }
  } catch (e) {
    logger.error(`[updateProStatus] failed for uid=${uid}`, e);
  }
}

/// Backfill one-shot: legge `users/{uid}.proStatus` per ogni utente e
/// rimirror su `user_profiles/{uid}.isPro`. Da chiamare una volta dopo
/// il deploy del mirror (utenti già Pro non sono coperti automaticamente).
/// Protetto admin via custom claim email.
const ADMIN_BACKFILL_SECRET = defineSecret('ADMIN_BACKFILL_SECRET');

exports.backfillIsProMirror = onRequest(
  { region: 'europe-west3', cors: true, secrets: [ADMIN_BACKFILL_SECRET] },
  async (req, res) => {
    // Auth basic via header X-Admin-Secret (uso one-shot, niente claims).
    const secret = req.header('X-Admin-Secret');
    if (secret !== ADMIN_BACKFILL_SECRET.value()) {
      logger.warn('[backfillIsProMirror] unauthorized');
      res.status(401).send('unauthorized');
      return;
    }

    let scanned = 0;
    let mirrored = 0;
    let skipped = 0;
    const errors = [];

    try {
      const snap = await db.collection('users').get();
      for (const doc of snap.docs) {
        scanned += 1;
        const proStatus = doc.data()?.proStatus;
        if (!proStatus) {
          skipped += 1;
          continue;
        }
        const isProActive =
          proStatus.isPro === true &&
          (proStatus.expiresAtMs == null ||
            proStatus.expiresAtMs > Date.now());
        try {
          await db.collection('user_profiles').doc(doc.id).set(
            {
              isPro: isProActive,
              proExpiresAtMs: proStatus.expiresAtMs ?? null,
              proUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            { merge: true }
          );
          mirrored += 1;
        } catch (e) {
          errors.push({ uid: doc.id, msg: e.message });
        }
      }
      res.json({ ok: true, scanned, mirrored, skipped, errors });
    } catch (e) {
      logger.error('[backfillIsProMirror] failed', e);
      res.status(500).json({ ok: false, error: e.message });
    }
  }
);

// ===================================================================
// 6.6 — TRAIL CONDITIONS AI SUMMARY
// ===================================================================
// Killer feature Pro: riassume in linguaggio naturale le segnalazioni
// recenti della community per un sentiero (fango, neve, ponti chiusi,
// ecc.) usando Claude Haiku. Cache 24h su Firestore per minimizzare
// costi e latenza — un summary serve in media a 50-100 utenti prima
// di cambiare stato.
//
// Storage:
//   /trail_conditions_summaries/{trailId} = {
//     summary: string,
//     reportsCount: int,
//     hasCriticalReports: bool,
//     newestReportAt: timestamp,
//     generatedAt: timestamp,
//     model: string,
//     locale: string,
//   }

const anthropicApiKey = defineSecret('ANTHROPIC_API_KEY');

/// Costruisce il prompt per Claude a partire dai report community.
function buildTrailConditionsPrompt(reports, trailName, locale) {
  const lang = locale === 'en' ? 'English' : 'Italian';
  const lines = reports.map((r, idx) => {
    const ageHours = Math.round((Date.now() - r.reportedAt.toMillis()) / 36e5);
    const ageStr = ageHours < 24
      ? `${ageHours}h ago`
      : `${Math.round(ageHours / 24)} days ago`;
    const note = (r.note || '').trim().replace(/\s+/g, ' ').slice(0, 200);
    return `${idx + 1}. [${r.status}] (${ageStr}) ${note || '(no note)'}`;
  }).join('\n');

  return `You are summarizing recent trail-condition reports for hikers
in ${lang}, written by users of an outdoor app. Produce a SHORT,
factual summary (max 3 sentences, ~50 words total) that helps a
hiker decide whether to go today.

Trail: "${trailName}"
Reports (most recent first):
${lines}

Rules:
- Mention specific recent issues (mud on the climb, broken bridge,
  snow above 1500m, etc.) only if they appear in multiple reports
  or in a recent critical one.
- If most recent reports say "good", say the trail is in good
  conditions.
- DO NOT invent details. DO NOT moralize. DO NOT mention safety
  generic disclaimers. DO NOT say "based on reports".
- DO NOT use markdown, lists, or emojis. Plain text in ${lang}, single
  paragraph.
- If reports are conflicting, lean on the most recent ones.

Summary:`;
}

/// Chiama Claude Haiku via API HTTP. Ritorna il testo del summary.
async function callClaude(prompt, apiKey) {
  const res = await axios.post(
    'https://api.anthropic.com/v1/messages',
    {
      model: 'claude-haiku-4-5',
      max_tokens: 200,
      messages: [{ role: 'user', content: prompt }],
    },
    {
      headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      timeout: 15000,
    }
  );
  const content = res.data?.content?.[0]?.text;
  if (!content || typeof content !== 'string') {
    throw new Error('Claude returned empty content');
  }
  return content.trim();
}

exports.summarizeTrailConditions = onCall(
  {
    secrets: [anthropicApiKey],
    region: 'europe-west3',
    timeoutSeconds: 30,
  },
  async (request) => {
    const trailId = request.data?.trailId;
    const trailName = request.data?.trailName || 'Sentiero';
    const locale = request.data?.locale || 'it';
    const forceRefresh = request.data?.forceRefresh === true;

    if (!trailId || typeof trailId !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'trailId is required'
      );
    }
    if (!request.auth?.uid) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Auth required'
      );
    }

    const summaryRef = db
      .collection('trail_conditions_summaries')
      .doc(trailId);

    // 1. Cache check — 24h TTL
    if (!forceRefresh) {
      const cached = await summaryRef.get();
      if (cached.exists) {
        const data = cached.data();
        const ageMs = Date.now() - (data.generatedAt?.toMillis() || 0);
        const isFresh = ageMs < 24 * 3600 * 1000;
        if (isFresh && data.summary) {
          return {
            summary: data.summary,
            reportsCount: data.reportsCount || 0,
            hasCriticalReports: data.hasCriticalReports || false,
            newestReportAt: data.newestReportAt?.toMillis() || null,
            generatedAt: data.generatedAt?.toMillis() || null,
            cached: true,
          };
        }
      }
    }

    // 2. Fetch report recenti (60 giorni, max 20)
    const cutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - 60 * 24 * 3600 * 1000
    );
    const reportsSnap = await db
      .collection('trail_conditions')
      .doc(trailId)
      .collection('reports')
      .where('reportedAt', '>=', cutoff)
      .orderBy('reportedAt', 'desc')
      .limit(20)
      .get();

    const reports = reportsSnap.docs.map((d) => ({
      status: d.data().status || 'good',
      note: d.data().note || '',
      reportedAt: d.data().reportedAt,
    }));

    if (reports.length === 0) {
      return {
        summary: null,
        reportsCount: 0,
        hasCriticalReports: false,
        newestReportAt: null,
        generatedAt: null,
        cached: false,
      };
    }

    // 3. Genera summary via Claude
    const prompt = buildTrailConditionsPrompt(reports, trailName, locale);
    let summary;
    try {
      summary = await callClaude(prompt, anthropicApiKey.value());
    } catch (e) {
      logger.error('[summarizeTrailConditions] Claude error', e?.message || e);
      throw new functions.https.HttpsError(
        'internal',
        'Failed to generate summary'
      );
    }

    const hasCritical = reports.some((r) =>
      ['closed', 'rockfall', 'ice'].includes(r.status)
    );

    const payload = {
      summary,
      reportsCount: reports.length,
      hasCriticalReports: hasCritical,
      newestReportAt: reports[0].reportedAt,
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
      model: 'claude-haiku-4-5',
      locale,
    };

    await summaryRef.set(payload, { merge: true });

    return {
      summary,
      reportsCount: reports.length,
      hasCriticalReports: hasCritical,
      newestReportAt: reports[0].reportedAt.toMillis(),
      generatedAt: Date.now(),
      cached: false,
    };
  }
);

/// Trigger automatico: quando arriva un nuovo report, invalida la
/// cache (così la prossima call rigenera fresh con il nuovo dato).
/// Più economico di rigenerare subito — la maggior parte degli utenti
/// non legge il summary istantaneamente dopo un report.
exports.invalidateTrailConditionsSummaryOnNewReport = onDocumentCreated(
  {
    document: 'trail_conditions/{trailId}/reports/{reportId}',
    region: 'europe-west3',
  },
  async (event) => {
    const { trailId } = event.params;
    try {
      await db
        .collection('trail_conditions_summaries')
        .doc(trailId)
        .delete();
      logger.info(
        `[invalidateTrailSummary] cleared cache for trail ${trailId}`
      );
    } catch (e) {
      logger.warn(`[invalidateTrailSummary] failed: ${e?.message}`);
    }
  }
);

// ===================================================================
// STRAVA — OAuth + upload end-of-session
// ===================================================================
//
// Setup richiesto:
// 1) Crea app su https://www.strava.com/settings/api
//    - Authorization Callback Domain: cloudfunctions.net
//    - Website: https://trailshare.app (o quello che hai)
// 2) Salva i secret:
//    firebase functions:secrets:set STRAVA_CLIENT_ID
//    firebase functions:secrets:set STRAVA_CLIENT_SECRET
// 3) In functions/ esegui: npm install form-data
// 4) Deploy: firebase deploy --only functions:stravaCallback,functions:stravaUploadActivity,functions:stravaDisconnect
//
// Schema Firestore:
//   users/{uid}/integrations/strava: {
//     athleteId, accessToken, refreshToken, expiresAt (sec since epoch),
//     scope, autoUploadEnabled (bool), connectedAt
//   }
//
// Track doc additions (scritti dalla upload function):
//   stravaActivityId, stravaUploadId, stravaUploadStatus, stravaUploadedAt, stravaError

const STRAVA_OAUTH_TOKEN_URL = 'https://www.strava.com/oauth/token';
const STRAVA_UPLOADS_URL = 'https://www.strava.com/api/v3/uploads';

const STRAVA_ACTIVITY_TYPE_MAP = {
  trekking: 'Hike',
  hiking: 'Hike',
  walking: 'Walk',
  trailRunning: 'TrailRun',
  running: 'Run',
  cycling: 'Ride',
  gravelBiking: 'GravelRide',
  mountainBiking: 'MountainBikeRide',
  eMountainBike: 'EMountainBikeRide',
  eBike: 'EBikeRide',
  alpineSkiing: 'AlpineSki',
  skiTouring: 'BackcountrySki',
  nordicSkiing: 'NordicSki',
  snowshoeing: 'Snowshoe',
};

function escapeXmlStrava(text) {
  return String(text || '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&apos;');
}

function buildGpxFromTrack(track) {
  const points = Array.isArray(track.points) ? track.points : [];
  const lines = [];
  lines.push('<?xml version="1.0" encoding="UTF-8"?>');
  lines.push('<gpx version="1.1" creator="TrailShare" xmlns="http://www.topografix.com/GPX/1/1">');
  lines.push('  <metadata>');
  lines.push(`    <name>${escapeXmlStrava(track.name)}</name>`);
  const createdAt = track.createdAt && track.createdAt.toDate
    ? track.createdAt.toDate()
    : (track.createdAt ? new Date(track.createdAt) : new Date());
  lines.push(`    <time>${createdAt.toISOString()}</time>`);
  lines.push('  </metadata>');
  lines.push('  <trk>');
  lines.push(`    <name>${escapeXmlStrava(track.name)}</name>`);
  if (track.description) {
    lines.push(`    <desc>${escapeXmlStrava(track.description)}</desc>`);
  }
  lines.push('    <trkseg>');
  for (const p of points) {
    const lat = p.lat ?? p.latitude;
    const lng = p.lng ?? p.longitude ?? p.lon;
    if (lat == null || lng == null) continue;
    const ele = p.ele ?? p.elevation ?? p.altitude;
    const time = p.time ?? p.timestamp;
    let line = `      <trkpt lat="${lat}" lon="${lng}">`;
    if (ele != null) line += `<ele>${Number(ele).toFixed(1)}</ele>`;
    if (time) {
      const t = typeof time === 'string' ? time : new Date(time).toISOString();
      line += `<time>${t}</time>`;
    }
    line += '</trkpt>';
    lines.push(line);
  }
  lines.push('    </trkseg>');
  lines.push('  </trk>');
  lines.push('</gpx>');
  return lines.join('\n');
}

async function refreshStravaToken(uid, integration) {
  const nowSec = Math.floor(Date.now() / 1000);
  // Refresh se mancano meno di 60s alla scadenza
  if (integration.expiresAt && integration.expiresAt - nowSec > 60) {
    return integration;
  }
  const resp = await axios.post(STRAVA_OAUTH_TOKEN_URL, {
    client_id: stravaClientId.value(),
    client_secret: stravaClientSecret.value(),
    grant_type: 'refresh_token',
    refresh_token: integration.refreshToken,
  });
  const data = resp.data;
  const updated = {
    ...integration,
    accessToken: data.access_token,
    refreshToken: data.refresh_token,
    expiresAt: data.expires_at,
  };
  await db.collection('users').doc(uid).collection('integrations').doc('strava').set({
    accessToken: data.access_token,
    refreshToken: data.refresh_token,
    expiresAt: data.expires_at,
  }, { merge: true });
  return updated;
}

// OAuth callback: riceve ?code&state=<uid>, scambia con tokens, redirect deep link
exports.stravaCallback = onRequest(
  { secrets: [stravaClientId, stravaClientSecret], cors: false },
  async (req, res) => {
    const { code, state, error: stravaError, scope } = req.query;
    const redirectOk = 'trailshare://strava/connected';
    const redirectErr = (msg) => `trailshare://strava/error?msg=${encodeURIComponent(msg || 'unknown')}`;

    if (stravaError) {
      logger.warn(`[strava] OAuth denied: ${stravaError}`);
      return res.redirect(302, redirectErr(stravaError));
    }
    if (!code || !state) {
      return res.redirect(302, redirectErr('missing_params'));
    }
    const uid = String(state);

    try {
      const tokenResp = await axios.post(STRAVA_OAUTH_TOKEN_URL, {
        client_id: stravaClientId.value(),
        client_secret: stravaClientSecret.value(),
        code,
        grant_type: 'authorization_code',
      });
      const t = tokenResp.data;
      if (!t.access_token || !t.refresh_token) {
        return res.redirect(302, redirectErr('no_tokens'));
      }

      await db.collection('users').doc(uid).collection('integrations').doc('strava').set({
        athleteId: t.athlete?.id || null,
        athleteFirstname: t.athlete?.firstname || null,
        athleteLastname: t.athlete?.lastname || null,
        accessToken: t.access_token,
        refreshToken: t.refresh_token,
        expiresAt: t.expires_at,
        scope: String(scope || ''),
        autoUploadEnabled: true,
        connectedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });

      logger.info(`[strava] connected uid=${uid} athlete=${t.athlete?.id}`);
      return res.redirect(302, redirectOk);
    } catch (e) {
      logger.error('[strava] callback error', e?.response?.data || e?.message);
      return res.redirect(302, redirectErr('exchange_failed'));
    }
  }
);

// Disconnessione: revoca tokens lato Strava + elimina doc
exports.stravaDisconnect = onCall(
  { secrets: [stravaClientId, stravaClientSecret] },
  async (req) => {
    if (!req.auth?.uid) throw new functions.https.HttpsError('unauthenticated', 'auth required');
    const uid = req.auth.uid;
    const docRef = db.collection('users').doc(uid).collection('integrations').doc('strava');
    const snap = await docRef.get();
    if (!snap.exists) return { ok: true, alreadyDisconnected: true };
    const integration = snap.data();
    try {
      await axios.post('https://www.strava.com/oauth/deauthorize', null, {
        params: { access_token: integration.accessToken },
      });
    } catch (e) {
      logger.warn(`[strava] deauthorize failed (procedo lo stesso): ${e?.message}`);
    }
    await docRef.delete();
    return { ok: true };
  }
);

// Upload attività: legge track, genera GPX, refresh token, upload + polling, scrive stato
exports.stravaUploadActivity = onCall(
  { secrets: [stravaClientId, stravaClientSecret], timeoutSeconds: 120 },
  async (req) => {
    if (!req.auth?.uid) throw new functions.https.HttpsError('unauthenticated', 'auth required');
    const uid = req.auth.uid;
    const trackId = req.data?.trackId;
    if (!trackId) throw new functions.https.HttpsError('invalid-argument', 'trackId required');

    const integSnap = await db.collection('users').doc(uid).collection('integrations').doc('strava').get();
    if (!integSnap.exists) throw new functions.https.HttpsError('failed-precondition', 'strava_not_connected');

    // Le tracce sono nested in users/{uid}/tracks/{trackId}
    const trackRef = db.collection('users').doc(uid).collection('tracks').doc(trackId);
    const trackSnap = await trackRef.get();
    if (!trackSnap.exists) throw new functions.https.HttpsError('not-found', 'track_not_found');
    const track = trackSnap.data();
    if (track.stravaActivityId) {
      return { ok: true, alreadyUploaded: true, stravaActivityId: track.stravaActivityId };
    }

    let integration = integSnap.data();
    integration = await refreshStravaToken(uid, integration);

    const gpx = buildGpxFromTrack({ ...track, name: track.name || 'TrailShare activity' });
    const FormData = require('form-data');
    const form = new FormData();
    form.append('file', Buffer.from(gpx, 'utf8'), {
      filename: `${trackId}.gpx`,
      contentType: 'application/gpx+xml',
    });
    form.append('data_type', 'gpx');
    form.append('name', track.name || 'TrailShare activity');
    if (track.description) form.append('description', track.description);
    form.append('external_id', `trailshare-${trackId}`);
    const stravaActivityType = STRAVA_ACTIVITY_TYPE_MAP[track.activityType];
    if (stravaActivityType) form.append('activity_type', stravaActivityType);

    let uploadId;
    try {
      const up = await axios.post(STRAVA_UPLOADS_URL, form, {
        headers: { ...form.getHeaders(), Authorization: `Bearer ${integration.accessToken}` },
        maxContentLength: Infinity, maxBodyLength: Infinity,
      });
      uploadId = up.data?.id_str || up.data?.id;
      logger.info(`[strava] upload accepted track=${trackId} uploadId=${uploadId}`);
    } catch (e) {
      const errMsg = e?.response?.data?.message || e?.message || 'upload_failed';
      const errors = e?.response?.data?.errors;
      logger.error(`[strava] upload failed: ${errMsg}`, errors);
      await trackRef.update({
        stravaUploadStatus: 'error',
        stravaError: errMsg,
        stravaUploadedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      // Duplicato (già caricato manualmente / esiste activity con stesso external_id)
      const dupId = errors?.find?.((er) => er?.code === 'duplicate')?.resource;
      if (dupId) {
        return { ok: false, error: 'duplicate' };
      }
      throw new functions.https.HttpsError('internal', errMsg);
    }

    await trackRef.update({
      stravaUploadId: String(uploadId),
      stravaUploadStatus: 'processing',
      stravaUploadedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Polling: Strava processa il GPX in qualche secondo
    let activityId = null;
    let lastStatus = 'processing';
    let lastError = null;
    for (let attempt = 0; attempt < 10; attempt++) {
      await new Promise((r) => setTimeout(r, 1500));
      try {
        const st = await axios.get(`${STRAVA_UPLOADS_URL}/${uploadId}`, {
          headers: { Authorization: `Bearer ${integration.accessToken}` },
        });
        const d = st.data;
        if (d.activity_id) { activityId = d.activity_id; break; }
        if (d.error) { lastError = d.error; break; }
        lastStatus = d.status || lastStatus;
      } catch (e) {
        logger.warn(`[strava] poll attempt ${attempt} failed: ${e?.message}`);
      }
    }

    if (activityId) {
      await trackRef.update({
        stravaActivityId: String(activityId),
        stravaUploadStatus: 'done',
      });
      return { ok: true, stravaActivityId: String(activityId) };
    }
    await trackRef.update({
      stravaUploadStatus: lastError ? 'error' : 'pending',
      stravaError: lastError || null,
    });
    return { ok: false, status: lastError ? 'error' : 'pending', error: lastError, lastStatus };
  }
);

// ===================================================================
// STRAVA — Import attività da Strava (read direction)
// ===================================================================
//
// Setup webhook (one-shot):
// 1) firebase functions:secrets:set STRAVA_WEBHOOK_VERIFY_TOKEN  (qualsiasi stringa random)
// 2) Deploy: firebase deploy --only functions:stravaWebhook,functions:stravaSubscribeWebhook
// 3) Crea la subscription chiamando stravaSubscribeWebhook (callable) come admin
//    OPPURE manualmente con curl:
//    curl -X POST https://www.strava.com/api/v3/push_subscriptions \
//      -F client_id=$CLIENT_ID -F client_secret=$CLIENT_SECRET \
//      -F callback_url=https://europe-west3-trailshare-5334b.cloudfunctions.net/stravaWebhook \
//      -F verify_token=<STRAVA_WEBHOOK_VERIFY_TOKEN>
//
// Strava → callback_url GET con hub.challenge → rispondiamo echo
// Strava → callback_url POST con event {object_type, aspect_type, owner_id, object_id}
//
// Import skippato per:
// - activity con external_id che inizia per "trailshare-" (è una nostra)
// - activityType non outdoor (Yoga, WeightTraining, ecc.)
// - utente senza importFromStravaEnabled=true
// - distance < 100m

const STRAVA_API_BASE = 'https://www.strava.com/api/v3';

const STRAVA_TO_TRAILSHARE_ACTIVITY = {
  Hike: 'trekking',
  Walk: 'walking',
  Run: 'running',
  TrailRun: 'trailRunning',
  Ride: 'cycling',
  GravelRide: 'gravelBiking',
  MountainBikeRide: 'mountainBiking',
  EBikeRide: 'eBike',
  EMountainBikeRide: 'eMountainBike',
  AlpineSki: 'alpineSkiing',
  BackcountrySki: 'skiTouring',
  NordicSki: 'nordicSkiing',
  Snowshoe: 'snowshoeing',
};

async function findUserByStravaAthleteId(athleteId) {
  const snap = await db.collectionGroup('integrations')
    .where('athleteId', '==', Number(athleteId))
    .limit(1)
    .get();
  if (snap.empty) return null;
  const doc = snap.docs[0];
  // path = users/{uid}/integrations/strava
  const uid = doc.ref.parent.parent.id;
  return { uid, integration: doc.data() };
}

async function importStravaActivity(uid, activityId, integration) {
  // 1) Metadata
  const meta = await axios.get(`${STRAVA_API_BASE}/activities/${activityId}`, {
    headers: { Authorization: `Bearer ${integration.accessToken}` },
  });
  const a = meta.data;

  // Skip nostre upload
  if (a.external_id && String(a.external_id).startsWith('trailshare-')) {
    logger.info(`[stravaImport] skip ours: activity=${activityId}`);
    return { skipped: 'own_upload' };
  }
  // Skip non outdoor
  const activityType = STRAVA_TO_TRAILSHARE_ACTIVITY[a.type] || STRAVA_TO_TRAILSHARE_ACTIVITY[a.sport_type];
  if (!activityType) {
    logger.info(`[stravaImport] skip type ${a.type}/${a.sport_type}: activity=${activityId}`);
    return { skipped: 'unsupported_type' };
  }
  // Skip troppo corte
  if (!a.distance || a.distance < 100) {
    return { skipped: 'too_short' };
  }
  // Skip già importate
  const existing = await db.collection('users').doc(uid).collection('tracks')
    .where('stravaSourceActivityId', '==', String(activityId)).limit(1).get();
  if (!existing.empty) {
    logger.info(`[stravaImport] already imported: activity=${activityId}`);
    return { skipped: 'already_imported' };
  }

  // 2) Streams
  const streamKeys = 'latlng,altitude,time,heartrate,velocity_smooth';
  const streamsResp = await axios.get(
    `${STRAVA_API_BASE}/activities/${activityId}/streams?keys=${streamKeys}&key_by_type=true`,
    { headers: { Authorization: `Bearer ${integration.accessToken}` } },
  );
  const s = streamsResp.data || {};
  const latlng = s.latlng?.data || [];
  const altitude = s.altitude?.data || [];
  const time = s.time?.data || [];
  const hr = s.heartrate?.data || [];
  const speed = s.velocity_smooth?.data || [];

  if (latlng.length === 0) {
    logger.warn(`[stravaImport] no GPS data: activity=${activityId}`);
    return { skipped: 'no_gps' };
  }

  // 3) Costruisci points (formato compatibile con TrackPoint.fromMap)
  // HR samples: chiavi come millisecondsSinceEpoch.toString() (formato app)
  const startMs = new Date(a.start_date).getTime();
  const points = [];
  const heartRateData = {};
  for (let i = 0; i < latlng.length; i++) {
    const tsMs = startMs + (time[i] || 0) * 1000;
    points.push({
      lat: latlng[i][0],
      lng: latlng[i][1],
      ele: altitude[i] != null ? altitude[i] : null,
      time: new Date(tsMs).toISOString(),
      speed: speed[i] != null ? speed[i] : null,
    });
    if (hr[i] != null && hr[i] > 30 && hr[i] < 250) {
      heartRateData[String(tsMs)] = Math.round(hr[i]);
    }
  }

  // 4) Track doc — IMPORTANTE: stats sono campi FLAT al top level
  //    (durata in secondi, non microseconds). Vedi tracks_repository._trackFromFirestore.
  const track = {
    userId: uid,
    name: a.name || 'Attività Strava',
    description: a.description || null,
    activityType: activityType,
    points: points,
    createdAt: admin.firestore.Timestamp.fromDate(new Date(a.start_date)),
    isPublic: false,
    isPlanned: false,
    photos: [],
    groupIds: [],
    // Stats flat
    distance: Number(a.distance) || 0,
    elevationGain: Number(a.total_elevation_gain) || 0,
    elevationLoss: 0,
    maxElevation: a.elev_high || 0,
    minElevation: a.elev_low || 0,
    duration: a.elapsed_time || 0,
    movingTime: a.moving_time || a.elapsed_time || 0,
    avgSpeed: a.average_speed ? a.average_speed * 3.6 : 0,
    maxSpeed: a.max_speed ? a.max_speed * 3.6 : 0,
    // Health
    heartRateData: Object.keys(heartRateData).length > 0 ? heartRateData : null,
    healthCalories: a.calories || null,
    // Strava metadata
    importedFromStrava: true,
    stravaSourceActivityId: String(activityId),
    stravaActivityId: String(activityId),
    stravaUploadStatus: 'done',
  };

  const ref = await db.collection('users').doc(uid).collection('tracks').add(track);
  logger.info(`[stravaImport] imported activity=${activityId} → track=${ref.id} uid=${uid}`);
  return { imported: true, trackId: ref.id };
}

// Webhook callback Strava
exports.stravaWebhook = onRequest(
  {
    secrets: [stravaClientId, stravaClientSecret, stravaWebhookVerifyToken],
    cors: false,
    timeoutSeconds: 60,
  },
  async (req, res) => {
    // Subscription validation
    if (req.method === 'GET') {
      const mode = req.query['hub.mode'];
      const token = req.query['hub.verify_token'];
      const challenge = req.query['hub.challenge'];
      if (mode === 'subscribe' && token === stravaWebhookVerifyToken.value()) {
        logger.info('[stravaWebhook] subscription validated');
        return res.status(200).json({ 'hub.challenge': challenge });
      }
      logger.warn(`[stravaWebhook] invalid validation token=${token}`);
      return res.status(403).send('Forbidden');
    }

    // Event POST
    if (req.method !== 'POST') return res.status(405).send('Method not allowed');

    const event = req.body || {};
    const { object_type, aspect_type, owner_id, object_id } = event;
    logger.info(`[stravaWebhook] event ${object_type}/${aspect_type} owner=${owner_id} obj=${object_id}`);

    // Rispondi subito a Strava (deve avere 200 entro 2s o riprova)
    res.status(200).send('OK');

    if (object_type !== 'activity' || aspect_type !== 'create') return;

    try {
      const found = await findUserByStravaAthleteId(owner_id);
      if (!found) {
        logger.info(`[stravaWebhook] no user for athleteId=${owner_id}`);
        return;
      }
      if (found.integration.importFromStravaEnabled !== true) {
        logger.info(`[stravaWebhook] import disabled uid=${found.uid}`);
        return;
      }
      const integration = await refreshStravaToken(found.uid, found.integration);
      await importStravaActivity(found.uid, object_id, integration);
    } catch (e) {
      logger.error(`[stravaWebhook] import error obj=${object_id}: ${e?.message}`, e?.response?.data);
    }
  }
);

// Setup webhook subscription (one-shot, super-admin only)
exports.stravaSubscribeWebhook = onCall(
  { secrets: [stravaClientId, stravaClientSecret, stravaWebhookVerifyToken] },
  async (req) => {
    if (req.auth?.token?.email !== 'todde.massimiliano@gmail.com') {
      throw new functions.https.HttpsError('permission-denied', 'admin only');
    }
    const callbackUrl = `https://europe-west3-trailshare-5334b.cloudfunctions.net/stravaWebhook`;
    // Check existing
    try {
      const list = await axios.get('https://www.strava.com/api/v3/push_subscriptions', {
        params: {
          client_id: stravaClientId.value(),
          client_secret: stravaClientSecret.value(),
        },
      });
      if (Array.isArray(list.data) && list.data.length > 0) {
        return { ok: true, alreadyExists: true, subscriptions: list.data };
      }
    } catch (e) {
      logger.warn(`[stravaSub] list error: ${e?.message}`);
    }
    // Create
    try {
      const r = await axios.post('https://www.strava.com/api/v3/push_subscriptions', null, {
        params: {
          client_id: stravaClientId.value(),
          client_secret: stravaClientSecret.value(),
          callback_url: callbackUrl,
          verify_token: stravaWebhookVerifyToken.value(),
        },
      });
      return { ok: true, subscriptionId: r.data?.id };
    } catch (e) {
      const msg = e?.response?.data || e?.message;
      logger.error('[stravaSub] create error', msg);
      throw new functions.https.HttpsError('internal', JSON.stringify(msg));
    }
  }
);

// ===================================================================
// SPAZI PRO — Notifiche FCM ai follower per nuovi business posts
// ===================================================================
//
// Quando un owner business pubblica un aggiornamento, tutti i follower
// ricevono una notifica push. Pattern allineato a `notifyGroupMembers`:
// legge fcmTokens da user_profiles, sendEachForMulticast, cleanup
// token invalidi.

exports.onBusinessPostCreated = onDocumentCreated(
  'businesses/{businessId}/posts/{postId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const post = snap.data();
    const { businessId, postId } = event.params;

    // Carica metadata business per nome + verifica owner
    const bizDoc = await db.collection('businesses').doc(businessId).get();
    if (!bizDoc.exists) {
      logger.warn(`[BusinessPost] Business ${businessId} non trovato`);
      return;
    }
    const business = bizDoc.data();
    const businessName = business.name || 'Spazio Pro';

    // Recupera follower
    const followersSnap = await db
      .collection('businesses')
      .doc(businessId)
      .collection('followers')
      .get();

    if (followersSnap.empty) {
      logger.info(`[BusinessPost] Nessun follower per business ${businessId}`);
      return;
    }

    // Aggrega FCM tokens da user_profiles
    const allTokens = [];
    const tokenOwnerMap = {};
    const followerIds = followersSnap.docs.map((d) => d.id);
    const authorId = post.authorId;

    for (const userId of followerIds) {
      // Skip l'autore stesso (evita auto-notifica)
      if (userId === authorId) continue;
      try {
        const profileDoc = await db
          .collection('user_profiles')
          .doc(userId)
          .get();
        if (!profileDoc.exists) continue;
        const tokens = profileDoc.data().fcmTokens || [];
        for (const token of tokens) {
          allTokens.push(token);
          tokenOwnerMap[token] = userId;
        }
      } catch (e) {
        logger.warn(
          `[BusinessPost] Errore fetch profile ${userId}: ${e?.message}`
        );
      }
    }

    if (allTokens.length === 0) {
      logger.info(
        `[BusinessPost] Nessun token FCM tra i ${followerIds.length} follower`
      );
      return;
    }

    // Body: primi 100 caratteri del post
    const text = (post.text || '').toString();
    const body = text.length > 100 ? `${text.substring(0, 97)}…` : text;

    logger.info(
      `[BusinessPost] Invio a ${allTokens.length} dispositivi (business=${businessId}, post=${postId})`
    );

    const message = {
      notification: { title: businessName, body },
      data: {
        type: 'business_post',
        businessId,
        postId,
      },
      tokens: allTokens,
    };

    let response;
    try {
      response = await admin.messaging().sendEachForMulticast(message);
      logger.info(
        `[BusinessPost] FCM result: ${response.successCount} ok, ${response.failureCount} fail`
      );
    } catch (e) {
      logger.error(`[BusinessPost] FCM error: ${e?.message}`);
      return;
    }

    // Cleanup token invalidi
    if (response.failureCount > 0) {
      const tokensToRemove = {};
      response.responses.forEach((result, index) => {
        if (
          result.error &&
          (result.error.code === 'messaging/registration-token-not-registered' ||
            result.error.code === 'messaging/invalid-registration-token')
        ) {
          const token = allTokens[index];
          const userId = tokenOwnerMap[token];
          if (!tokensToRemove[userId]) tokensToRemove[userId] = [];
          tokensToRemove[userId].push(token);
        }
      });
      for (const [userId, tokens] of Object.entries(tokensToRemove)) {
        try {
          await db.collection('user_profiles').doc(userId).update({
            fcmTokens: admin.firestore.FieldValue.arrayRemove(...tokens),
          });
          logger.info(
            `[BusinessPost] Rimossi ${tokens.length} token invalidi per ${userId}`
          );
        } catch (e) {
          logger.warn(
            `[BusinessPost] Errore cleanup tokens ${userId}: ${e?.message}`
          );
        }
      }
    }
  }
);

// Retry automatico per upload in stato `pending`: ogni 10 minuti cerca le
// tracce con stravaUploadStatus=pending da almeno 5 min e ripolla
// /uploads/{stravaUploadId}. Se Strava ha completato, scrive activityId.
// Se è in error, segna error. Dopo MAX_AGE_MIN abbandona (segna error).
exports.stravaReconcilePending = onSchedule(
  {
    schedule: 'every 10 minutes',
    region: 'europe-west3',
    secrets: [stravaClientId, stravaClientSecret],
    timeoutSeconds: 300,
  },
  async () => {
    const FIVE_MIN_AGO = admin.firestore.Timestamp.fromMillis(Date.now() - 5 * 60 * 1000);
    const MAX_AGE_MIN = 60; // dopo 1h marchia error
    const MAX_AGE_AGO = admin.firestore.Timestamp.fromMillis(Date.now() - MAX_AGE_MIN * 60 * 1000);

    const snap = await db.collectionGroup('tracks')
      .where('stravaUploadStatus', '==', 'pending')
      .where('stravaUploadedAt', '<', FIVE_MIN_AGO)
      .limit(50)
      .get();

    if (snap.empty) {
      logger.info('[stravaReconcile] no pending uploads');
      return;
    }
    logger.info(`[stravaReconcile] ${snap.size} pending upload(s) da ricontrollare`);

    for (const doc of snap.docs) {
      const track = doc.data();
      const uploadId = track.stravaUploadId;
      const uploadedAt = track.stravaUploadedAt;
      // Ricava uid dal path users/{uid}/tracks/{tid}
      const pathParts = doc.ref.path.split('/');
      const uid = pathParts[1];

      if (!uploadId || !uid) {
        await doc.ref.update({ stravaUploadStatus: 'error', stravaError: 'missing_upload_id' });
        continue;
      }

      // Troppo vecchio: arrendi
      if (uploadedAt && uploadedAt.toMillis && uploadedAt.toMillis() < MAX_AGE_AGO.toMillis()) {
        await doc.ref.update({
          stravaUploadStatus: 'error',
          stravaError: 'timeout_after_1h',
        });
        logger.warn(`[stravaReconcile] timeout track=${doc.id} uid=${uid}`);
        continue;
      }

      try {
        const integSnap = await db.collection('users').doc(uid)
          .collection('integrations').doc('strava').get();
        if (!integSnap.exists) {
          await doc.ref.update({ stravaUploadStatus: 'error', stravaError: 'strava_disconnected' });
          continue;
        }
        const integration = await refreshStravaToken(uid, integSnap.data());

        const r = await axios.get(`${STRAVA_UPLOADS_URL}/${uploadId}`, {
          headers: { Authorization: `Bearer ${integration.accessToken}` },
        });
        const d = r.data;
        if (d.activity_id) {
          await doc.ref.update({
            stravaActivityId: String(d.activity_id),
            stravaUploadStatus: 'done',
          });
          logger.info(`[stravaReconcile] done track=${doc.id} activity=${d.activity_id}`);
        } else if (d.error) {
          await doc.ref.update({ stravaUploadStatus: 'error', stravaError: d.error });
          logger.warn(`[stravaReconcile] error track=${doc.id} err=${d.error}`);
        }
        // altrimenti rimane pending: rilancerà al prossimo tick
      } catch (e) {
        logger.error(`[stravaReconcile] track=${doc.id} ${e?.message}`);
      }
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────
// Strava manual force-sync (utente clicca "Sincronizza ora" in Settings)
// Pulla le ultime N attività e importa quelle non ancora presenti.
// Aggira il webhook quando è rotto o l'utente vuole un sync immediato.
// ─────────────────────────────────────────────────────────────────────────
exports.stravaImportRecent = onCall(
  {
    region: 'europe-west3',
    secrets: [stravaClientId, stravaClientSecret],
    timeoutSeconds: 120,
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new Error('unauthenticated');
    const limit = Math.min(Number(request.data?.limit) || 10, 30);

    const integDoc = await db
      .collection('users').doc(uid)
      .collection('integrations').doc('strava')
      .get();
    if (!integDoc.exists) throw new Error('strava_not_connected');
    let integration = integDoc.data();
    if (!integration?.accessToken) throw new Error('strava_not_connected');
    if (integration.importFromStravaEnabled !== true) {
      throw new Error('import_disabled');
    }

    // Refresh token se necessario
    integration = await refreshStravaToken(uid, integration);

    const resp = await axios.get(
      `${STRAVA_API_BASE}/athlete/activities?per_page=${limit}`,
      { headers: { Authorization: `Bearer ${integration.accessToken}` } },
    );
    const activities = resp.data || [];
    logger.info(`[stravaImportRecent] uid=${uid} fetched=${activities.length}`);

    const results = { imported: [], skipped: [], errors: [] };
    for (const a of activities) {
      try {
        const r = await importStravaActivity(uid, a.id, integration);
        if (r?.skipped) {
          results.skipped.push({ id: a.id, name: a.name, reason: r.skipped });
        } else {
          results.imported.push({ id: a.id, name: a.name });
        }
      } catch (e) {
        results.errors.push({ id: a.id, error: e?.message || String(e) });
        logger.error(`[stravaImportRecent] activity=${a.id} ${e?.message}`);
      }
    }
    return results;
  },
);

// ═══════════════════════════════════════════════════════════════════════════
// MIGRAZIONE: split public_trails → public_trails (index) + public_trail_geometries
// ═══════════════════════════════════════════════════════════════════════════
//
// Motivazione: i doc legacy in `public_trails/` includono `geometry.coordinatesJson`
// fino a ~800 KB. Con 4400+ trail la Discover map scarica decine di MB e
// blocca il client. Spostiamo la geometria pesante in `public_trail_geometries/{id}`
// e calcoliamo un `simplifiedPoints` inline (max 30 pt) per il render mappa.
//
// Idempotente: skippa trail già migrati (presenza di `simplifiedPoints` o
// assenza di `geometry.coordinatesJson`). Chiamabile più volte.

// Admin emails per i Cloud Functions privilegiati (es. moderazione,
// stats, manutenzione). Manteniamo 'info@bluspose.it' come legacy
// finché il founder non migra l'auth Firebase al nuovo dominio:
// rimuoverlo prima della migrazione lo escluderebbe dalle azioni
// admin server-side.
const ADMIN_EMAILS = [
  'admin@trailshare.app',
  'info@trailshare.app',
  'todde.massimiliano@gmail.com',
  'info@bluspose.it', // legacy — rimuovere dopo migrazione auth founder
];

function _sampleEvenly(coords, maxPoints) {
  // Output: lista di {lng, lat} — Firestore non accetta array di array.
  if (!Array.isArray(coords) || coords.length === 0) return [];
  const toPt = (c) => ({ lng: Number(c[0]), lat: Number(c[1]) });
  if (coords.length <= maxPoints) return coords.map(toPt);
  const stride = coords.length / maxPoints;
  const out = [];
  for (let i = 0; i < maxPoints; i++) {
    const idx = Math.min(coords.length - 1, Math.floor(i * stride));
    out.push(toPt(coords[idx]));
  }
  const last = toPt(coords[coords.length - 1]);
  const tail = out[out.length - 1];
  if (!tail || tail.lng !== last.lng || tail.lat !== last.lat) out.push(last);
  return out;
}

exports.migratePublicTrailsSplit = onCall(
  { region: 'europe-west3', timeoutSeconds: 540, memory: '1GiB' },
  async (request) => {
    const email = request.auth?.token?.email;
    if (!email || !ADMIN_EMAILS.includes(email)) {
      throw new Error('unauthorized: admin only');
    }

    const batchSize = Number(request.data?.batchSize) || 200;
    const dryRun = request.data?.dryRun === true;
    const startAfter = request.data?.startAfter || null;

    let scanned = 0;
    let migrated = 0;
    let alreadyMigrated = 0;
    let noGeometry = 0;
    let errors = 0;
    let lastDocId = null;
    const errorSamples = [];

    let q = db.collection('public_trails').orderBy(FieldPath.documentId()).limit(batchSize);
    if (startAfter) {
      q = q.startAfter(startAfter);
    }

    const snap = await q.get();
    logger.info(`[migratePublicTrailsSplit] processing ${snap.size} docs (startAfter=${startAfter}, dryRun=${dryRun})`);

    for (const doc of snap.docs) {
      scanned += 1;
      lastDocId = doc.id;
      try {
        const data = doc.data();
        const hasSimplified = Array.isArray(data.simplifiedPoints) && data.simplifiedPoints.length > 0;
        const geom = data.geometry;
        const inlineJson = geom && typeof geom === 'object' ? geom.coordinatesJson : null;

        if (hasSimplified && !inlineJson) {
          alreadyMigrated += 1;
          continue;
        }
        if (!inlineJson || typeof inlineJson !== 'string') {
          noGeometry += 1;
          continue;
        }

        let coords;
        try {
          coords = JSON.parse(inlineJson);
        } catch (e) {
          errors += 1;
          if (errorSamples.length < 5) errorSamples.push({ id: doc.id, err: 'parse:' + e.message });
          continue;
        }
        if (!Array.isArray(coords) || coords.length < 2) {
          noGeometry += 1;
          continue;
        }

        const simplified = _sampleEvenly(coords, 30);

        if (dryRun) {
          migrated += 1;
          continue;
        }

        // 1) Scrivi geometria completa in collection separata
        await db.collection('public_trail_geometries').doc(doc.id).set({
          coordinatesJson: inlineJson,
          pointsCount: coords.length,
          osmId: data.osmId || null,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        // 2) Aggiorna doc index: aggiungi simplifiedPoints, rimuovi coordinatesJson
        await doc.ref.update({
          simplifiedPoints: simplified,
          'geometry.coordinatesJson': admin.firestore.FieldValue.delete(),
          migratedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        migrated += 1;
      } catch (e) {
        errors += 1;
        if (errorSamples.length < 5) errorSamples.push({ id: doc.id, err: e.message });
        logger.error(`[migratePublicTrailsSplit] doc=${doc.id} ${e.message}`);
      }
    }

    const hasMore = snap.size === batchSize;
    logger.info(`[migratePublicTrailsSplit] done batch: scanned=${scanned} migrated=${migrated} already=${alreadyMigrated} noGeom=${noGeometry} errors=${errors} hasMore=${hasMore}`);

    return {
      scanned,
      migrated,
      alreadyMigrated,
      noGeometry,
      errors,
      errorSamples,
      lastDocId,
      hasMore,
      nextStartAfter: hasMore ? lastDocId : null,
    };
  }
);

// ============================================================
// ADMIN CUSTOM CLAIMS (single source of truth platform admin)
// ============================================================
//
// Sostituisce il pattern hardcoded `ADMIN_EMAILS` + lista
// duplicata `isAdminByEmail` in firestore.rules.
//
// Pattern:
// 1. setAdminClaim(targetUid, isAdmin) — callable solo da admin
//    già esistenti. Setta il claim `admin: true|false` sull'utente
//    Auth target.
// 2. Le firestore.rules controllano `request.auth.token.admin == true`
//    via funzione `isAdminByClaim()`. Niente più liste duplicate.
// 3. Il client deve fare `await user.getIdToken(true)` dopo che gli
//    viene assegnato il claim (force refresh), altrimenti aspetta
//    fino a 1 ora.
//
// Bootstrap: la prima volta usa `bootstrapAdminClaims` che setta
// il claim sui 4 admin storici basandosi sulla loro email. Solo il
// super-admin (uid hardcoded) puo' chiamare questa funzione, e
// solo una volta — poi setAdminClaim per i futuri admin.

const SUPER_ADMIN_UID = 'g4uPvD3VQcMiYb4dDTWs7kJgm4u1';

/// Verifica se il caller corrente e' admin platform.
/// Compatibile con la transizione: accetta sia custom claim
/// (preferito) sia email in ADMIN_EMAILS (legacy fallback).
async function _isCallerAdmin(auth) {
  if (!auth) return false;
  if (auth.token.admin === true) return true;
  if (auth.token.email && ADMIN_EMAILS.includes(auth.token.email)) return true;
  return false;
}

exports.setAdminClaim = onCall(async (request) => {
  const callerAuth = request.auth;
  if (!(await _isCallerAdmin(callerAuth))) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Solo admin esistenti possono assegnare il ruolo admin.'
    );
  }

  const targetUid = request.data.uid;
  const isAdmin = request.data.isAdmin === true;
  if (!targetUid || typeof targetUid !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'uid mancante');
  }

  // Setta il claim. Preserva eventuali altri custom claims.
  const userRecord = await admin.auth().getUser(targetUid);
  const existingClaims = userRecord.customClaims || {};
  const newClaims = { ...existingClaims, admin: isAdmin };
  await admin.auth().setCustomUserClaims(targetUid, newClaims);

  // Mirror su user_profiles.admin per compatibilita' con il check
  // legacy lato app (AdminRepository.isCurrentUserAdmin che legge
  // user_profiles/{uid}.admin). Cosi' anche senza force-refresh
  // del token il flag e' visibile subito.
  await admin.firestore().collection('user_profiles').doc(targetUid).set(
    { admin: isAdmin },
    { merge: true },
  );

  logger.info(
    `[setAdminClaim] callerUid=${callerAuth.uid} targetUid=${targetUid} isAdmin=${isAdmin}`
  );

  return {
    success: true,
    uid: targetUid,
    isAdmin,
    note: 'Il client target deve chiamare user.getIdToken(true) per refresh immediato del claim. Altrimenti il claim si propaga entro 1 ora.',
  };
});

/// Bootstrap one-shot: setta `admin: true` come custom claim ai 4
/// admin storici (definiti in ADMIN_EMAILS). Idempotente — eseguibile
/// piu' volte senza danni.
///
/// Chiamabile SOLO dal super-admin (uid hardcoded). Usato una volta
/// al deploy iniziale del sistema claims, poi non piu' necessario.
exports.bootstrapAdminClaims = onCall(async (request) => {
  if (!request.auth || request.auth.uid !== SUPER_ADMIN_UID) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Solo il super-admin puo eseguire bootstrap.'
    );
  }

  const results = [];
  for (const email of ADMIN_EMAILS) {
    try {
      const userRecord = await admin.auth().getUserByEmail(email);
      const existingClaims = userRecord.customClaims || {};
      const newClaims = { ...existingClaims, admin: true };
      await admin.auth().setCustomUserClaims(userRecord.uid, newClaims);
      await admin.firestore().collection('user_profiles').doc(userRecord.uid).set(
        { admin: true },
        { merge: true },
      );
      results.push({ email, uid: userRecord.uid, ok: true });
      logger.info(`[bootstrapAdminClaims] ok: ${email} -> ${userRecord.uid}`);
    } catch (e) {
      results.push({ email, ok: false, error: e.message });
      logger.warn(`[bootstrapAdminClaims] skip ${email}: ${e.message}`);
    }
  }

  return { results, totalProcessed: results.length };
});

// ===================================================================
// SELF-CLAIM FLOW (Epic 7.H1)
// ===================================================================
// Quando il team TrailShare inserisce uno Spazio Pro per conto di un
// rifugista/noleggiatore che non e' ancora autonomo, la scheda nasce
// con `pendingSelfManagement: true` e ownerId = uid del team. Il
// gestore reale ricevera' via WhatsApp un link `claim-self/{id}?t={token}`
// che gli permette di subentrare come owner.
//
// Sicurezza:
// - `generateSelfClaimToken`: callable, solo admin platform. Genera
//   token random 32 char (crypto.randomBytes hex). Invalida i token
//   precedenti per lo stesso business. TTL 30 giorni.
// - `acceptSelfClaim`: callable, qualunque utente loggato. Valida
//   token + scadenza + match businessId. Trasferisce ownership
//   atomicamente in una transaction Firestore. Token consumato.
// - Token vivono in `business_self_claims/{token}` con rule
//   `allow read,write: if false;` → niente accesso client.

const crypto = require('crypto');

const SELF_CLAIM_TTL_DAYS = 30;

exports.generateSelfClaimToken = onCall(async (request) => {
  if (!(await _isCallerAdmin(request.auth))) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Solo admin platform puo generare token self-claim.'
    );
  }
  const businessId = request.data && request.data.businessId;
  if (!businessId || typeof businessId !== 'string') {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'businessId mancante.'
    );
  }

  // Verifica che il business esista
  const businessRef = db.collection('businesses').doc(businessId);
  const businessSnap = await businessRef.get();
  if (!businessSnap.exists) {
    throw new functions.https.HttpsError(
      'not-found',
      `Business ${businessId} non trovato.`
    );
  }

  // Invalida i token precedenti per lo stesso business (puo' essere
  // che l'admin rigeneri il link perche' il rifugista l'ha perso).
  const oldTokens = await db.collection('business_self_claims')
    .where('businessId', '==', businessId)
    .get();
  const batch = db.batch();
  oldTokens.forEach((doc) => batch.delete(doc.ref));

  // Nuovo token
  const token = crypto.randomBytes(16).toString('hex'); // 32 char
  const expiresAt = admin.firestore.Timestamp.fromMillis(
    Date.now() + SELF_CLAIM_TTL_DAYS * 24 * 60 * 60 * 1000
  );
  const tokenRef = db.collection('business_self_claims').doc(token);
  batch.set(tokenRef, {
    businessId,
    expiresAt,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    createdByUid: request.auth.uid,
  });

  // Setta pendingSelfManagement=true sul business doc (idempotente)
  batch.update(businessRef, {
    pendingSelfManagement: true,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();

  // Costruisci URL completo (host hard-coded — se cambia il dominio,
  // aggiorna anche qui).
  const url = `https://app.trailshare.app/claim-self/${businessId}?t=${token}`;

  logger.info(
    `[generateSelfClaimToken] businessId=${businessId} by=${request.auth.uid}`
  );

  return {
    success: true,
    token,
    url,
    expiresAt: expiresAt.toDate().toISOString(),
    expiresInDays: SELF_CLAIM_TTL_DAYS,
  };
});

// ===================================================================
// CLAIM REQUESTS PUBBLICHE (Epic 7.H5)
// ===================================================================
// Flow public: visitatore di scheda unclaimed compila form, scrive
// su `business_claim_requests/{auto}` con status='pending'.
// Questo trigger invia email al team admin (via Trigger Email
// Extension che ascolta `mail/`). L'admin review da web admin e
// chiama approveClaimRequest/rejectClaimRequest che fa ownership
// transfer + email all'utente.

const ADMIN_NOTIFY_EMAIL = 'info@trailshare.app';

exports.onClaimRequestCreated = onDocumentCreated(
  'business_claim_requests/{requestId}',
  async (event) => {
    const data = event.data && event.data.data();
    if (!data) return;
    const requestId = event.params.requestId;

    const subject = `[Claim] Richiesta per "${data.businessName}"`;
    const html = `
      <h2>Nuova richiesta di claim Spazio Pro</h2>
      <p><strong>Scheda:</strong> ${data.businessName} (ID: ${data.businessId})</p>
      <p><strong>Slug:</strong> ${data.businessSlug || '-'}</p>
      <hr/>
      <h3>Dati richiedente</h3>
      <ul>
        <li><strong>Nome:</strong> ${data.requesterName || '-'}</li>
        <li><strong>Ruolo:</strong> ${data.requesterRole || '-'}</li>
        <li><strong>P.IVA / CF:</strong> ${data.requesterVat || '-'}</li>
        <li><strong>Email:</strong> ${data.requesterEmail || '-'}</li>
        <li><strong>Telefono:</strong> ${data.requesterPhone || '-'}</li>
        <li><strong>Sito:</strong> ${data.requesterWebsite || '-'}</li>
        <li><strong>UID Firebase:</strong> ${data.requesterUid}</li>
      </ul>
      ${data.notes ? `<p><strong>Note:</strong> ${data.notes}</p>` : ''}
      <hr/>
      <p><a href="https://app.trailshare.app/admin">Apri Admin Panel</a> per
      approvare o rifiutare la richiesta (ID: ${requestId}).</p>
    `.trim();

    try {
      await db.collection('mail').add({
        to: [ADMIN_NOTIFY_EMAIL],
        message: {
          subject,
          html,
          text: `Nuova claim request per "${data.businessName}". Apri /admin per approvare. ID: ${requestId}`,
        },
      });
      logger.info(`[onClaimRequestCreated] email queued for ${requestId}`);
    } catch (e) {
      logger.error(`[onClaimRequestCreated] mail write failed: ${e.message}`);
    }
  }
);

exports.approveClaimRequest = onCall(async (request) => {
  if (!(await _isCallerAdmin(request.auth))) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Solo admin platform puo approvare claim.'
    );
  }
  const requestId = request.data && request.data.requestId;
  if (!requestId || typeof requestId !== 'string') {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'requestId mancante.'
    );
  }

  const requestRef = db.collection('business_claim_requests').doc(requestId);
  const result = await db.runTransaction(async (tx) => {
    const reqSnap = await tx.get(requestRef);
    if (!reqSnap.exists) {
      throw new functions.https.HttpsError(
        'not-found', `Request ${requestId} non trovata.`
      );
    }
    const req = reqSnap.data();
    if (req.status !== 'pending') {
      throw new functions.https.HttpsError(
        'failed-precondition',
        `Request gia processata (status=${req.status}).`
      );
    }
    const businessRef = db.collection('businesses').doc(req.businessId);
    const bizSnap = await tx.get(businessRef);
    if (!bizSnap.exists) {
      throw new functions.https.HttpsError(
        'not-found', `Business ${req.businessId} non trovato.`
      );
    }
    const biz = bizSnap.data();
    const oldOwnerUid = biz.ownerId;
    const oldAdmins = Array.isArray(biz.adminUserIds) ? biz.adminUserIds : [];
    const newOwnerUid = req.requesterUid;
    const newAdmins = Array.from(new Set([
      ...oldAdmins.filter((id) => id !== newOwnerUid),
      oldOwnerUid,
    ].filter(Boolean)));

    tx.update(businessRef, {
      ownerId: newOwnerUid,
      adminUserIds: newAdmins,
      // 7.H1 — passa da unclaimed a verified (entry-level pagato in
      // futuro, oggi free per i seed clients). Se il business era
      // gia verified (claim manuale post-fatto), lascia il tier.
      tier: biz.tier === 'unclaimed' ? 'verified' : biz.tier,
      disclaimerVisible: false,
      pendingSelfManagement: false,
      claimedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      // 7.H12 funnel
      'funnelCounters.claim_approved': admin.firestore.FieldValue.increment(1),
    });
    tx.update(requestRef, {
      status: 'approved',
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
      processedByUid: request.auth.uid,
    });
    return { businessName: biz.name, requesterEmail: req.requesterEmail };
  });

  // Email di conferma al richiedente (best-effort, fuori transazione).
  try {
    await db.collection('mail').add({
      to: [result.requesterEmail],
      message: {
        subject: `Hai ottenuto la gestione di "${result.businessName}"`,
        html: `
          <h2>Richiesta approvata</h2>
          <p>Ciao,</p>
          <p>La tua richiesta di gestione per <strong>${result.businessName}</strong>
          è stata approvata dal team TrailShare.</p>
          <p>Ora puoi accedere alla scheda da app o da
          <a href="https://app.trailshare.app">app.trailshare.app</a> e
          aggiornare foto, orari, listino, percorsi consigliati.</p>
          <p>Per qualsiasi necessità rispondi a questa email.</p>
          <p>— Team TrailShare</p>
        `.trim(),
      },
    });
  } catch (e) {
    logger.warn(`[approveClaimRequest] mail to requester failed: ${e.message}`);
  }

  logger.info(`[approveClaimRequest] ${requestId} → ${result.businessName}`);
  return { success: true, ...result };
});

exports.rejectClaimRequest = onCall(async (request) => {
  if (!(await _isCallerAdmin(request.auth))) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Solo admin platform puo rifiutare claim.'
    );
  }
  const { requestId, reason } = request.data || {};
  if (!requestId || typeof requestId !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'requestId mancante.');
  }
  const reasonText = (typeof reason === 'string' && reason.trim().length > 0)
    ? reason.trim()
    : 'Dati forniti non sufficienti per verificare la richiesta.';

  const requestRef = db.collection('business_claim_requests').doc(requestId);
  const reqSnap = await requestRef.get();
  if (!reqSnap.exists) {
    throw new functions.https.HttpsError('not-found', `Request ${requestId} non trovata.`);
  }
  const req = reqSnap.data();
  if (req.status !== 'pending') {
    throw new functions.https.HttpsError(
      'failed-precondition',
      `Request gia processata (status=${req.status}).`
    );
  }

  await requestRef.update({
    status: 'rejected',
    rejectionReason: reasonText,
    processedAt: admin.firestore.FieldValue.serverTimestamp(),
    processedByUid: request.auth.uid,
  });
  // 7.H12 funnel counter (best-effort, fuori dal flow critico)
  try {
    await db.collection('businesses').doc(req.businessId).update({
      'funnelCounters.claim_rejected': admin.firestore.FieldValue.increment(1),
    });
  } catch (_) { /* swallow */ }

  try {
    await db.collection('mail').add({
      to: [req.requesterEmail],
      message: {
        subject: `Aggiornamento richiesta gestione "${req.businessName}"`,
        html: `
          <h2>Richiesta non approvata</h2>
          <p>Ciao,</p>
          <p>Abbiamo valutato la tua richiesta di gestione per
          <strong>${req.businessName}</strong> e per ora non possiamo
          approvarla.</p>
          <p><strong>Motivo:</strong> ${reasonText}</p>
          <p>Se ritieni ci sia un errore, rispondi a questa email allegando
          ulteriore documentazione (visura camerale, fattura intestata,
          ecc.) e riapriremo la valutazione.</p>
          <p>— Team TrailShare</p>
        `.trim(),
      },
    });
  } catch (e) {
    logger.warn(`[rejectClaimRequest] mail to requester failed: ${e.message}`);
  }

  logger.info(`[rejectClaimRequest] ${requestId} rejected: ${reasonText}`);
  return { success: true, requestId, reason: reasonText };
});

exports.acceptSelfClaim = onCall(async (request) => {
  if (!request.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Devi essere loggato per rivendicare la scheda.'
    );
  }
  const { businessId, token } = request.data || {};
  if (!businessId || !token || typeof businessId !== 'string' || typeof token !== 'string') {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'businessId e token sono obbligatori.'
    );
  }

  const newOwnerUid = request.auth.uid;

  // Transaction: leggi token + business, valida tutto, applica
  // ownership transfer atomicamente. Se fallisce qualunque check,
  // niente viene modificato.
  const result = await db.runTransaction(async (tx) => {
    const tokenRef = db.collection('business_self_claims').doc(token);
    const tokenSnap = await tx.get(tokenRef);
    if (!tokenSnap.exists) {
      throw new functions.https.HttpsError(
        'not-found',
        'Token non valido o gia consumato.'
      );
    }
    const tokenData = tokenSnap.data();
    if (tokenData.businessId !== businessId) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Token non corrisponde a questa scheda.'
      );
    }
    const expiresAt = tokenData.expiresAt;
    if (expiresAt && expiresAt.toMillis() < Date.now()) {
      throw new functions.https.HttpsError(
        'deadline-exceeded',
        'Token scaduto. Chiedi al team TrailShare un nuovo link.'
      );
    }

    const businessRef = db.collection('businesses').doc(businessId);
    const businessSnap = await tx.get(businessRef);
    if (!businessSnap.exists) {
      throw new functions.https.HttpsError(
        'not-found',
        'Scheda non trovata.'
      );
    }
    const business = businessSnap.data();
    const oldOwnerUid = business.ownerId;
    const oldAdmins = Array.isArray(business.adminUserIds)
      ? business.adminUserIds
      : [];

    // Se l'utente loggato e' GIA' l'owner, niente da fare (idempotente).
    if (oldOwnerUid === newOwnerUid) {
      tx.delete(tokenRef);
      tx.update(businessRef, {
        pendingSelfManagement: false,
        claimedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return { alreadyOwner: true, businessName: business.name };
    }

    // Transferisci ownership: vecchio owner va in adminUserIds (cosi'
    // il team mantiene accesso per supporto se serve). Nuovo owner =
    // utente che ha cliccato il link.
    const newAdmins = Array.from(new Set([
      ...oldAdmins.filter((id) => id !== newOwnerUid),
      oldOwnerUid,
    ].filter(Boolean)));

    tx.update(businessRef, {
      ownerId: newOwnerUid,
      adminUserIds: newAdmins,
      pendingSelfManagement: false,
      claimedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.delete(tokenRef);

    return {
      alreadyOwner: false,
      businessName: business.name,
      previousOwnerUid: oldOwnerUid,
    };
  });

  logger.info(
    `[acceptSelfClaim] businessId=${businessId} newOwnerUid=${newOwnerUid} alreadyOwner=${result.alreadyOwner}`
  );

  return { success: true, ...result };
});

// ===================================================================
// OSM IMPORT (Epic 7.H2 + 7.H3)
// ===================================================================
//
// Pre-popola schede Spazio Pro `unclaimed` a partire da OpenStreetMap
// via Overpass API. GDPR: dati pubblici aziendali, base legale
// art. 6.1.f (interesse legittimo) + banner disclaimer + opt-out
// 1-click (vedi docs/gtm/PRESEEDING_PRIVACY_UPDATE.md).
//
// Architettura:
// - `importOsmBusinesses({region, osmTag, dryRun})` callable admin-only,
//   one-shot per regione. Idempotente: dedup su sourceUrl.
// - `refreshOsmBusinessesMonthly` scheduled. Re-fetch dati pubblici
//   dei doc unclaimed e aggiorna nome/coordinate/orari (sempre solo
//   per le schede ANCORA unclaimed; non tocca quelle claimate).

const OVERPASS_API = 'https://overpass-api.de/api/interpreter';
const OVERPASS_TIMEOUT_MS = 60_000;
const OSM_USER_AGENT = 'TrailShare/2.4.6 (+https://trailshare.app; info@trailshare.app)';

// Confini amministrativi reali delle regioni italiane via ISO 3166-2.
// La query Overpass usa `area["ISO3166-2"="IT-XX"]->.r;` per
// restringere i POI ai confini ufficiali, NIENTE spillover su
// regioni vicine o oltreconfine. Più pulito di bbox approssimati.
//
// Per Trentino-Alto Adige usiamo le province autonome (IT-TN, IT-BZ)
// separate, perché Trentino e Alto Adige in TrailShare hanno valore
// e cultura outdoor differenti.
//
// "italia" usa il country code ISO 3166-1 (IT) — pesante, evitare.
const ITALY_REGION_ISO = {
  lombardia:     'IT-25',
  piemonte:      'IT-21',
  veneto:        'IT-34',
  trentino:      'IT-TN', // provincia autonoma di Trento
  altoadige:     'IT-BZ', // provincia autonoma di Bolzano
  valleaosta:    'IT-23',
  liguria:       'IT-42',
  emiliaromagna: 'IT-45',
  toscana:       'IT-52',
  marche:        'IT-57',
  umbria:        'IT-55',
  lazio:         'IT-62',
  abruzzo:       'IT-65',
  molise:        'IT-67',
  campania:      'IT-72',
  puglia:        'IT-75',
  basilicata:    'IT-77',
  calabria:      'IT-78',
  sicilia:       'IT-82',
  sardegna:      'IT-88',
  italia:        'IT',     // country, query pesante
};

// Mappa tipo TrailShare ↔ tag OSM. Una entry può combinare più
// (tag, value) per esprimere "OR".
//
// `rifugio` = SOLO alpine_hut (rifugio gestito tradizionale). I bivacchi
// (wilderness_hut) sono ~50% del volume OSM ma poco utili come Spazio
// Pro: non hanno gestore. Per ora skip; se servono in futuro li
// promuoviamo in un tipo "bivacco" separato.
const OSM_TAG_PRESETS = {
  rifugio: [
    { k: 'tourism', v: 'alpine_hut' },
  ],
  noleggio: [
    { k: 'rental', v: 'bicycle' },
    { k: 'rental', v: 'ski' },
    { k: 'shop', v: 'bicycle' }, // shop=bicycle spesso ha anche rental
  ],
  guidaAlpina: [
    { k: 'sport', v: 'climbing' },
    { k: 'leisure', v: 'climbing' },
  ],
  shop: [
    { k: 'shop', v: 'outdoor' },
    { k: 'shop', v: 'sports' },
  ],
};

/// Slugify (allineato a lib/presentation/pages/business/business_create_page.dart)
function slugify(input) {
  return (input || '')
    .toLowerCase()
    .trim()
    .replace(/[àáâãä]/g, 'a')
    .replace(/[èéêë]/g, 'e')
    .replace(/[ìíîï]/g, 'i')
    .replace(/[òóôõö]/g, 'o')
    .replace(/[ùúûü]/g, 'u')
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-+|-+$/g, '')
    || 'spazio';
}

async function uniqueSlug(base) {
  let candidate = base;
  let n = 1;
  while (true) {
    const snap = await db.collection('businesses')
      .where('slug', '==', candidate)
      .limit(1).get();
    if (snap.empty) return candidate;
    n++;
    candidate = `${base}-${n}`;
    if (n > 100) return `${base}-${Date.now()}`;
  }
}

/// Costruisce query Overpass QL ristretta ai confini amministrativi
/// ufficiali (ISO 3166-2). Cerca sia node sia way (alcuni rifugi
/// sono mappati come polygon).
function buildOverpassQuery(isoCode, tagPairs) {
  // `area[...]->.r` definisce l'area di ricerca. Per ISO 3166-2 (es.
  // IT-25) cerchiamo la regione; per country code (IT) ISO 3166-1.
  const areaTag = isoCode.includes('-') ? 'ISO3166-2' : 'ISO3166-1';
  const nodeParts = tagPairs.map(({ k, v }) => `node["${k}"="${v}"](area.r);`).join('');
  const wayParts = tagPairs.map(({ k, v }) => `way["${k}"="${v}"](area.r);`).join('');
  return `[out:json][timeout:60];
area["${areaTag}"="${isoCode}"]->.r;
(${nodeParts}${wayParts});
out center tags;`;
}

/// Normalizza un POI OSM nel formato Business doc.
function osmToBusinessDoc(poi, businessType, ownerId) {
  // Coordinate: node ha lat/lon direttamente; way ha center.{lat,lon}
  const lat = poi.lat != null ? poi.lat : (poi.center && poi.center.lat);
  const lng = poi.lon != null ? poi.lon : (poi.center && poi.center.lon);
  if (lat == null || lng == null) return null;

  const tags = poi.tags || {};
  const name = (tags.name || tags['name:it'] || '').trim();
  if (!name) return null; // niente nome → non importabile

  const description = (tags.description || tags['description:it'] || '').trim() || null;
  const phone = (tags.phone || tags['contact:phone'] || '').trim() || null;
  const email = (tags.email || tags['contact:email'] || '').trim() || null;
  const website = (tags.website || tags['contact:website'] || tags.url || '').trim() || null;
  const city = (tags['addr:city'] || tags['addr:locality'] || '').trim() || null;
  const street = (tags['addr:street'] || '').trim();
  const housenumber = (tags['addr:housenumber'] || '').trim();
  const address = [street, housenumber].filter(Boolean).join(' ').trim() || null;
  const elevation = tags.ele ? Number(tags.ele) : null;

  const geohash = encodeGeohash(lat, lng, 7);
  const osmType = poi.type; // 'node' | 'way'
  const osmId = poi.id;
  const sourceUrl = `https://www.openstreetmap.org/${osmType}/${osmId}`;

  return {
    name,
    type: businessType,
    tier: 'unclaimed',
    status: 'active',
    description,
    location: {
      lat, lng, geohash,
      ...(city ? { city } : {}),
      ...(address ? { address } : {}),
      ...(elevation != null && !isNaN(elevation) ? { elevation } : {}),
    },
    ...(phone || email || website ? {
      contacts: {
        ...(phone ? { phone } : {}),
        ...(email ? { email } : {}),
        ...(website ? { website } : {}),
      },
    } : {}),
    ownerId, // team admin che ha lanciato l'import
    followerCount: 0,
    postsCount: 0,
    reviewCount: 0,
    sourceUrl,
    disclaimerVisible: true,
    pendingSelfManagement: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

exports.importOsmBusinesses = onCall(
  { timeoutSeconds: 300, memory: '512MiB' },
  async (request) => {
    if (!(await _isCallerAdmin(request.auth))) {
      throw new functions.https.HttpsError(
        'permission-denied', 'Solo admin platform puo importare da OSM.'
      );
    }
    const { region, businessType, dryRun } = request.data || {};
    if (!region || !ITALY_REGION_ISO[region]) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        `region invalida. Disponibili: ${Object.keys(ITALY_REGION_ISO).join(', ')}`
      );
    }
    if (!businessType || !OSM_TAG_PRESETS[businessType]) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        `businessType invalido. Disponibili: ${Object.keys(OSM_TAG_PRESETS).join(', ')}`
      );
    }

    const isoCode = ITALY_REGION_ISO[region];
    const tagPairs = OSM_TAG_PRESETS[businessType];
    const query = buildOverpassQuery(isoCode, tagPairs);

    logger.info(`[importOsmBusinesses] region=${region} type=${businessType} dryRun=${!!dryRun}`);

    let overpassData;
    try {
      const resp = await axios.post(
        OVERPASS_API,
        `data=${encodeURIComponent(query)}`,
        {
          timeout: OVERPASS_TIMEOUT_MS,
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'User-Agent': OSM_USER_AGENT,
          },
        }
      );
      overpassData = resp.data;
    } catch (e) {
      throw new functions.https.HttpsError(
        'unavailable',
        `Overpass API fallita: ${e.message}. Riprova fra qualche minuto (rate limit OSM).`
      );
    }

    const elements = Array.isArray(overpassData && overpassData.elements)
      ? overpassData.elements : [];
    logger.info(`[importOsmBusinesses] Overpass ha restituito ${elements.length} elementi`);

    // Dedup su sourceUrl. Una query batch get sui sourceUrl trovati.
    const candidates = [];
    for (const poi of elements) {
      const doc = osmToBusinessDoc(poi, businessType, request.auth.uid);
      if (doc) candidates.push(doc);
    }
    if (candidates.length === 0) {
      return {
        success: true,
        region, businessType, dryRun: !!dryRun,
        fetched: elements.length, created: 0, skipped: 0,
        message: 'Nessun POI valido nei dati Overpass (mancano coordinate o nome).',
      };
    }

    // Carica tutti i sourceUrl esistenti per dedup. Chunk da 10 perche'
    // `where(in)` di Firestore accetta max 10 valori per query.
    const existingUrls = new Set();
    const urls = candidates.map((c) => c.sourceUrl);
    for (let i = 0; i < urls.length; i += 10) {
      const chunk = urls.slice(i, i + 10);
      const snap = await db.collection('businesses')
        .where('sourceUrl', 'in', chunk)
        .get();
      snap.forEach((d) => {
        const u = d.data().sourceUrl;
        if (u) existingUrls.add(u);
      });
    }

    let created = 0, skipped = 0;
    const errors = [];
    const samples = []; // per dryRun mostra primi 5 doc

    for (const doc of candidates) {
      if (existingUrls.has(doc.sourceUrl)) {
        skipped++;
        continue;
      }
      if (dryRun) {
        if (samples.length < 5) {
          samples.push({
            name: doc.name,
            sourceUrl: doc.sourceUrl,
            city: doc.location.city || null,
            lat: doc.location.lat,
            lng: doc.location.lng,
          });
        }
        created++;
        continue;
      }
      try {
        // Slug unique al momento del write per evitare collisioni.
        const slug = await uniqueSlug(slugify(doc.name));
        await db.collection('businesses').add({ ...doc, slug });
        created++;
      } catch (e) {
        errors.push({ name: doc.name, error: e.message });
      }
    }

    logger.info(
      `[importOsmBusinesses] region=${region} fetched=${elements.length} ` +
      `created=${created} skipped=${skipped} errors=${errors.length} dryRun=${!!dryRun}`
    );

    return {
      success: true,
      region, businessType, dryRun: !!dryRun,
      fetched: elements.length,
      created, skipped, errors,
      samples: dryRun ? samples : undefined,
    };
  }
);

/// 7.H3 — Refresh mensile. Per ogni doc tier=unclaimed con sourceUrl
/// OSM, re-fetch via Overpass `node/id` o `way/id` e aggiorna i campi
/// pubblici (nome, coordinate, contatti, orari). Non tocca i doc
/// claimati: rispettiamo l'autonomia del gestore.
///
/// Approccio: invece di N richieste, raggruppiamo in batch da 200 e
/// usiamo query Overpass `node(id:1,2,3,..);way(id:..);out;`.
exports.refreshOsmBusinessesMonthly = onSchedule(
  { schedule: '0 4 1 * *', timeZone: 'Europe/Rome', timeoutSeconds: 540, memory: '512MiB' },
  async (event) => {
    logger.info('[refreshOsmBusinessesMonthly] start');

    const snap = await db.collection('businesses')
      .where('tier', '==', 'unclaimed')
      .where('disclaimerVisible', '==', true)
      .get();
    if (snap.empty) {
      logger.info('[refreshOsmBusinessesMonthly] no unclaimed docs');
      return;
    }

    // Mappa: osmType:id → docRef. Estraiamo da sourceUrl.
    const byOsmKey = new Map();
    snap.forEach((d) => {
      const data = d.data();
      const url = data.sourceUrl || '';
      const m = url.match(/openstreetmap\.org\/(node|way)\/(\d+)/);
      if (!m) return;
      const key = `${m[1]}:${m[2]}`;
      byOsmKey.set(key, d.ref);
    });

    if (byOsmKey.size === 0) {
      logger.info('[refreshOsmBusinessesMonthly] no osm-sourced docs');
      return;
    }

    // Batch query Overpass: max ~200 id per batch per evitare URL troppo
    // lunghi e timeout.
    const keys = Array.from(byOsmKey.keys());
    let refreshed = 0;
    for (let i = 0; i < keys.length; i += 200) {
      const batchKeys = keys.slice(i, i + 200);
      const nodeIds = batchKeys.filter((k) => k.startsWith('node:'))
        .map((k) => k.split(':')[1]).join(',');
      const wayIds = batchKeys.filter((k) => k.startsWith('way:'))
        .map((k) => k.split(':')[1]).join(',');
      const queryParts = [];
      if (nodeIds) queryParts.push(`node(id:${nodeIds});`);
      if (wayIds) queryParts.push(`way(id:${wayIds});`);
      if (queryParts.length === 0) continue;

      const query = `[out:json][timeout:50];(${queryParts.join('')});out center tags;`;
      let elements = [];
      try {
        const resp = await axios.post(
          OVERPASS_API,
          `data=${encodeURIComponent(query)}`,
          {
            timeout: OVERPASS_TIMEOUT_MS,
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'User-Agent': OSM_USER_AGENT,
            },
          }
        );
        elements = (resp.data && resp.data.elements) || [];
      } catch (e) {
        logger.error(`[refreshOsmBusinessesMonthly] Overpass batch ${i} failed: ${e.message}`);
        continue;
      }

      for (const poi of elements) {
        const key = `${poi.type}:${poi.id}`;
        const ref = byOsmKey.get(key);
        if (!ref) continue;

        // Reuse il normalizer (ownerId placeholder, lo ignoriamo nel patch).
        const fresh = osmToBusinessDoc(poi, '', '');
        if (!fresh) continue;

        // Patch parziale: solo i campi pubblici che possono cambiare.
        // Niente tier/ownerId/createdAt/sourceUrl/disclaimer.
        const patch = {
          name: fresh.name,
          'location.lat': fresh.location.lat,
          'location.lng': fresh.location.lng,
          'location.geohash': fresh.location.geohash,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        if (fresh.location.city) patch['location.city'] = fresh.location.city;
        if (fresh.location.address) patch['location.address'] = fresh.location.address;
        if (fresh.location.elevation != null) patch['location.elevation'] = fresh.location.elevation;
        if (fresh.description) patch.description = fresh.description;
        if (fresh.contacts && fresh.contacts.phone) patch['contacts.phone'] = fresh.contacts.phone;
        if (fresh.contacts && fresh.contacts.email) patch['contacts.email'] = fresh.contacts.email;
        if (fresh.contacts && fresh.contacts.website) patch['contacts.website'] = fresh.contacts.website;

        try {
          await ref.update(patch);
          refreshed++;
        } catch (e) {
          logger.warn(`[refreshOsmBusinessesMonthly] update ${ref.id} failed: ${e.message}`);
        }
      }
    }

    logger.info(`[refreshOsmBusinessesMonthly] done refreshed=${refreshed} total=${byOsmKey.size}`);
  }
);

// ===================================================================
// FUNNEL TELEMETRY (Epic 7.H12)
// ===================================================================
//
// Eventi per misurare la conversione del claim flow:
// - unclaimed_view: scheda unclaimed visualizzata
// - claim_started: utente clicca "Rivendica"
// - claim_completed: form submittato
// - claim_approved: admin approva (incrementato da approveClaimRequest)
// - claim_rejected: admin rifiuta
//
// Doc per evento in `business_funnel_events/{auto}`. Aggregati
// (counter per businessId) calcolabili con query. MVP semplice:
// niente sampling, niente bot detection — quando il volume cresce
// aggiungeremo bot filter via UA.

exports.trackFunnelEvent = onCall(async (request) => {
  // No isCallerAdmin check: chiunque (anche anon) può tracciare visite
  // a una scheda pubblica. Richiediamo solo che il payload sia valido.
  const { businessId, event } = request.data || {};
  if (!businessId || typeof businessId !== 'string') {
    throw new functions.https.HttpsError('invalid-argument', 'businessId mancante');
  }
  const allowedEvents = ['unclaimed_view', 'claim_started', 'claim_completed'];
  if (!event || !allowedEvents.includes(event)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `event invalido. Ammessi: ${allowedEvents.join(', ')}`
    );
  }

  // Batch: scrivi evento + increment counter aggregato sul business
  // doc (campo `funnelCounters.{event}`). L'owner della scheda lo
  // legge dalla read pubblica del doc, senza bisogno di Cloud Function
  // dedicata per gli aggregati.
  const batch = db.batch();
  const eventRef = db.collection('business_funnel_events').doc();
  batch.set(eventRef, {
    businessId,
    event,
    userId: request.auth ? request.auth.uid : null,
    ts: admin.firestore.FieldValue.serverTimestamp(),
  });
  const businessRef = db.collection('businesses').doc(businessId);
  batch.update(businessRef, {
    [`funnelCounters.${event}`]: admin.firestore.FieldValue.increment(1),
  });
  try {
    await batch.commit();
  } catch (e) {
    // Se l'increment fallisce (es. doc non esiste) almeno scriviamo
    // l'evento singolarmente — meglio dato granular perso aggregato
    // che evento perso.
    logger.warn(`[trackFunnelEvent] batch failed: ${e.message} — fallback evento solo`);
    try {
      await eventRef.set({
        businessId, event,
        userId: request.auth ? request.auth.uid : null,
        ts: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (_) { /* swallow */ }
  }

  return { success: true };
});

// ===================================================================
// STATIC MAP PROXY (Epic 7.H10 — Outreach PDF)
// ===================================================================
// MapTiler Cloud applica una restrizione `User-Agent: TrailShareApp`
// sulla nostra key. Sul browser web il campo User-Agent è un
// "forbidden header" (CORS security) → non possiamo settarlo da
// http.get di Dart, e MapTiler rifiuta la request.
//
// Soluzione: questa Cloud Function fa proxy server-side. Il client
// chiama `staticMapProxy?lat=...&lng=...&markers=...`, noi chiamiamo
// MapTiler dal Cloud Run env settando il giusto UA, e restituiamo
// l'immagine PNG con Cache-Control 7 giorni.
//
// Le tile di MapTiler sono cachate dal CDN nostro per ridurre il
// numero di richieste a MapTiler (free tier 100k/mese).

// ===================================================================
// OUTREACH BATCH EMAIL (Epic 7.H10b)
// ===================================================================
// Invio automatico email outreach alle schede unclaimed con email
// pubblica. Pesca da Firestore, genera self-claim token per ognuna,
// scrive doc su `mail/` collection (Trigger Email Extension lo manda
// via SendGrid).
//
// GDPR:
// - Solo email pubbliche delle attività (campo contacts.email del
//   doc business — di solito letto da OSM, sito ufficiale, registro
//   imprese)
// - Footer obbligatorio con motivazione contatto + opt-out via reply
// - Cap 50 email/batch (free tier SendGrid 100/giorno totali)
// - Skip schede già contattate (campo outreachEmailSentAt non null)
// - Skip domini personali generici (gmail/hotmail/yahoo/libero —
//   probabili email private, non aziendali)
//
// Funzioni:
// - previewOutreachBatch({region, type}) → conteggio + sample 5
//   senza inviare nulla
// - sendOutreachBatch({region, type, maxEmails=50, dryRun}) → invio
//   batch effettivo

/// Converte un body HTML in plain text accettabile come fallback
/// multipart/alternative. Rimuove tag, decodifica entità HTML basilari,
/// normalizza gli spazi. Best-effort — non è un parser HTML completo:
/// va bene per i nostri template controllati lato server.
function _htmlToPlainText(html) {
  if (!html) return '';
  let s = String(html);
  // Sostituisci <br>, </p>, </div>, </li>, </h*> con newline
  s = s.replace(/<\s*br\s*\/?\s*>/gi, '\n');
  s = s.replace(/<\/\s*(p|div|li|h[1-6])\s*>/gi, '\n\n');
  // Bullet point per <li>
  s = s.replace(/<\s*li[^>]*>/gi, '• ');
  // Rimuovi style/script/head/title interi (con contenuto)
  s = s.replace(/<\s*(style|script|head|title)[^>]*>[\s\S]*?<\/\s*\1\s*>/gi, '');
  // Estrai href dai link in formato "testo (https://url)"
  s = s.replace(/<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi,
    (_m, href, txt) => {
      const t = txt.replace(/<[^>]+>/g, '').trim();
      if (!t || t === href) return href;
      return `${t} (${href})`;
    });
  // Rimuovi tutti gli altri tag
  s = s.replace(/<[^>]+>/g, '');
  // Decodifica entità HTML comuni
  s = s.replace(/&nbsp;/g, ' ')
       .replace(/&amp;/g, '&')
       .replace(/&lt;/g, '<')
       .replace(/&gt;/g, '>')
       .replace(/&quot;/g, '"')
       .replace(/&#39;/g, "'")
       .replace(/&euro;/g, '€')
       .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
       .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(parseInt(d, 10)));
  // Normalizza whitespace
  s = s.replace(/[ \t]+/g, ' ');
  s = s.replace(/\n{3,}/g, '\n\n');
  s = s.split('\n').map((l) => l.trim()).join('\n').trim();
  return s;
}

const _PERSONAL_EMAIL_DOMAINS = new Set([
  'gmail.com', 'googlemail.com', 'hotmail.com', 'hotmail.it',
  'yahoo.com', 'yahoo.it', 'libero.it', 'live.it', 'live.com',
  'outlook.com', 'outlook.it', 'msn.com', 'tin.it', 'alice.it',
  'virgilio.it', 'fastwebnet.it', 'tiscali.it', 'me.com',
  'icloud.com', 'privaterelay.appleid.com', 'aol.com',
]);

function _isLikelyBusinessEmail(email) {
  if (!email || typeof email !== 'string') return false;
  const m = email.toLowerCase().trim().match(/@([^@\s]+)$/);
  if (!m) return false;
  return !_PERSONAL_EMAIL_DOMAINS.has(m[1]);
}

/// Estrae il dominio dall'email. "info@foo.it" → "foo.it".
function _extractDomain(email) {
  const m = email.toLowerCase().trim().match(/@([^@\s]+)$/);
  return m ? m[1] : null;
}

/// DNS check: il dominio esiste e ha MX record (server email)?
/// Cache in-memory per session: stessa Cloud Function instance riusa
/// il risultato. Ritorna true se dominio valido + ha MX, false
/// altrimenti (DNS fail, no MX, ENOTFOUND).
const _dns = require('dns').promises;
const _domainMxCache = new Map();

async function _domainHasMx(domain) {
  if (!domain) return false;
  if (_domainMxCache.has(domain)) return _domainMxCache.get(domain);
  try {
    const records = await _dns.resolveMx(domain);
    const valid = Array.isArray(records) && records.length > 0;
    _domainMxCache.set(domain, valid);
    return valid;
  } catch (e) {
    // ENOTFOUND, ENODATA, ESERVFAIL → dominio non esiste o niente MX
    _domainMxCache.set(domain, false);
    return false;
  }
}

// Bbox approssimati per regioni italiane (lat_min, lat_max, lng_min,
// lng_max). Allineati a ITALY_REGION_BBOX usato per OSM import.
// `null` = no filtro regione (tutte).
const _OUTREACH_REGION_BBOX = {
  lombardia:     [44.7, 46.7, 8.5, 11.5],
  piemonte:      [44.0, 46.5, 6.6, 9.2],
  veneto:        [44.7, 46.7, 10.6, 13.1],
  trentino:      [45.6, 46.6, 10.4, 11.9],
  altoadige:     [46.2, 47.1, 10.3, 12.5],
  valleaosta:    [45.4, 45.9, 6.8, 7.9],
  liguria:       [43.7, 44.7, 7.5, 10.0],
  emiliaromagna: [43.7, 45.1, 9.2, 12.8],
  toscana:       [42.2, 44.5, 9.6, 12.4],
  marche:        [42.7, 44.0, 12.2, 13.9],
  umbria:        [42.5, 43.6, 11.9, 13.3],
  lazio:         [40.7, 42.7, 11.4, 14.0],
  abruzzo:       [41.7, 42.9, 13.0, 14.8],
  molise:        [41.4, 42.1, 14.0, 15.2],
  campania:      [39.9, 41.5, 13.7, 15.8],
  puglia:        [39.7, 42.2, 14.8, 18.6],
  basilicata:    [39.9, 41.2, 15.3, 16.9],
  calabria:      [37.9, 40.2, 15.5, 17.3],
  sicilia:       [36.6, 38.4, 12.3, 15.7],
  sardegna:      [38.8, 41.3, 8.1, 9.9],
};

/// Costruisce body HTML email outreach per una scheda specifica.
function _buildOutreachEmailHtml(business, claimUrl) {
  const name = (business.name || '').replace(/</g, '&lt;');
  const city = business.location && business.location.city
    ? business.location.city.replace(/</g, '&lt;')
    : '';
  const publicUrl = `https://trailshare.app/b/${business.slug}`;
  const typeLabel = ({
    rifugio: 'rifugio',
    noleggio: 'noleggio',
    guidaAlpina: 'guida alpina',
    scuolaAlpinismo: 'scuola alpinismo',
    shop: 'shop outdoor',
    tourOperator: 'tour operator',
    consorzioTurismo: 'consorzio turismo',
    altro: 'attività',
  })[business.type] || 'attività';

  return `
    <div style="font-family: 'Helvetica Neue', Arial, sans-serif; max-width: 600px; color: #2d3436; line-height: 1.5;">
      <p>Buongiorno,</p>

      <p>mi chiamo Massimiliano e gestisco <strong>TrailShare</strong>,
      un'app di tracking GPS e mappe per escursionisti, alpinisti e
      bikers attiva in Italia.</p>

      <p>Su TrailShare abbiamo creato una scheda pubblica del vostro
      ${typeLabel} <strong>${name}</strong> a partire da fonti pubbliche
      (OpenStreetMap, sito CAI, registro imprese):</p>

      <p><a href="${publicUrl}" style="color: #E07B4C; font-weight: 600;">${publicUrl}</a></p>

      <p>La scheda è già online e visitata dai nostri utenti che cercano
      informazioni ${city ? `sulla zona di ${city}` : 'nella vostra zona'}.</p>

      <p>Ti scrivo per proporti di <strong>prenderne tu il controllo</strong>:
      bastano cinque minuti, e da subito potrai:</p>

      <ul>
        <li>aggiornare foto, orari di apertura, listino prezzi</li>
        <li>aggiungere i percorsi che consigli ai tuoi ospiti</li>
        <li>ricevere statistiche delle visite e dei contatti</li>
        <li>rispondere alle domande dei clienti direttamente dall'app</li>
      </ul>

      <p>Per i primi sei mesi il servizio è <strong>gratuito</strong>
      (design partner program), poi €19,99/mese o €199/anno solo da
      gennaio 2027.</p>

      <p style="margin: 24px 0;">
        <a href="${claimUrl}"
           style="display: inline-block; background: #E07B4C; color: white;
                  padding: 12px 24px; text-decoration: none; border-radius: 8px;
                  font-weight: 600;">
          → Rivendica la scheda (1 click)
        </a>
      </p>

      <p>Il link sopra ti porta direttamente alla pagina dove confermi
      con un click di essere tu il gestore. Niente form lunghi.</p>

      <p>Per qualunque domanda mi puoi rispondere qui o scrivere a
      <a href="mailto:info@trailshare.app">info@trailshare.app</a>.</p>

      <p>Grazie del tempo, buona stagione.</p>

      <p>Massimiliano<br>
      <em>TrailShare</em><br>
      <a href="https://trailshare.app">trailshare.app</a></p>

      <hr style="border: none; border-top: 1px solid #dfe6e9; margin: 24px 0;">

      <p style="font-size: 11px; color: #636e72; line-height: 1.4;">
        Hai ricevuto questa email perché la tua attività è inserita su
        TrailShare a partire da dati pubblici (OpenStreetMap, registro
        imprese). Se non vuoi più ricevere comunicazioni o desideri la
        rimozione della scheda, rispondi a info@trailshare.app con
        oggetto "Rimozione" e provvederemo entro 48 ore lavorative.
        Base legale: interesse legittimo art. 6.1.f GDPR — dati
        pubblici aziendali.
      </p>
    </div>
  `;
}

/// Query base: schede unclaimed con email business pubblica e
/// outreach mai inviato. Filtra opzionalmente per regione (bbox) e
/// tipo. Ritorna lista di doc snapshot.
async function _findOutreachCandidates(region, businessType, limit, options = {}) {
  const { dnsCheck = true } = options;
  // Lato Firestore filtriamo tier + outreachEmailSentAt null. Il
  // resto (email valida, bbox regione, DNS check) in-memory perché
  // Firestore non supporta range + multiple inequality.
  let query = db.collection('businesses')
    .where('tier', '==', 'unclaimed')
    .where('status', '==', 'active');
  if (businessType) {
    query = query.where('type', '==', businessType);
  }
  const snap = await query.limit(3000).get();

  const bbox = region ? _OUTREACH_REGION_BBOX[region] : null;
  // Pre-filter veloce (senza DNS)
  const preFiltered = [];
  for (const doc of snap.docs) {
    const data = doc.data();
    if (data.outreachEmailSentAt) continue;
    const email = data.contacts && data.contacts.email;
    if (!_isLikelyBusinessEmail(email)) continue;
    if (bbox) {
      const lat = data.location && data.location.lat;
      const lng = data.location && data.location.lng;
      if (lat == null || lng == null) continue;
      if (lat < bbox[0] || lat > bbox[1] || lng < bbox[2] || lng > bbox[3]) {
        continue;
      }
    }
    preFiltered.push({ id: doc.id, ref: doc.ref, data });
  }

  if (!dnsCheck) {
    return preFiltered.slice(0, limit);
  }

  // DNS check parallelo (max 20 concurrent per non saturare il
  // resolver). Skippa i domini che non hanno MX record →
  // riduce drasticamente i bounce.
  const candidates = [];
  const skippedNoMx = [];
  const concurrency = 20;
  let cursor = 0;
  async function worker() {
    while (cursor < preFiltered.length && candidates.length < limit) {
      const idx = cursor++;
      if (idx >= preFiltered.length) break;
      const c = preFiltered[idx];
      const email = c.data.contacts.email;
      const domain = _extractDomain(email);
      const hasMx = await _domainHasMx(domain);
      if (hasMx) {
        if (candidates.length < limit) candidates.push(c);
      } else {
        skippedNoMx.push({ id: c.id, name: c.data.name, email });
      }
    }
  }
  await Promise.all(Array.from({ length: concurrency }, () => worker()));

  if (skippedNoMx.length > 0) {
    logger.info(
      `[outreach] DNS pre-check: skipped ${skippedNoMx.length} domini senza MX. ` +
      `Primi 3: ${skippedNoMx.slice(0, 3).map((s) => s.email).join(", ")}`
    );
  }
  return candidates;
}

exports.previewOutreachBatch = onCall(
  { timeoutSeconds: 180, memory: '512MiB' },
  async (request) => {
    if (!(await _isCallerAdmin(request.auth))) {
      throw new functions.https.HttpsError(
        'permission-denied', 'Solo admin platform puo eseguire outreach.'
      );
    }
    const { region, businessType } = request.data || {};
    if (region && !_OUTREACH_REGION_BBOX[region]) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        `region invalida. Disponibili: ${Object.keys(_OUTREACH_REGION_BBOX).join(', ')}, oppure null.`
      );
    }

    // Conta SENZA DNS check (veloce, mostra il volume "grezzo" che
    // verrebbe scartato senza filtri di qualità)
    const rawCandidates = await _findOutreachCandidates(
      region, businessType, 500, { dnsCheck: false }
    );
    // Conta CON DNS check (il volume reale che verrà inviato)
    const candidates = await _findOutreachCandidates(
      region, businessType, 500, { dnsCheck: true }
    );
    const samples = candidates.slice(0, 5).map((c) => ({
      id: c.id,
      name: c.data.name,
      city: c.data.location && c.data.location.city,
      email: c.data.contacts && c.data.contacts.email,
    }));

    return {
      success: true,
      region: region || 'all',
      businessType: businessType || 'all',
      found: candidates.length,
      foundBeforeDns: rawCandidates.length,
      skippedNoMx: rawCandidates.length - candidates.length,
      samples,
    };
  }
);

exports.sendOutreachBatch = onCall(
  { timeoutSeconds: 300, memory: '512MiB' },
  async (request) => {
    if (!(await _isCallerAdmin(request.auth))) {
      throw new functions.https.HttpsError(
        'permission-denied', 'Solo admin platform puo eseguire outreach.'
      );
    }
    const { region, businessType, maxEmails, dryRun } = request.data || {};
    const cap = Math.min(Math.max(parseInt(maxEmails) || 50, 1), 100);
    if (region && !_OUTREACH_REGION_BBOX[region]) {
      throw new functions.https.HttpsError(
        'invalid-argument', `region invalida.`
      );
    }

    const candidates = await _findOutreachCandidates(region, businessType, cap);

    let sent = 0;
    const errors = [];
    const senderUid = request.auth.uid;

    for (const c of candidates) {
      const b = c.data;
      const email = b.contacts.email;
      try {
        if (dryRun) {
          sent++;
          continue;
        }

        // Genera self-claim token per la scheda (inline — replica
        // logica generateSelfClaimToken con dedup).
        const token = crypto.randomBytes(16).toString('hex');
        const expiresAt = admin.firestore.Timestamp.fromMillis(
          Date.now() + SELF_CLAIM_TTL_DAYS * 24 * 60 * 60 * 1000
        );

        // Invalida token precedenti per questa scheda
        const oldTokens = await db.collection('business_self_claims')
          .where('businessId', '==', c.id)
          .get();
        const batch = db.batch();
        oldTokens.forEach((d) => batch.delete(d.ref));

        batch.set(db.collection('business_self_claims').doc(token), {
          businessId: c.id,
          expiresAt,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          createdByUid: senderUid,
          source: 'outreach_batch',
        });

        batch.update(c.ref, {
          pendingSelfManagement: true,
          outreachEmailSentAt: admin.firestore.FieldValue.serverTimestamp(),
          outreachStatus: 'sent',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        const claimUrl = `https://app.trailshare.app/claim-self/${c.id}?t=${token}`;
        const html = _buildOutreachEmailHtml({ ...b, slug: b.slug }, claimUrl);
        const subject = `${b.name} è già su TrailShare — ti va di gestirlo tu?`;

        // Scrive su collection `mail` per Trigger Email Extension.
        // Includiamo sempre il plain text fallback (multipart/alternative)
        // per evitare che vecchie webmail (Aruba, Libero, ecc.) mostrino
        // il codice HTML grezzo invece del messaggio renderizzato.
        batch.set(db.collection('mail').doc(), {
          to: [email],
          message: { subject, html, text: _htmlToPlainText(html) },
          replyTo: 'info@trailshare.app',
        });

        await batch.commit();
        sent++;
      } catch (e) {
        logger.warn(`[sendOutreachBatch] error on ${c.id}: ${e.message}`);
        errors.push({ businessId: c.id, name: b.name, error: e.message });
      }
    }

    logger.info(
      `[sendOutreachBatch] region=${region || 'all'} type=${businessType || 'all'} ` +
      `dryRun=${!!dryRun} candidates=${candidates.length} sent=${sent} ` +
      `errors=${errors.length}`
    );

    return {
      success: true,
      region: region || 'all',
      businessType: businessType || 'all',
      dryRun: !!dryRun,
      candidates: candidates.length,
      sent,
      errors,
    };
  }
);

// ===================================================================
// NEWSLETTER UTENTI — Service update email (v2.5.1)
// ===================================================================
// Invio email informative agli utenti registrati sulle principali
// novità del prodotto. Base legale: legittimo interesse art. 6.1.f
// GDPR + relazione contrattuale di servizio. Vedi privacy.html sez.
// "Comunicazioni di aggiornamento prodotto".
//
// Architettura:
// - Schema: user_profiles/{uid}.marketingOptOut (bool) +
//   marketingOptOutAt + newsletterLastSentAt
// - unsubscribeNewsletter: endpoint HTTP pubblico con uid+token HMAC,
//   marca opt-out e ritorna pagina HTML
// - previewNewsletterBatch: admin only, conta destinatari + 5 sample
// - sendNewsletterBatch: admin only, invia batch scrivendo su mail/
//   (Trigger Email Extension SendGrid)
//
// GDPR & best practice:
// - Link "Annulla iscrizione" obbligatorio in ogni email (footer)
// - Skip automatico utenti con marketingOptOut: true
// - Skip utenti con account cancellato / deleted
// - Cap di sicurezza (default 50, max 500 per batch)
// - DryRun mode per simulare senza inviare
// - Idempotente: newsletterLastSentCampaign per evitare doppi invii
//   della stessa campagna

const _NEWSLETTER_UNSUBSCRIBE_SECRET = () => {
  // HMAC secret stabile derivato dal project. In produzione si può
  // spostare su Secret Manager se serve rotazione. Per ora basta che
  // sia non guessable e stabile tra runtime instances.
  return process.env.NEWSLETTER_UNSUB_SECRET ||
    'trailshare-newsletter-unsub-v1-do-not-share';
};

function _newsletterUnsubToken(uid) {
  return crypto
    .createHmac('sha256', _NEWSLETTER_UNSUBSCRIBE_SECRET())
    .update(`unsub:${uid}`)
    .digest('hex')
    .substring(0, 32);
}

function _newsletterUnsubUrl(uid) {
  const token = _newsletterUnsubToken(uid);
  return `https://europe-west3-trailshare-5334b.cloudfunctions.net/unsubscribeNewsletter?uid=${encodeURIComponent(uid)}&t=${token}`;
}

/// Costruisce il body HTML della newsletter v2.5.1.
/// [displayName] = nome utente per personalizzazione (fallback "ciao").
function _buildNewsletterHtml(displayName, unsubUrl) {
  const greetName = (displayName || '').trim().split(' ')[0] || '';
  const greeting = greetName ? `Ciao ${greetName.replace(/</g, '&lt;')},` : 'Ciao,';

  return `
<!DOCTYPE html>
<html lang="it">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>TrailShare — Le novità di questi mesi</title>
</head>
<body style="margin:0;padding:0;background:#f5f4f1;font-family:'Helvetica Neue',Arial,sans-serif;color:#2d3436;">
<div style="max-width:600px;margin:0 auto;background:#ffffff;">

  <!-- Hero -->
  <div style="background:linear-gradient(135deg,#E07B4C 0%,#D86B3C 100%);padding:32px 24px;text-align:center;">
    <h1 style="margin:0;color:#ffffff;font-size:26px;font-weight:800;letter-spacing:-0.3px;">
      TrailShare è cresciuto.
    </h1>
    <p style="margin:8px 0 0;color:#fff3ee;font-size:15px;">
      Le novità che ti sei perso, in 2 minuti.
    </p>
  </div>

  <!-- Body -->
  <div style="padding:28px 24px;line-height:1.55;font-size:15px;">

    <p style="margin:0 0 16px;">${greeting}</p>

    <p style="margin:0 0 20px;">
      sono Massimiliano, fondatore di TrailShare. Ti scrivo perché ti sei
      registrato all'app nei mesi scorsi e nel frattempo sono uscite tre
      novità grosse che cambiano il modo di usarla. Te le racconto in breve.
    </p>

    <!-- News 1: Tour multi-giorno -->
    <div style="margin:24px 0;padding:18px;background:#fef9f5;border-left:4px solid #E07B4C;border-radius:6px;">
      <h2 style="margin:0 0 8px;font-size:18px;color:#2d3436;">
        🗺️ Tour multi-giorno
      </h2>
      <p style="margin:0;font-size:14px;color:#4a5560;">
        Crea cammini di più giorni unendo le tue tracce: foto di copertina,
        gallery, descrizione strutturata, periodo migliore, difficoltà,
        e rifugio dove pernotti per ogni tappa. Distingue cammini consecutivi
        (es. Alta Via) da collezioni tematiche (es. "le più belle della
        Valle Seriana"). Pubblicabili anche sulla community.
      </p>
    </div>

    <!-- News 2: AR Recognition -->
    <div style="margin:24px 0;padding:18px;background:#f5f9fe;border-left:4px solid #4a90d9;border-radius:6px;">
      <h2 style="margin:0 0 8px;font-size:18px;color:#2d3436;">
        📸 Riconosci le cime con la fotocamera
      </h2>
      <p style="margin:0;font-size:14px;color:#4a5560;">
        Inquadra le montagne intorno a te: TrailShare riconosce automaticamente
        le cime visibili sovrapponendo nomi e quote in tempo reale. Dataset
        di 37.000+ cime italiane già bundlato nell'app (funziona anche offline).
        AR Photo Mode con foto annotate per gli abbonati Pro.
      </p>
    </div>

    <!-- News 3: Lifeline + LiveTrack -->
    <div style="margin:24px 0;padding:18px;background:#f3faf5;border-left:4px solid #5cb47e;border-radius:6px;">
      <h2 style="margin:0 0 8px;font-size:18px;color:#2d3436;">
        🛟 Lifeline e LiveTrack — sicurezza in montagna
      </h2>
      <p style="margin:0;font-size:14px;color:#4a5560;">
        Imposta fino a 3 contatti di emergenza che ricevono un link
        personalizzato con la tua posizione live durante l'attività.
        In caso di inattività prolungata o SOS manuale, Lifeline prepara
        messaggi precompilati pronti da inviare. LiveTrack condivide la
        posizione live con chiunque tu voglia, via link.
        <br><br>
        <em style="color:#8392a5;">Limiti: non è un servizio di emergenza,
        serve copertura cellulare. Per il 112 c'è il tasto dedicato.</em>
      </p>
    </div>

    <p style="margin:24px 0 16px;font-size:15px;">
      Se l'app ti aveva deluso quando l'hai provata, oggi è davvero un'altra
      cosa. Dacci un'altra occasione 🙂
    </p>

    <!-- CTA -->
    <div style="text-align:center;margin:28px 0;">
      <a href="https://trailshare.app/#download"
         style="display:inline-block;background:#E07B4C;color:#ffffff;
                padding:14px 32px;text-decoration:none;border-radius:10px;
                font-weight:700;font-size:15px;">
        Aggiorna l'app o scaricala di nuovo
      </a>
    </div>

    <p style="margin:20px 0 0;font-size:14px;color:#4a5560;">
      Per qualsiasi cosa puoi rispondere direttamente a questa email, oppure
      scrivere a <a href="mailto:info@trailshare.app" style="color:#E07B4C;">info@trailshare.app</a>.
    </p>

    <p style="margin:16px 0 0;font-size:14px;">
      Buoni sentieri,<br>
      <strong>Massimiliano</strong><br>
      <span style="color:#8392a5;font-size:13px;">TrailShare</span>
    </p>

  </div>

  <!-- Footer -->
  <div style="padding:20px 24px;background:#f8f7f4;border-top:1px solid #e4e2dd;font-size:11px;color:#8392a5;line-height:1.5;">
    <p style="margin:0 0 8px;">
      Ricevi questa email perché sei un utente registrato di TrailShare.
      Te la mandiamo per informarti delle novità rilevanti del servizio,
      sulla base del nostro
      <a href="https://trailshare.app/privacy#comunicazioni" style="color:#8392a5;text-decoration:underline;">legittimo interesse (art. 6.1.f GDPR)</a>
      a tenerti aggiornato. Le email transazionali continueranno comunque.
    </p>
    <p style="margin:0;">
      <a href="${unsubUrl}" style="color:#8392a5;text-decoration:underline;">Annulla iscrizione</a>
      &nbsp;·&nbsp;
      <a href="https://trailshare.app/privacy" style="color:#8392a5;text-decoration:underline;">Privacy</a>
      &nbsp;·&nbsp;
      <a href="mailto:privacy@trailshare.app" style="color:#8392a5;text-decoration:underline;">privacy@trailshare.app</a>
    </p>
  </div>

</div>
</body>
</html>
  `;
}

/// Endpoint pubblico HTTPS: utente clicca "Annulla iscrizione" → marca
/// opt-out su user_profiles/{uid}, ritorna pagina HTML di conferma.
/// Verifica HMAC: ?uid=...&t=...
exports.unsubscribeNewsletter = onRequest(
  { region: 'europe-west3', cors: true, timeoutSeconds: 15 },
  async (req, res) => {
    const uid = (req.query.uid || '').toString();
    const token = (req.query.t || '').toString();
    if (!uid || !token) {
      res.status(400).send('Missing uid or token');
      return;
    }
    if (token !== _newsletterUnsubToken(uid)) {
      res.status(403).send('Invalid unsubscribe token');
      return;
    }
    try {
      await db.collection('user_profiles').doc(uid).set({
        marketingOptOut: true,
        marketingOptOutAt: admin.firestore.FieldValue.serverTimestamp(),
        marketingOptOutSource: 'newsletter_link',
      }, { merge: true });
      logger.info(`[unsubscribeNewsletter] opt-out registered for ${uid}`);
    } catch (e) {
      logger.error('[unsubscribeNewsletter] write error:', e.message);
      res.status(500).send('Errore tecnico. Scrivi a privacy@trailshare.app.');
      return;
    }
    res.set('Content-Type', 'text/html; charset=utf-8');
    res.send(`<!DOCTYPE html><html lang="it"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Disiscritto — TrailShare</title>
<link rel="icon" type="image/png" href="https://trailshare.app/images/app-icon.png">
</head><body style="margin:0;padding:48px 20px;background:#f5f4f1;font-family:'Helvetica Neue',Arial,sans-serif;color:#2d3436;text-align:center;">
<div style="max-width:480px;margin:0 auto;background:#fff;padding:40px 28px;border-radius:14px;box-shadow:0 4px 24px rgba(0,0,0,.06);">
  <div style="font-size:48px;margin-bottom:12px;">✅</div>
  <h1 style="margin:0 0 12px;font-size:22px;">Ti abbiamo disiscritto.</h1>
  <p style="margin:0 0 16px;color:#4a5560;line-height:1.5;">
    Non riceverai più email di aggiornamento prodotto da TrailShare.
    Le email transazionali indispensabili al servizio (sicurezza account,
    conferme di azioni) continueranno a essere inviate.
  </p>
  <p style="margin:24px 0 0;font-size:13px;color:#8392a5;">
    Se hai cambiato idea, scrivici a
    <a href="mailto:privacy@trailshare.app" style="color:#E07B4C;">privacy@trailshare.app</a>.
  </p>
  <a href="https://trailshare.app" style="display:inline-block;margin-top:28px;color:#E07B4C;text-decoration:none;font-weight:600;">
    ← Torna a trailshare.app
  </a>
</div>
</body></html>`);
  }
);

/// Conta destinatari della prossima campagna newsletter e ritorna 5
/// sample (senza inviare). Admin only.
exports.previewNewsletterBatch = onCall(
  { region: 'europe-west3', timeoutSeconds: 60 },
  async (request) => {
    if (!(await _isCallerAdmin(request.auth))) {
      throw new functions.https.HttpsError(
        'permission-denied', 'Solo admin platform.'
      );
    }
    const { campaignId } = request.data || {};
    if (!campaignId || typeof campaignId !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument', 'campaignId richiesto (es. "v2.5.1-launch").'
      );
    }
    // Lista utenti Firebase Auth (paginata, fino a 5000 per il preview).
    // Per project con >5000 utenti aggiungere paginazione completa.
    const all = [];
    let nextPageToken;
    do {
      const page = await admin.auth().listUsers(1000, nextPageToken);
      all.push(...page.users);
      nextPageToken = page.pageToken;
    } while (nextPageToken && all.length < 5000);

    // Filtra: email valida + non opt-out + non già contattati per
    // questa campagna.
    const eligible = [];
    let skipNoEmail = 0, skipOptOut = 0, skipAlreadySent = 0, skipDisabled = 0;
    for (const u of all) {
      if (u.disabled) { skipDisabled++; continue; }
      if (!u.email || !u.emailVerified) { skipNoEmail++; continue; }
      const profileSnap = await db.collection('user_profiles').doc(u.uid).get();
      const p = profileSnap.exists ? profileSnap.data() : {};
      if (p.marketingOptOut === true) { skipOptOut++; continue; }
      if (p.newsletterLastSentCampaign === campaignId) { skipAlreadySent++; continue; }
      eligible.push({
        uid: u.uid,
        email: u.email,
        displayName: u.displayName || p.displayName || '',
        createdAt: u.metadata.creationTime,
        lastSignIn: u.metadata.lastSignInTime,
      });
    }
    const samples = eligible.slice(0, 5);
    return {
      campaignId,
      totalAuthUsers: all.length,
      eligible: eligible.length,
      skipped: {
        noEmail: skipNoEmail,
        optOut: skipOptOut,
        alreadySent: skipAlreadySent,
        disabled: skipDisabled,
      },
      samples,
    };
  }
);

/// Invia un batch della newsletter. Admin only. Cap di sicurezza.
exports.sendNewsletterBatch = onCall(
  { region: 'europe-west3', timeoutSeconds: 540, memory: '512MiB' },
  async (request) => {
    if (!(await _isCallerAdmin(request.auth))) {
      throw new functions.https.HttpsError(
        'permission-denied', 'Solo admin platform.'
      );
    }
    const {
      campaignId,
      subject,
      maxEmails,
      dryRun,
      testEmail, // se valorizzato → invia solo a quest'indirizzo, salta Auth/dedup
    } = request.data || {};
    if (!campaignId || typeof campaignId !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument', 'campaignId richiesto.'
      );
    }
    const cap = Math.min(Math.max(parseInt(maxEmails) || 50, 1), 500);
    const finalSubject = (subject && typeof subject === 'string' && subject.trim())
      ? subject.trim()
      : 'TrailShare è cresciuto. Le novità che ti sei perso.';

    // ─── Modalità TEST: invio singolo a un indirizzo specifico ──────
    // Non legge Auth, non aggiorna user_profiles, non rispetta dedup.
    // Usato per controllare il rendering del template prima del rollout.
    if (testEmail && typeof testEmail === 'string') {
      const email = testEmail.trim();
      if (!email.match(/^[^@\s]+@[^@\s]+\.[^@\s]+$/)) {
        throw new functions.https.HttpsError(
          'invalid-argument', 'testEmail non valida.'
        );
      }
      const html = _buildNewsletterHtml('Massimiliano',
        _newsletterUnsubUrl('TEST-USER-UID-NOT-REAL'));
      const subjectWithTag = `[TEST] ${finalSubject}`;
      if (!dryRun) {
        await db.collection('mail').add({
          to: [email],
          message: {
            subject: subjectWithTag,
            html,
            text: _htmlToPlainText(html),
          },
          replyTo: 'info@trailshare.app',
        });
      }
      logger.info(`[sendNewsletterBatch] TEST mode → ${email} dryRun=${!!dryRun}`);
      return {
        success: true,
        testMode: true,
        testEmail: email,
        dryRun: !!dryRun,
        sent: dryRun ? 0 : 1,
        skipped: 0,
        errors: [],
      };
    }

    // Lista utenti Auth con paginazione.
    const all = [];
    let nextPageToken;
    do {
      const page = await admin.auth().listUsers(1000, nextPageToken);
      all.push(...page.users);
      nextPageToken = page.pageToken;
    } while (nextPageToken);

    let sent = 0;
    let skipped = 0;
    const errors = [];

    for (const u of all) {
      if (sent >= cap) break;
      if (u.disabled || !u.email || !u.emailVerified) { skipped++; continue; }
      try {
        const profileRef = db.collection('user_profiles').doc(u.uid);
        const profileSnap = await profileRef.get();
        const p = profileSnap.exists ? profileSnap.data() : {};
        if (p.marketingOptOut === true) { skipped++; continue; }
        if (p.newsletterLastSentCampaign === campaignId) { skipped++; continue; }

        if (dryRun) {
          sent++;
          continue;
        }

        const displayName = u.displayName || p.displayName || '';
        const unsubUrl = _newsletterUnsubUrl(u.uid);
        const html = _buildNewsletterHtml(displayName, unsubUrl);

        const batch = db.batch();
        batch.set(db.collection('mail').doc(), {
          to: [u.email],
          message: { subject: finalSubject, html, text: _htmlToPlainText(html) },
          replyTo: 'info@trailshare.app',
        });
        batch.set(profileRef, {
          newsletterLastSentAt: admin.firestore.FieldValue.serverTimestamp(),
          newsletterLastSentCampaign: campaignId,
        }, { merge: true });
        await batch.commit();
        sent++;
      } catch (e) {
        logger.warn(`[sendNewsletterBatch] error on ${u.uid}: ${e.message}`);
        errors.push({ uid: u.uid, email: u.email, error: e.message });
      }
    }

    logger.info(
      `[sendNewsletterBatch] campaign=${campaignId} dryRun=${!!dryRun} ` +
      `total=${all.length} sent=${sent} skipped=${skipped} errors=${errors.length}`
    );
    return {
      success: true,
      campaignId,
      dryRun: !!dryRun,
      totalAuthUsers: all.length,
      cap,
      sent,
      skipped,
      errors,
    };
  }
);

// ===================================================================
// SURFACE PROFILE — Enrichment public_trails con terrainSegments (K1b)
// ===================================================================
// Cloud Function batch che pre-elabora i tag OSM way per ogni public_trail
// (relation OSM via Waymarked Trails) e denormalizza un array di
// TerrainSegment in public_trail_geometries/{trailId}.terrainSegments.
//
// Pattern: come il pre-import POI Mountain Finder (statico, refresh
// periodico) — niente Overpass live dal client. Vantaggio: offline,
// veloce, niente rate-limit lato utente.
//
// Funzioni:
// - enrichTrailWithTerrain({trailId}) — onCall admin, singolo trail
// - enrichAllTrailsTerrain({maxTrails, dryRun}) — onCall admin, batch
//
// Algoritmo per singolo trail:
// 1. Estrae osmRelationId dall'id Firestore (formato "wmt_relation_<id>")
// 2. Query Overpass: relation + way members + tutti i nodi
// 3. Per ogni way, applica logica equivalente a parseTerrainFromOsmTags
//    (replicata server-side per evitare import dart→js)
// 4. Carica coordinatesJson da public_trail_geometries/{trailId}
// 5. Per ogni TrackPoint, trova la way più vicina (matching nodo)
// 6. Comprime TrackPoint consecutivi con stesso TerrainType in segmenti
// 7. Update terrainSegments array sul doc geometria

// Mirror Overpass in ordine di velocità tipica. Failover automatico:
// se il primario va in timeout/429, prova il secondario.
// openstreetmap.fr rimosso: ritorna sempre 403 dalla Cloud Function
// (probabile blocco IP/UA).
const _OVERPASS_ENDPOINTS = [
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass-api.de/api/interpreter',
];

// User-Agent richiesto dalla policy Overpass (best practice).
const _OVERPASS_HEADERS = {
  'Content-Type': 'text/plain',
  'User-Agent': 'TrailShare/2.5.1 (info@trailshare.app) — terrain enrichment K1b',
};

/// Replica server-side di parseTerrainFromOsmTags() — TENERLA SINCRONIZZATA
/// con lib/data/models/terrain_segment.dart. Funzione pura.
function _parseTerrainFromOsmTags(tags) {
  const g = (k) => {
    const v = tags[k];
    if (v == null) return null;
    const t = String(v).trim().toLowerCase();
    return t.length === 0 ? null : t;
  };
  const highway = g('highway');
  if (highway === 'via_ferrata' || tags['via_ferrata_scale'] || g('climbing') === 'via_ferrata') {
    return 'via_ferrata';
  }
  const surface = g('surface');
  const sacScale = g('sac_scale');
  const tracktype = g('tracktype');
  const rockySurfaces = new Set(['rock', 'rocks', 'scree', 'pebblestone', 'stone']);
  const alpineSacScales = new Set(['alpine_hiking', 'demanding_alpine_hiking', 'difficult_alpine_hiking']);
  if (surface && rockySurfaces.has(surface)) return 'rocky';
  if (sacScale && alpineSacScales.has(sacScale)) return 'rocky';
  const asphaltSurfaces = new Set(['asphalt', 'paved', 'concrete', 'paving_stones', 'sett', 'cobblestone']);
  const asphaltHighways = new Set([
    'primary', 'secondary', 'tertiary', 'unclassified',
    'residential', 'service', 'cycleway', 'living_street',
  ]);
  if (surface && asphaltSurfaces.has(surface)) return 'asphalt';
  if (highway && asphaltHighways.has(highway)) return 'asphalt';
  const gravelSurfaces = new Set(['gravel', 'fine_gravel', 'dirt', 'earth', 'ground', 'unpaved', 'compacted']);
  if (surface && gravelSurfaces.has(surface)) return 'gravel';
  if (highway === 'track') {
    if (tracktype === 'grade1' || tracktype === 'grade2' || tracktype === 'grade3') return 'gravel';
    if (tracktype === 'grade4' || tracktype === 'grade5') return 'path';
    return 'gravel';
  }
  if (highway === 'path' || highway === 'footway' || highway === 'bridleway') return 'path';
  if (sacScale === 'hiking' || sacScale === 'mountain_hiking') return 'path';
  return 'unknown';
}

/// Haversine tra due coordinate (gradi → metri).
function _haversineMeters(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const toRad = (d) => d * Math.PI / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

/// Estrae l'osmRelationId dall'id documento. Format atteso:
/// "wmt_relation_<id>" → ritorna <id> come numero. null se non matcha.
function _extractOsmRelationId(trailDocId) {
  const m = /^wmt_relation_(\d+)$/.exec(trailDocId);
  return m ? parseInt(m[1], 10) : null;
}

/// Costruisce il query string Overpass QL per una relation.
/// `out tags geom` ritorna le way con tags + geometry inline (lat/lon
/// per ogni nodo), evitando di scaricare i nodi separatamente con
/// `(._;>;)`. Significativamente più veloce e ~50% meno payload.
function _buildOverpassRelationQuery(relationId) {
  return `[out:json][timeout:180];relation(${relationId});way(r);out tags geom;`;
}

/// Esegue la query con failover automatico sui mirror Overpass.
/// Ritorna gli elements; lancia errore se TUTTI i mirror falliscono.
/// Su 429 (rate limit) ritenta dopo 5s sullo stesso mirror una volta
/// prima di passare al successivo.
async function _overpassQueryWithFailover(query) {
  let lastError;
  for (const endpoint of _OVERPASS_ENDPOINTS) {
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const resp = await axios.post(endpoint, query, {
          headers: _OVERPASS_HEADERS,
          timeout: 60000, // 60s client-side, server-side timeout:180 nel QL
        });
        return resp.data?.elements || [];
      } catch (e) {
        lastError = e;
        const status = e.response?.status;
        if (status === 429 && attempt === 0) {
          logger.warn(`[K1b] ${endpoint} → 429, sleep 5s + retry`);
          await new Promise((r) => setTimeout(r, 5000));
          continue;
        }
        logger.warn(`[K1b] ${endpoint} → ${e.message}, next mirror`);
        break;
      }
    }
  }
  throw lastError || new Error('Tutti i mirror Overpass hanno fallito');
}

/// Calcola terrainSegments per un singolo trail.
/// Ritorna {segments, stats} oppure null se i dati sono insufficienti.
async function _computeTerrainSegments(trailDocId) {
  const relationId = _extractOsmRelationId(trailDocId);
  if (relationId == null) {
    logger.warn(`[K1b] Trail ${trailDocId} non ha id wmt_relation_<id>, skip`);
    return null;
  }

  // 1. Carica geometria
  const geoDoc = await db.collection('public_trail_geometries').doc(trailDocId).get();
  if (!geoDoc.exists) {
    logger.warn(`[K1b] Geometria assente per ${trailDocId}`);
    return null;
  }
  const coordsJsonStr = geoDoc.data().coordinatesJson;
  if (!coordsJsonStr || typeof coordsJsonStr !== 'string') return null;
  let coordsList;
  try {
    coordsList = JSON.parse(coordsJsonStr);
  } catch (e) {
    logger.warn(`[K1b] coordinatesJson malformato per ${trailDocId}: ${e.message}`);
    return null;
  }
  if (!Array.isArray(coordsList) || coordsList.length < 2) return null;
  // Punti come [lng, lat, ele?] — schema esistente
  const points = coordsList
    .filter((p) => Array.isArray(p) && p.length >= 2)
    .map((p) => ({ lng: p[0], lat: p[1] }));
  if (points.length < 2) return null;

  // 2. Query Overpass con failover automatico tra mirror
  const query = _buildOverpassRelationQuery(relationId);
  let elements;
  try {
    elements = await _overpassQueryWithFailover(query);
  } catch (e) {
    logger.error(`[K1b] Overpass tutti i mirror falliti per relation ${relationId}: ${e.message}`);
    return null;
  }

  // 3. Schema "out tags geom": ogni way ha tags + geometry inline
  //    (array di {lat, lon} per ogni nodo della way). Niente fetch
  //    separato dei nodi.
  const ways = []; // {nodes: [{lat,lng}], terrain: TerrainType}
  for (const el of elements) {
    if (el.type === 'way') {
      const tags = el.tags || {};
      const terrain = _parseTerrainFromOsmTags(tags);
      const geom = el.geometry || [];
      const wayNodes = geom
        .filter((g) => typeof g.lat === 'number' && typeof g.lon === 'number')
        .map((g) => ({ lat: g.lat, lng: g.lon }));
      if (wayNodes.length > 0) {
        ways.push({ nodes: wayNodes, terrain });
      }
    }
  }
  if (ways.length === 0) {
    logger.warn(`[K1b] Nessuna way per relation ${relationId}`);
    return null;
  }

  // 4. Per ogni TrackPoint, assegna terrain della way più vicina
  const pointTerrains = new Array(points.length);
  for (let i = 0; i < points.length; i++) {
    const p = points[i];
    let bestTerrain = 'unknown';
    let bestDist = Infinity;
    for (const w of ways) {
      for (const n of w.nodes) {
        const d = _haversineMeters(p.lat, p.lng, n.lat, n.lng);
        if (d < bestDist) {
          bestDist = d;
          bestTerrain = w.terrain;
        }
        if (bestDist < 5) break; // Hot path: < 5m è già match esatto
      }
      if (bestDist < 5) break;
    }
    // Se il nodo più vicino è > 100m è probabile noise, fallback unknown
    pointTerrains[i] = bestDist > 100 ? 'unknown' : bestTerrain;
  }

  // 5. Comprime indici consecutivi con stesso terrain
  const segments = [];
  let segStart = 0;
  for (let i = 1; i <= points.length; i++) {
    if (i === points.length || pointTerrains[i] !== pointTerrains[segStart]) {
      segments.push({
        startIdx: segStart,
        endIdx: i - 1,
        type: pointTerrains[segStart],
      });
      segStart = i;
    }
  }

  // 6. Smoothing: unisce segmenti di <= 2 punti col vicino dominante
  const smoothed = [];
  for (const seg of segments) {
    const len = seg.endIdx - seg.startIdx + 1;
    if (len <= 2 && smoothed.length > 0) {
      smoothed[smoothed.length - 1].endIdx = seg.endIdx;
    } else if (len <= 2 && smoothed.length === 0 && segments.length > 1) {
      // Primo seg corto: posticipa decisione, unisce col successivo dopo
      smoothed.push({ ...seg });
    } else {
      smoothed.push({ ...seg });
    }
  }
  // Secondo pass: merge segmenti consecutivi con stesso type
  const merged = [];
  for (const seg of smoothed) {
    if (merged.length > 0 && merged[merged.length - 1].type === seg.type) {
      merged[merged.length - 1].endIdx = seg.endIdx;
    } else {
      merged.push(seg);
    }
  }

  return {
    segments: merged,
    stats: {
      totalPoints: points.length,
      waysAnalyzed: ways.length,
      segmentCount: merged.length,
      typesFound: [...new Set(merged.map((s) => s.type))],
    },
  };
}

exports.enrichTrailWithTerrain = onCall(
  { region: 'europe-west3', timeoutSeconds: 120, memory: '512MiB' },
  async (request) => {
    if (!(await _isCallerAdmin(request.auth))) {
      throw new functions.https.HttpsError(
        'permission-denied', 'Solo admin platform.'
      );
    }
    const { trailId, dryRun } = request.data || {};
    if (!trailId || typeof trailId !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument', 'trailId richiesto.'
      );
    }
    const result = await _computeTerrainSegments(trailId);
    if (!result) {
      return { success: false, reason: 'no-data-or-invalid' };
    }
    if (!dryRun) {
      await db.collection('public_trail_geometries').doc(trailId).set({
        terrainSegments: result.segments,
        terrainEnrichedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    logger.info(
      `[K1b] enrichTrailWithTerrain trail=${trailId} segments=${result.segments.length} ` +
      `types=${result.stats.typesFound.join(',')} dryRun=${!!dryRun}`
    );
    return {
      success: true,
      trailId,
      dryRun: !!dryRun,
      ...result.stats,
    };
  }
);

exports.enrichAllTrailsTerrain = onCall(
  { region: 'europe-west3', timeoutSeconds: 540, memory: '512MiB' },
  async (request) => {
    if (!(await _isCallerAdmin(request.auth))) {
      throw new functions.https.HttpsError(
        'permission-denied', 'Solo admin platform.'
      );
    }
    const { maxTrails, dryRun, skipAlreadyEnriched } = request.data || {};
    // Cap hard a 25 per batch per stare ben sotto il timeout function
    // di 540s. Per processare molti trail, il client ri-chiama in loop
    // sfruttando skipAlreadyEnriched come dedup.
    const cap = Math.min(Math.max(parseInt(maxTrails) || 20, 1), 25);

    // Pesca trail ids candidati. Filtro lato Firestore impossibile per
    // "non ha terrainEnrichedAt" senza creare index → fetch + filter.
    const snap = await db.collection('public_trail_geometries')
      .limit(cap * 3) // overscan per compensare gli skip
      .get();

    let processed = 0, enriched = 0, skipped = 0;
    const errors = [];
    const samples = [];
    for (const doc of snap.docs) {
      if (enriched >= cap) break;
      if (skipAlreadyEnriched !== false && doc.data().terrainEnrichedAt) {
        skipped++;
        continue;
      }
      processed++;
      try {
        const result = await _computeTerrainSegments(doc.id);
        if (!result) {
          skipped++;
          continue;
        }
        if (!dryRun) {
          await db.collection('public_trail_geometries').doc(doc.id).set({
            terrainSegments: result.segments,
            terrainEnrichedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        }
        enriched++;
        if (samples.length < 5) {
          samples.push({
            trailId: doc.id,
            segments: result.segments.length,
            types: result.stats.typesFound,
          });
        }
        // Rate limit Overpass: kumi.systems da 429 sotto i 3s — usiamo
        // 3.5s di margine per non beccarli.
        await new Promise((r) => setTimeout(r, 3500));
      } catch (e) {
        errors.push({ trailId: doc.id, error: e.message });
      }
    }
    logger.info(
      `[K1b] enrichAllTrailsTerrain processed=${processed} enriched=${enriched} ` +
      `skipped=${skipped} errors=${errors.length} dryRun=${!!dryRun}`
    );
    return {
      success: true,
      dryRun: !!dryRun,
      processed,
      enriched,
      skipped,
      errors: errors.slice(0, 10),
      samples,
    };
  }
);

exports.staticMapProxy = onRequest(
  { region: "europe-west3", cors: true, timeoutSeconds: 30 },
  async (req, res) => {
    try {
      const { lat, lng, markers } = req.query;
      if (!lat || !lng) {
        res.status(400).send('Missing lat/lng');
        return;
      }
      const MAPTILER_KEY = 'EagFyuDbTNmVOAX1zlbz';
      let url = `https://api.maptiler.com/maps/streets-v2/static/auto/640x300.png?key=${MAPTILER_KEY}&padding=40`;
      if (markers && typeof markers === 'string' && markers.length > 0) {
        url += `&markers=${encodeURIComponent(markers)}`;
      }
      const resp = await axios.get(url, {
        responseType: 'arraybuffer',
        timeout: 20000,
        headers: {
          'User-Agent': 'TrailShareApp',
          'Referer': 'https://trailshare.app',
        },
      });
      res.set('Content-Type', 'image/png');
      res.set('Cache-Control', 'public, max-age=604800'); // 7 giorni
      res.send(Buffer.from(resp.data));
    } catch (e) {
      logger.error('[staticMapProxy] error:', e.message);
      res.status(500).send(`MapTiler error: ${e.message}`);
    }
  }
);
