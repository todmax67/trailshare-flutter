// File: functions/index.js (VERSIONE CORRETTA E COMPLETA)

const { onDocumentCreated, onDocumentUpdated, onDocumentDeleted } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");
const { onCall, onRequest } = require("firebase-functions/v2/https");
const functions = require("firebase-functions");
const { logger } = require("firebase-functions");
const { defineSecret } = require('firebase-functions/params');
const { GeoPoint } = require("firebase-admin/firestore");
const axios = require('axios');
admin.initializeApp();
const db = admin.firestore();
const storage = admin.storage();
setGlobalOptions({ region: "europe-west3" });
const orsApiKey = defineSecret('ORS_API_KEY');

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

    tracksSnapshot.forEach(doc => {
        try {
            const track = doc.data();
            if (!track) return;

            // --- Statistiche Totali (su tutte le tracce) ---
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
        totalTracks: tracksSnapshot.size,
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
        'https://trailshare.app', // Produzione
        'https://localhost',     // Sviluppo Capacitor/Web HTTPS
        'http://localhost',       // Sviluppo Capacitor/Web HTTP
        'capacitor://localhost'
    ];
    const origin = req.headers.origin;

    if (allowedOrigins.includes(origin)) {
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
            isPublic: false, duration: 0, waypoints: [], photos: [],
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