import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { GoogleGenerativeAI } from "@google/generative-ai";

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

// ============================================================
// 1. NOTIFY OWNER: When a new appointment is created
// ============================================================
export const onNewAppointment = functions.firestore
    .document("appointments/{appointmentId}")
    .onCreate(async (snap) => {
        const appointment = snap.data();
        const salonId: string = appointment.salonId;
        const serviceName: string = appointment.serviceName || "Service";
        const salonName: string = appointment.salonName || "Salon";

        try {
            // Get salon to find the owner
            const salonDoc = await db.collection("salons").doc(salonId).get();
            if (!salonDoc.exists) {
                console.log(`Salon ${salonId} not found, skipping notification.`);
                return;
            }

            const ownerId: string = salonDoc.data()?.ownerId;
            if (!ownerId) return;

            // Get owner's FCM token
            const ownerDoc = await db.collection("users").doc(ownerId).get();
            const fcmToken: string | undefined = ownerDoc.data()?.fcmToken;

            if (!fcmToken) {
                console.log(`No FCM token for owner ${ownerId}, skipping.`);
                return;
            }

            // Get owner's language preference
            const ownerLang: string = ownerDoc.data()?.lang || "fr";
            const isEn = ownerLang === "en";

            // Format date
            const dateTime = appointment.dateTime?.toDate
                ? appointment.dateTime.toDate()
                : new Date(appointment.dateTime);
            const dateLocale = isEn ? "en-US" : "fr-FR";
            const dateStr = dateTime.toLocaleDateString(dateLocale, {
                day: "2-digit",
                month: "long",
                year: "numeric",
            });
            const timeStr = dateTime.toLocaleTimeString(dateLocale, {
                hour: "2-digit",
                minute: "2-digit",
            });

            const notifTitle = isEn ? "New Booking! 🎉" : "Nouvelle Réservation ! 🎉";
            const notifBody = isEn
                ? `${serviceName} - ${salonName} on ${dateStr} at ${timeStr}`
                : `${serviceName} - ${salonName} le ${dateStr} à ${timeStr}`;

            // Save in-app notification for the owner
            await db.collection("notifications").add({
                userId: ownerId,
                title: notifTitle,
                body: notifBody,
                type: "new_appointment",
                isRead: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Send push notification to the salon owner
            await messaging.send({
                token: fcmToken,
                notification: {
                    title: notifTitle,
                    body: notifBody,
                },
                data: {
                    type: "new_appointment",
                    appointmentId: snap.id,
                    salonId: salonId,
                },
                android: {
                    priority: "high",
                    notification: {
                        channelId: "mon_salon_channel",
                        sound: "default",
                    },
                },
                apns: {
                    payload: {
                        aps: {
                            sound: "default",
                            badge: 1,
                        },
                    },
                },
            });

            console.log(`✅ Notification sent to owner ${ownerId} for appointment ${snap.id}`);
        } catch (error) {
            console.error("Error sending new appointment notification:", error);
        }
    });

// ============================================================
// 2. NOTIFY CLIENT: When an appointment status is changed
//    (e.g., cancelled by owner, confirmed, etc.)
// ============================================================
export const onAppointmentStatusChanged = functions.firestore
    .document("appointments/{appointmentId}")
    .onUpdate(async (change) => {
        const before = change.before.data();
        const after = change.after.data();

        // Only trigger if the status actually changed
        if (before.status === after.status) return;

        const clientId: string = after.clientId;
        const newStatus: string = after.status;
        const salonId: string = after.salonId;
        const salonName: string = after.salonName || "Salon";
        const serviceName: string = after.serviceName || "Service";

        // ── Notify waitlist on cancellation ──────────────────────────────
        if (newStatus === "cancelled" && salonId) {
            try {
                const appointmentDate = after.dateTime?.toDate
                    ? after.dateTime.toDate()
                    : new Date(after.dateTime);
                const startOfDay = new Date(
                    appointmentDate.getFullYear(),
                    appointmentDate.getMonth(),
                    appointmentDate.getDate()
                );
                const endOfDay = new Date(startOfDay.getTime() + 24 * 60 * 60 * 1000);

                const waitlistSnap = await db
                    .collection("waitlist")
                    .where("salonId", "==", salonId)
                    .where("notified", "==", false)
                    .get();

                const matchingEntries = waitlistSnap.docs.filter((doc) => {
                    const desiredDate = doc.data().desiredDate?.toDate
                        ? doc.data().desiredDate.toDate()
                        : new Date(doc.data().desiredDate);
                    return desiredDate >= startOfDay && desiredDate < endOfDay;
                });

                for (const entry of matchingEntries) {
                    const entryData = entry.data();
                    const waitlistClientId: string = entryData.clientId;

                    // Mark as notified
                    await entry.ref.update({ notified: true });

                    // Get waitlist client doc (for lang + FCM token)
                    const wClientDoc = await db.collection("users").doc(waitlistClientId).get();

                    // Get waitlist client's language
                    const wLang: string = wClientDoc.data()?.lang || "fr";
                    const wIsEn = wLang === "en";
                    const wDateStr = appointmentDate.toLocaleDateString(wIsEn ? "en-US" : "fr-FR", { day: "2-digit", month: "long" });

                    // Save in-app notification
                    await db.collection("notifications").add({
                        userId: waitlistClientId,
                        title: wIsEn ? `Slot available at ${salonName}!` : `Créneau disponible chez ${salonName} !`,
                        body: wIsEn ? `A slot opened up on ${wDateStr}. Book now!` : `Un créneau s'est libéré pour le ${wDateStr}. Réservez vite !`,
                        type: "waitlist",
                        isRead: false,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        salonId: salonId,
                    });

                    // Send FCM push (wClientDoc already fetched above for lang)
                    const wToken: string | undefined = wClientDoc.data()?.fcmToken;
                    if (wToken) {
                        await messaging.send({
                            token: wToken,
                            notification: {
                                title: wIsEn ? "Slot available! 🎉" : "Créneau disponible ! 🎉",
                                body: wIsEn ? `A slot opened up at ${salonName}. Book now!` : `Un créneau s'est libéré chez ${salonName}. Réservez maintenant !`,
                            },
                            data: {
                                type: "waitlist_available",
                                salonId: salonId,
                            },
                            android: {
                                priority: "high",
                                notification: {
                                    channelId: "mon_salon_channel",
                                    sound: "default",
                                },
                            },
                            apns: {
                                payload: {
                                    aps: {
                                        sound: "default",
                                        badge: 1,
                                    },
                                },
                            },
                        });
                    }

                    console.log(`✅ Waitlist notification sent to ${waitlistClientId}`);
                }
            } catch (waitlistError) {
                console.error("Error notifying waitlist:", waitlistError);
            }
        }

        try {
            // Get client's FCM token and language
            const clientDoc = await db.collection("users").doc(clientId).get();
            const fcmToken: string | undefined = clientDoc.data()?.fcmToken;
            const clientLang: string = clientDoc.data()?.lang || "fr";
            const isEn = clientLang === "en";

            if (!fcmToken) {
                console.log(`No FCM token for client ${clientId}, skipping.`);
                return;
            }

            // Build notification based on status
            let title = "";
            let body = "";

            switch (newStatus) {
                case "cancelled":
                    title = isEn ? "Appointment Cancelled ❌" : "Rendez-vous Annulé ❌";
                    body = isEn
                        ? `Your appointment "${serviceName}" at ${salonName} has been cancelled.`
                        : `Votre RDV "${serviceName}" chez ${salonName} a été annulé.`;
                    break;
                case "confirmed":
                    title = isEn ? "Appointment Confirmed ✅" : "Rendez-vous Confirmé ✅";
                    body = isEn
                        ? `Your appointment "${serviceName}" at ${salonName} is confirmed!`
                        : `Votre RDV "${serviceName}" chez ${salonName} est confirmé !`;
                    break;
                case "completed":
                    title = isEn ? "Appointment Completed 🌟" : "Rendez-vous Terminé 🌟";
                    body = isEn
                        ? `Thank you for visiting ${salonName}! Leave a review.`
                        : `Merci pour votre visite chez ${salonName} ! Laissez un avis.`;
                    break;
                default:
                    console.log(`Unknown status "${newStatus}", skipping notification.`);
                    return;
            }

            await messaging.send({
                token: fcmToken,
                notification: { title, body },
                data: {
                    type: "status_change",
                    appointmentId: change.after.id,
                    newStatus: newStatus,
                },
                android: {
                    priority: "high",
                    notification: {
                        channelId: "mon_salon_channel",
                        sound: "default",
                    },
                },
                apns: {
                    payload: {
                        aps: {
                            sound: "default",
                            badge: 1,
                        },
                    },
                },
            });

            console.log(`✅ Status change notification sent to client ${clientId}`);
        } catch (error) {
            console.error("Error sending status change notification:", error);
        }
    });

// ============================================================
// 3. NOTIFY ON NEW MESSAGE: When a message is sent in a conversation
//    - Sender is client  → notify the salon owner
//    - Sender is owner   → notify the client
// ============================================================
export const onNewMessage = functions.firestore
    .document("conversations/{convId}/messages/{msgId}")
    .onCreate(async (snap, context) => {
        const message = snap.data();
        const senderId: string = message.senderId;
        const text: string = message.text || "Nouveau message";
        const convId: string = context.params.convId;

        try {
            // Load the parent conversation document
            const convDoc = await db.collection("conversations").doc(convId).get();
            if (!convDoc.exists) return;

            const conv = convDoc.data()!;
            const clientId: string = conv.clientId;
            const ownerId: string = conv.ownerId;
            const salonName: string = conv.salonName || "Salon";
            const clientName: string = conv.clientName || "Client";

            const senderIsClient = senderId === clientId;

            // Determine recipient: the OTHER party
            const recipientId = senderIsClient ? ownerId : clientId;
            const senderDisplayName = senderIsClient ? clientName : salonName;

            // Fetch recipient FCM token and language
            const recipientDoc = await db.collection("users").doc(recipientId).get();
            const fcmToken: string | undefined = recipientDoc.data()?.fcmToken;
            const recipientLang: string = recipientDoc.data()?.lang || "fr";
            const isEn = recipientLang === "en";

            const notifTitle = isEn ? `Message from ${senderDisplayName} 💬` : `Message de ${senderDisplayName} 💬`;
            const notifBody = text.length > 80 ? text.substring(0, 80) + "…" : text;

            if (!fcmToken) {
                console.log(`No FCM token for recipient ${recipientId}, skipping.`);
                return;
            }

            await messaging.send({
                token: fcmToken,
                notification: {
                    title: notifTitle,
                    body: notifBody,
                },
                data: {
                    type: "new_message",
                    conversationId: convId,
                    senderId: senderId,
                },
                android: {
                    priority: "high",
                    notification: {
                        channelId: "mon_salon_channel",
                        sound: "default",
                    },
                },
                apns: {
                    payload: {
                        aps: {
                            sound: "default",
                            badge: 1,
                        },
                    },
                },
            });

            console.log(`✅ Message notification sent to ${recipientId} (conv: ${convId})`);
        } catch (error) {
            console.error("Error sending message notification:", error);
        }
    });

// ============================================================
// 4. NOTIFY FAVORITES: When a new promotion is created by a salon owner,
//    wait 5 minutes, then notify all clients who favourited that salon.
//    Each client receives:
//      • a Firestore notification (visible in the in-app bell screen)
//      • a FCM push notification (device banner)
// ============================================================
export const onNewPromotion = functions
    .runWith({ timeoutSeconds: 540 }) // allow up to 9 min (5 min wait + work)
    .firestore
    .document("promotions/{promoId}")
    .onCreate(async (snap, context) => {
        const promoId: string = context.params.promoId;

        // ── Wait 5 minutes ──────────────────────────────────────────────────
        await new Promise((resolve) => setTimeout(resolve, 5 * 60 * 1000));

        // ── Re-fetch to verify the promo still exists and is active ─────────
        const promoDoc = await snap.ref.get();
        if (!promoDoc.exists) {
            console.log(`Promo ${promoId} was deleted, skipping notifications.`);
            return;
        }
        const promo = promoDoc.data()!;
        if (!promo.isActive) {
            console.log(`Promo ${promoId} is no longer active, skipping notifications.`);
            return;
        }

        const salonId: string = promo.salonId;
        const promoTitle: string = promo.title || "Nouvelle offre";

        // ── Get salon name ───────────────────────────────────────────────────
        const salonDoc = await db.collection("salons").doc(salonId).get();
        if (!salonDoc.exists) {
            console.log(`Salon ${salonId} not found, skipping notifications.`);
            return;
        }
        const salonName: string = salonDoc.data()?.name || "Un salon";

        // ── Find users who have this salon in their favourites ───────────────
        const usersSnap = await db
            .collection("users")
            .where("favorites", "array-contains", salonId)
            .get();

        if (usersSnap.empty) {
            console.log(`No users have salon ${salonId} in favourites. Done.`);
            return;
        }

        console.log(`📣 Sending promo notifications to ${usersSnap.size} user(s) for salon "${salonName}".`);

        // ── Batch-write Firestore notifications + collect FCM sends ─────────
        const batch = db.batch();
        const fcmPromises: Promise<any>[] = [];

        for (const userDoc of usersSnap.docs) {
            const userData = userDoc.data();
            const userLang: string = userData?.lang || "fr";
            const uIsEn = userLang === "en";

            const notifTitle = uIsEn ? `New offer at ${salonName} ✨` : `Nouvelle offre chez ${salonName} ✨`;
            const notifBody = promoTitle;

            // In-app notification document
            const notifRef = db.collection("notifications").doc();
            batch.set(notifRef, {
                userId: userDoc.id,
                title: notifTitle,
                body: notifBody,
                type: "promotion",
                isRead: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                salonId: salonId,
                promoId: promoId,
            });

            // FCM push (per-user for language personalization)
            const fcmToken: string | undefined = userData?.fcmToken;
            if (fcmToken) {
                fcmPromises.push(messaging.send({
                    token: fcmToken,
                    notification: { title: notifTitle, body: notifBody },
                    data: {
                        type: "new_promotion",
                        salonId: salonId,
                        promoId: promoId,
                    },
                    android: {
                        priority: "high",
                        notification: {
                            channelId: "mon_salon_channel",
                            sound: "default",
                        },
                    },
                    apns: {
                        payload: {
                            aps: {
                                sound: "default",
                                badge: 1,
                            },
                        },
                    },
                }).catch(err => console.error(`FCM error for ${userDoc.id}:`, err)));
            }
        }

        await batch.commit();
        console.log(`✅ ${usersSnap.size} in-app notification(s) written.`);

        // ── Send FCM push notifications ──────────────────────────────────────
        if (fcmPromises.length === 0) {
            console.log("No FCM tokens available, skipping push notifications.");
            return;
        }

        await Promise.all(fcmPromises);

        console.log(`✅ ${fcmPromises.length} FCM push(es) sent.`);
    });

// ============================================================
// 5. DAILY REMINDERS: Scheduled function (runs every day at 8 AM)
//    Sends reminders for appointments happening today
// ============================================================
export const sendDailyReminders = functions.pubsub
    .schedule("0 8 * * *") // Every day at 08:00
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const now = new Date();
        const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const endOfDay = new Date(startOfDay.getTime() + 24 * 60 * 60 * 1000);

        try {
            // Query upcoming appointments for today
            const snapshot = await db
                .collection("appointments")
                .where("status", "==", "upcoming")
                .where("dateTime", ">=", admin.firestore.Timestamp.fromDate(startOfDay))
                .where("dateTime", "<", admin.firestore.Timestamp.fromDate(endOfDay))
                .get();

            if (snapshot.empty) {
                console.log("No appointments today, no reminders to send.");
                return;
            }

            console.log(`📅 Found ${snapshot.size} appointments today. Sending reminders...`);

            const sendPromises = snapshot.docs.map(async (doc) => {
                const appointment = doc.data();
                const clientId: string = appointment.clientId;
                const salonName: string = appointment.salonName || "Salon";
                const serviceName: string = appointment.serviceName || "Service";

                // Get time
                const dateTime = appointment.dateTime?.toDate
                    ? appointment.dateTime.toDate()
                    : new Date(appointment.dateTime);

                // Get client's FCM token and language
                const clientDoc = await db.collection("users").doc(clientId).get();
                const fcmToken: string | undefined = clientDoc.data()?.fcmToken;
                const cLang: string = clientDoc.data()?.lang || "fr";
                const cIsEn = cLang === "en";

                const timeStr = dateTime.toLocaleTimeString(cIsEn ? "en-US" : "fr-FR", {
                    hour: "2-digit",
                    minute: "2-digit",
                });

                if (!fcmToken) return;

                await messaging.send({
                    token: fcmToken,
                    notification: {
                        title: cIsEn ? "Reminder: Appointment today! ⏰" : "Rappel : RDV aujourd'hui ! ⏰",
                        body: cIsEn ? `${serviceName} at ${salonName} at ${timeStr}` : `${serviceName} chez ${salonName} à ${timeStr}`,
                    },
                    data: {
                        type: "reminder",
                        appointmentId: doc.id,
                    },
                    android: {
                        priority: "high",
                        notification: {
                            channelId: "mon_salon_channel",
                            sound: "default",
                        },
                    },
                    apns: {
                        payload: {
                            aps: {
                                sound: "default",
                                badge: 1,
                            },
                        },
                    },
                });

                console.log(`✅ Reminder sent to client ${clientId}`);
            });

            await Promise.all(sendPromises);
            console.log("✅ All daily reminders sent.");
        } catch (error) {
            console.error("Error sending daily reminders:", error);
        }
    });

// ============================================================
// 6. 24H REMINDER: Scheduled function (runs every day at 8 AM)
//    Sends reminders for appointments happening TOMORROW
// ============================================================
export const send24hReminders = functions.pubsub
    .schedule("0 8 * * *") // Every day at 08:00
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const now = new Date();
        const tomorrowStart = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
        const tomorrowEnd = new Date(tomorrowStart.getTime() + 24 * 60 * 60 * 1000);

        try {
            const snapshot = await db
                .collection("appointments")
                .where("status", "==", "upcoming")
                .where("dateTime", ">=", admin.firestore.Timestamp.fromDate(tomorrowStart))
                .where("dateTime", "<", admin.firestore.Timestamp.fromDate(tomorrowEnd))
                .get();

            if (snapshot.empty) {
                console.log("No appointments tomorrow, no 24h reminders to send.");
                return;
            }

            console.log(`📅 Found ${snapshot.size} appointments tomorrow. Sending 24h reminders...`);

            const sendPromises = snapshot.docs.map(async (doc) => {
                const appointment = doc.data();
                const clientId: string = appointment.clientId;
                const salonName: string = appointment.salonName || "Salon";
                const serviceName: string = appointment.serviceName || "Service";

                // Skip walk-in clients (no user account)
                if (clientId === "walk-in") return;

                const dateTime = appointment.dateTime?.toDate
                    ? appointment.dateTime.toDate()
                    : new Date(appointment.dateTime);

                // Get client's FCM token and language
                const clientDoc = await db.collection("users").doc(clientId).get();
                const fcmToken: string | undefined = clientDoc.data()?.fcmToken;
                const cLang: string = clientDoc.data()?.lang || "fr";
                const cIsEn = cLang === "en";

                const timeStr = dateTime.toLocaleTimeString(cIsEn ? "en-US" : "fr-FR", {
                    hour: "2-digit",
                    minute: "2-digit",
                });

                if (!fcmToken) return;

                const rTitle = cIsEn ? "Reminder: Appointment tomorrow! 📋" : "Rappel : RDV demain ! 📋";
                const rBody = cIsEn
                    ? `${serviceName} at ${salonName} tomorrow at ${timeStr}`
                    : `${serviceName} chez ${salonName} demain à ${timeStr}`;

                await messaging.send({
                    token: fcmToken,
                    notification: {
                        title: rTitle,
                        body: rBody,
                    },
                    data: {
                        type: "reminder_24h",
                        appointmentId: doc.id,
                    },
                    android: {
                        priority: "high",
                        notification: {
                            channelId: "mon_salon_channel",
                            sound: "default",
                        },
                    },
                    apns: {
                        payload: {
                            aps: {
                                sound: "default",
                                badge: 1,
                            },
                        },
                    },
                });

                // Also save an in-app notification
                await db.collection("notifications").add({
                    userId: clientId,
                    title: rTitle,
                    body: rBody,
                    type: "reminder_24h",
                    isRead: false,
                    createdAt: admin.firestore.FieldValue.serverTimestamp(),
                });

                console.log(`✅ 24h reminder sent to client ${clientId}`);
            });

            await Promise.all(sendPromises);
            console.log("✅ All 24h reminders sent.");
        } catch (error) {
            console.error("Error sending 24h reminders:", error);
        }
    });

// ============================================================
// 7. AUTO-COMPLETE: Scheduled function (runs every 12 hours)
//    Marks past "upcoming" appointments as "completed" automatically
// ============================================================
export const autoCompleteAppointments = functions.pubsub
    .schedule("0 0,12 * * *") // Every day at 00:00 and 12:00
    .timeZone("Europe/Paris")
    .onRun(async () => {
        // Only auto-complete appointments at least 12h after their scheduled time
        const twelveHoursAgo = admin.firestore.Timestamp.fromDate(
            new Date(Date.now() - 12 * 60 * 60 * 1000)
        );

        try {
            const snapshot = await db
                .collection("appointments")
                .where("status", "==", "upcoming")
                .where("dateTime", "<", twelveHoursAgo)
                .get();

            if (snapshot.empty) {
                console.log("No past upcoming appointments to auto-complete.");
                return;
            }

            console.log(`🔄 Auto-completing ${snapshot.size} past appointment(s)...`);

            const batch = db.batch();
            for (const doc of snapshot.docs) {
                batch.update(doc.ref, { status: "completed" });
            }
            await batch.commit();

            console.log(`✅ ${snapshot.size} appointment(s) auto-completed.`);
        } catch (error) {
            console.error("Error auto-completing appointments:", error);
        }
    });

// ============================================================
// 8. NOTIFY OWNER: When a new order is created (Boutique)
// ============================================================
export const onNewOrder = functions.firestore
    .document("orders/{orderId}")
    .onCreate(async (snap) => {
        const order = snap.data();
        const salonId: string = order.salonId;
        const clientName: string = order.clientName || "Client";
        const totalPrice: number = order.totalPrice || 0;
        const deliveryFee: number = order.deliveryFee || 0;
        const grandTotal = totalPrice + deliveryFee;
        const itemCount: number = (order.items || []).length;

        try {
            const salonDoc = await db.collection("salons").doc(salonId).get();
            if (!salonDoc.exists) return;

            const ownerId: string = salonDoc.data()?.ownerId;
            if (!ownerId) return;

            const ownerDoc = await db.collection("users").doc(ownerId).get();
            const fcmToken: string | undefined = ownerDoc.data()?.fcmToken;
            const oLang: string = ownerDoc.data()?.lang || "fr";
            const oIsEn = oLang === "en";

            const oTitle = oIsEn ? "New shop order" : "Nouvelle commande boutique";
            const oBody = oIsEn
                ? `${clientName} ordered ${itemCount} item${itemCount > 1 ? "s" : ""} for ${grandTotal} MAD`
                : `${clientName} a commandé ${itemCount} article${itemCount > 1 ? "s" : ""} pour ${grandTotal} MAD`;

            // Save in-app notification for owner
            await db.collection("notifications").add({
                userId: ownerId,
                title: oTitle,
                body: oBody,
                type: "new_order",
                salonId: salonId,
                orderId: snap.id,
                isRead: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            if (fcmToken) {
                await messaging.send({
                    token: fcmToken,
                    notification: {
                        title: oIsEn ? "🛍️ New order" : "🛍️ Nouvelle commande",
                        body: oIsEn
                            ? `${clientName} — ${itemCount} item${itemCount > 1 ? "s" : ""} · ${grandTotal} MAD`
                            : `${clientName} — ${itemCount} article${itemCount > 1 ? "s" : ""} · ${grandTotal} MAD`,
                    },
                    data: {
                        type: "new_order",
                        orderId: snap.id,
                        salonId: salonId,
                    },
                    android: { priority: "high" },
                    apns: { payload: { aps: { sound: "default" } } },
                });
                console.log(`✅ Order notification sent to owner ${ownerId}`);
            }
        } catch (error) {
            console.error("Error sending order notification:", error);
        }
    });

// ============================================================
// 9. NOTIFY CLIENT: When order status changes
// ============================================================
export const onOrderStatusChanged = functions.firestore
    .document("orders/{orderId}")
    .onUpdate(async (change) => {
        const before = change.before.data();
        const after = change.after.data();

        if (before.status === after.status) return;

        const clientId: string = after.clientId;
        if (!clientId || clientId === "walk-in" || clientId === "anonymous") return;

        const newStatus: string = after.status;

        try {
            const clientDoc = await db.collection("users").doc(clientId).get();
            if (!clientDoc.exists) return;
            const cLang: string = clientDoc.data()?.lang || "fr";
            const cIsEn = cLang === "en";

        let title = "";
        let body = "";

        switch (newStatus) {
            case "confirmed":
                title = cIsEn ? "Order confirmed ✅" : "Commande confirmée ✅";
                body = cIsEn ? "Your order has been confirmed by the salon." : "Votre commande a été confirmée par le salon.";
                break;
            case "delivered":
                title = cIsEn ? "Order delivered 📦" : "Commande livrée 📦";
                body = cIsEn ? "Your order has been marked as delivered." : "Votre commande a été marquée comme livrée.";
                break;
            case "cancelled":
                title = cIsEn ? "Order cancelled ❌" : "Commande annulée ❌";
                body = cIsEn ? "Your order has been cancelled by the salon." : "Votre commande a été annulée par le salon.";
                break;
            default:
                return;
        }

            const fcmToken: string | undefined = clientDoc.data()?.fcmToken;

            // Save in-app notification
            await db.collection("notifications").add({
                userId: clientId,
                title: title,
                body: body,
                type: "order_status",
                orderId: change.after.id,
                isRead: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            if (fcmToken) {
                await messaging.send({
                    token: fcmToken,
                    notification: { title, body },
                    data: {
                        type: "order_status",
                        orderId: change.after.id,
                        status: newStatus,
                    },
                    android: { priority: "high" },
                    apns: { payload: { aps: { sound: "default" } } },
                });
                console.log(`✅ Order status notification sent to client ${clientId}`);
            }
        } catch (error) {
            console.error("Error sending order status notification:", error);
        }
    });

// ============================================================
// 10. LOW STOCK ALERT: When product stock drops
// ============================================================
export const onProductStockChanged = functions.firestore
    .document("products/{productId}")
    .onUpdate(async (change) => {
        const before = change.before.data();
        const after = change.after.data();

        const oldStock: number = before.stock || 0;
        const newStock: number = after.stock || 0;
        const threshold: number = after.lowStockThreshold || 5;

        // Only trigger when stock drops below threshold (not when already below)
        if (newStock >= oldStock || newStock > threshold || oldStock <= threshold) return;

        const salonId: string = after.salonId;
        const productName: string = after.name || "Produit";

        try {
            const salonDoc = await db.collection("salons").doc(salonId).get();
            if (!salonDoc.exists) return;

            const ownerId: string = salonDoc.data()?.ownerId;
            if (!ownerId) return;

            const ownerDoc = await db.collection("users").doc(ownerId).get();
            const fcmToken: string | undefined = ownerDoc.data()?.fcmToken;
            const sLang: string = ownerDoc.data()?.lang || "fr";
            const sIsEn = sLang === "en";

            const sTitle = sIsEn ? "⚠️ Low stock" : "⚠️ Stock bas";
            const sBody = sIsEn
                ? `${productName} — only ${newStock} unit${newStock > 1 ? "s" : ""} left`
                : `${productName} — il ne reste que ${newStock} unité${newStock > 1 ? "s" : ""}`;

            // Save in-app notification
            await db.collection("notifications").add({
                userId: ownerId,
                title: sTitle,
                body: sBody,
                type: "low_stock",
                salonId: salonId,
                isRead: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            if (fcmToken) {
                await messaging.send({
                    token: fcmToken,
                    notification: {
                        title: sTitle,
                        body: sBody,
                    },
                    data: {
                        type: "low_stock",
                        productId: change.after.id,
                        salonId: salonId,
                    },
                    android: { priority: "high" },
                    apns: { payload: { aps: { sound: "default" } } },
                });
                console.log(`✅ Low stock alert sent for ${productName}`);
            }
        } catch (error) {
            console.error("Error sending low stock notification:", error);
        }
    });

// ============================================================
// 11. AI DAILY SUMMARY: Generate intelligent dashboard summary
//     Includes: no-show prediction, price suggestions, financial
//     insights, action suggestions, monthly comparison
// ============================================================
export const generateDailySummary = functions
    .runWith({ secrets: ["GEMINI_API_KEY"] })
    .https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }

    const salonId: string = data.salonId;
    if (!salonId) {
        throw new functions.https.HttpsError("invalid-argument", "salonId required");
    }
    const lang: string = data.lang || "fr";
    const isEn = lang === "en";

    try {
        // ── Gather salon data ──
        const salonDoc = await db.collection("salons").doc(salonId).get();
        if (!salonDoc.exists) {
            throw new functions.https.HttpsError("not-found", "Salon not found");
        }
        const salon = salonDoc.data()!;

        const now = new Date();
        const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const todayEnd = new Date(todayStart.getTime() + 24 * 60 * 60 * 1000);
        const weekStart = new Date(todayStart.getTime() - (now.getDay() === 0 ? 6 : now.getDay() - 1) * 24 * 60 * 60 * 1000);
        const lastWeekStart = new Date(weekStart.getTime() - 7 * 24 * 60 * 60 * 1000);

        // Month boundaries
        const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
        const lastMonthStart = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        const lastMonthEnd = new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59);

        // Fetch all salon appointments in one query (no composite index needed)
        const allApptsSnap = await db.collection("appointments")
            .where("salonId", "==", salonId)
            .get();

        const allAppts: any[] = allApptsSnap.docs.map(d => ({...d.data(), _id: d.id}));

        // Helper: get timestamp as millis
        const getTime = (a: any): number => {
            if (a.dateTime?.toDate) return a.dateTime.toDate().getTime();
            if (a.dateTime) return new Date(a.dateTime).getTime();
            return 0;
        };

        // Today's appointments
        const todayAppts = allAppts.filter(a => {
            const t = getTime(a);
            return t >= todayStart.getTime() && t < todayEnd.getTime();
        });
        const todayCount = todayAppts.length;
        const todayUpcoming = todayAppts.filter(a => a.status === "upcoming").length;
        const todayCompleted = todayAppts.filter(a => a.status === "completed").length;
        const todayRevenue = todayAppts
            .filter(a => a.status === "completed")
            .reduce((s, a) => s + (a.price || 0), 0);

        // This week's appointments
        const weekAppts = allAppts.filter(a => {
            const t = getTime(a);
            return t >= weekStart.getTime() && t < todayEnd.getTime();
        });
        const weekCount = weekAppts.length;
        const weekRevenue = weekAppts
            .filter(a => a.status === "completed")
            .reduce((s, a) => s + (a.price || 0), 0);
        const weekCancelled = weekAppts.filter(a => a.status === "cancelled").length;

        // Last week (for comparison)
        const lastWeekAppts = allAppts.filter(a => {
            const t = getTime(a);
            return t >= lastWeekStart.getTime() && t < weekStart.getTime();
        });
        const lastWeekCount = lastWeekAppts.length;
        const lastWeekRevenue = lastWeekAppts
            .filter(a => a.status === "completed")
            .reduce((s, a) => s + (a.price || 0), 0);

        // ── Monthly comparison ──
        const thisMonthAppts = allAppts.filter(a => {
            const t = getTime(a);
            return t >= monthStart.getTime() && t < todayEnd.getTime();
        });
        const lastMonthAppts = allAppts.filter(a => {
            const t = getTime(a);
            return t >= lastMonthStart.getTime() && t <= lastMonthEnd.getTime();
        });
        const thisMonthRevenue = thisMonthAppts
            .filter(a => a.status === "completed")
            .reduce((s, a) => s + (a.price || 0), 0);
        const lastMonthRevenue = lastMonthAppts
            .filter(a => a.status === "completed")
            .reduce((s, a) => s + (a.price || 0), 0);
        const thisMonthCount = thisMonthAppts.length;
        const lastMonthCount = lastMonthAppts.length;
        const thisMonthCancelled = thisMonthAppts.filter(a => a.status === "cancelled").length;
        const lastMonthCancelled = lastMonthAppts.filter(a => a.status === "cancelled").length;
        // Unique clients this month vs last
        const thisMonthClients = new Set(thisMonthAppts.map(a => a.clientId).filter((id: string) => id && id !== "walk-in"));
        const lastMonthClients = new Set(lastMonthAppts.map(a => a.clientId).filter((id: string) => id && id !== "walk-in"));

        // ── No-show / cancellation prediction for today's clients ──
        const todayUpcomingAppts = todayAppts.filter(a => a.status === "upcoming");
        const clientIds = [...new Set(todayUpcomingAppts.map(a => a.clientId).filter((id: string) => id && id !== "walk-in"))];

        const noShowRisks: Array<{clientName: string, clientId: string, total: number, cancelled: number, rate: number}> = [];
        for (const cid of clientIds) {
            const clientAppts = allAppts.filter(a => a.clientId === cid && getTime(a) < todayStart.getTime());
            if (clientAppts.length < 2) continue; // Need history to predict
            const cancelled = clientAppts.filter(a => a.status === "cancelled").length;
            const rate = Math.round((cancelled / clientAppts.length) * 100);
            if (rate >= 25) {
                const name = todayUpcomingAppts.find(a => a.clientId === cid)?.clientName || "Client";
                noShowRisks.push({clientName: name, clientId: cid, total: clientAppts.length, cancelled, rate});
            }
        }
        noShowRisks.sort((a, b) => b.rate - a.rate);

        // ── Service pricing analysis ──
        const serviceCounts: Record<string, {count: number, totalRevenue: number, avgPrice: number}> = {};
        const completedAppts = allAppts.filter(a => a.status === "completed");
        for (const a of completedAppts) {
            const name = a.serviceName || "Autre";
            if (!serviceCounts[name]) serviceCounts[name] = {count: 0, totalRevenue: 0, avgPrice: 0};
            serviceCounts[name].count++;
            serviceCounts[name].totalRevenue += (a.price || 0);
        }
        for (const key of Object.keys(serviceCounts)) {
            serviceCounts[key].avgPrice = Math.round(serviceCounts[key].totalRevenue / serviceCounts[key].count);
        }
        const serviceAnalysis = Object.entries(serviceCounts)
            .map(([name, stats]) => ({name, ...stats}))
            .sort((a, b) => b.count - a.count)
            .slice(0, 8);

        const topService = serviceAnalysis[0] || null;

        // ── Charges this month (for financial insights) ──
        let thisMonthCharges = 0;
        let lastMonthCharges = 0;
        try {
            const chargesSnap = await db.collection("charges")
                .where("salonId", "==", salonId)
                .get();
            for (const doc of chargesSnap.docs) {
                const c = doc.data();
                const ct = c.date?.toDate ? c.date.toDate().getTime() : 0;
                if (ct >= monthStart.getTime() && ct < todayEnd.getTime()) {
                    thisMonthCharges += (c.amount || 0);
                } else if (ct >= lastMonthStart.getTime() && ct <= lastMonthEnd.getTime()) {
                    lastMonthCharges += (c.amount || 0);
                }
            }
        } catch (_) { /* charges collection may not exist */ }

        // ── Busiest day analysis ──
        const dayBookings: Record<string, number> = {};
        const dayNamesArr = isEn
            ? ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            : ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"];
        for (const a of thisMonthAppts) {
            const d = a.dateTime?.toDate ? a.dateTime.toDate() : new Date(getTime(a));
            const dayName = dayNamesArr[d.getDay()];
            dayBookings[dayName] = (dayBookings[dayName] || 0) + 1;
        }
        const busiestDay = Object.entries(dayBookings).sort((a, b) => b[1] - a[1])[0];
        const slowestDay = Object.entries(dayBookings).sort((a, b) => a[1] - b[1])[0];

        // Reviews
        const reviewsSnap = await db.collection("reviews")
            .where("salonId", "==", salonId)
            .get();
        const recentReviews = reviewsSnap.docs
            .map(d => d.data())
            .sort((a, b) => {
                const ta = a.createdAt?.toDate ? a.createdAt.toDate().getTime() : 0;
                const tb = b.createdAt?.toDate ? b.createdAt.toDate().getTime() : 0;
                return tb - ta;
            })
            .slice(0, 5)
            .map(r => ({ rating: r.rating, comment: r.comment || "" }));

        // ── Build prompt ──
        const weekChange = lastWeekCount > 0
            ? Math.round(((weekCount - lastWeekCount) / lastWeekCount) * 100)
            : 0;
        const revenueChange = lastWeekRevenue > 0
            ? Math.round(((weekRevenue - lastWeekRevenue) / lastWeekRevenue) * 100)
            : 0;

        const todayName = dayNamesArr[now.getDay()];
        const monthNames = isEn
            ? ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
            : ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"];
        const thisMonthName = monthNames[now.getMonth()];
        const lastMonthName = monthNames[now.getMonth() === 0 ? 11 : now.getMonth() - 1];

        const prompt = isEn
            ? `You are the AI assistant for salon "${salon.name}". Generate a structured JSON summary for the owner. Speak in English, be concise and actionable.

TODAY'S DATA (${todayName}):
- ${todayCount} appointments (${todayUpcoming} upcoming, ${todayCompleted} completed)
- Revenue today: ${todayRevenue} MAD

WEEKLY DATA:
- ${weekCount} appointments (${weekCancelled} cancelled)
- Revenue: ${weekRevenue} MAD
- Change vs last week: ${weekChange > 0 ? "+" : ""}${weekChange}% appointments, ${revenueChange > 0 ? "+" : ""}${revenueChange}% revenue
${topService ? `- Top service: ${topService.name} (${topService.count} times, avg ${topService.avgPrice} MAD)` : ""}

MONTHLY COMPARISON:
- ${thisMonthName}: ${thisMonthCount} appointments, ${thisMonthRevenue} MAD revenue, ${thisMonthCancelled} cancelled, ${thisMonthClients.size} unique clients
- ${lastMonthName}: ${lastMonthCount} appointments, ${lastMonthRevenue} MAD revenue, ${lastMonthCancelled} cancelled, ${lastMonthClients.size} unique clients
- Charges ${thisMonthName}: ${thisMonthCharges} MAD | Net profit: ${thisMonthRevenue - thisMonthCharges} MAD
- Charges ${lastMonthName}: ${lastMonthCharges} MAD | Net profit: ${lastMonthRevenue - lastMonthCharges} MAD
${busiestDay ? `- Busiest day this month: ${busiestDay[0]} (${busiestDay[1]} appointments)` : ""}
${slowestDay ? `- Slowest day: ${slowestDay[0]} (${slowestDay[1]} appointments)` : ""}

SERVICE ANALYSIS:
${serviceAnalysis.map(s => `- ${s.name}: ${s.count} bookings, avg price ${s.avgPrice} MAD`).join("\n")}

AT-RISK CLIENTS (high cancellation rate among today's appointments):
${noShowRisks.length > 0 ? noShowRisks.map(r => `- ${r.clientName}: ${r.rate}% cancellation (${r.cancelled}/${r.total} appointments)`).join("\n") : "No at-risk clients today."}

${recentReviews.length > 0 ? `RECENT REVIEWS: ${recentReviews.map(r => `${r.rating}★${r.comment ? " - " + r.comment : ""}`).join(" | ")}` : "No recent reviews."}

Respond ONLY with valid JSON (no markdown, no \`\`\`json), with this exact structure:
{
  "summary": "2-3 motivating summary sentences about the day",
  "noShowAlerts": ["short sentence per at-risk client"] or [] if none,
  "priceSuggestions": ["1-2 price suggestions based on service demand"] or [] if nothing to suggest,
  "actionSuggestions": ["2-3 concrete actions to take today/this week"],
  "monthlyComparison": "1-2 sentences comparing this month to last (appointments, revenue, profit)",
  "financialInsights": "1-2 sentences about financial health and trends"
}`
            : `Tu es l'assistant IA du salon "${salon.name}". Génère un résumé structuré en JSON pour le propriétaire. Parle en français, tutoie-le. Sois concis et actionnable.

DONNÉES DU JOUR (${todayName}) :
- ${todayCount} RDV (${todayUpcoming} à venir, ${todayCompleted} terminés)
- Revenu aujourd'hui : ${todayRevenue} MAD

DONNÉES DE LA SEMAINE :
- ${weekCount} RDV (${weekCancelled} annulés)
- Revenu : ${weekRevenue} MAD
- Variation vs semaine dernière : ${weekChange > 0 ? "+" : ""}${weekChange}% RDV, ${revenueChange > 0 ? "+" : ""}${revenueChange}% revenu
${topService ? `- Service top : ${topService.name} (${topService.count} fois, moy ${topService.avgPrice} MAD)` : ""}

COMPARAISON MENSUELLE :
- ${thisMonthName} : ${thisMonthCount} RDV, ${thisMonthRevenue} MAD revenu, ${thisMonthCancelled} annulés, ${thisMonthClients.size} clients uniques
- ${lastMonthName} : ${lastMonthCount} RDV, ${lastMonthRevenue} MAD revenu, ${lastMonthCancelled} annulés, ${lastMonthClients.size} clients uniques
- Charges ${thisMonthName} : ${thisMonthCharges} MAD | Bénéfice net : ${thisMonthRevenue - thisMonthCharges} MAD
- Charges ${lastMonthName} : ${lastMonthCharges} MAD | Bénéfice net : ${lastMonthRevenue - lastMonthCharges} MAD
${busiestDay ? `- Jour le plus chargé ce mois : ${busiestDay[0]} (${busiestDay[1]} RDV)` : ""}
${slowestDay ? `- Jour le plus calme : ${slowestDay[0]} (${slowestDay[1]} RDV)` : ""}

ANALYSE DES SERVICES :
${serviceAnalysis.map(s => `- ${s.name} : ${s.count} réservations, prix moyen ${s.avgPrice} MAD`).join("\n")}

CLIENTS À RISQUE (taux d'annulation élevé parmi les RDV d'aujourd'hui) :
${noShowRisks.length > 0 ? noShowRisks.map(r => `- ${r.clientName} : ${r.rate}% d'annulation (${r.cancelled}/${r.total} RDV)`).join("\n") : "Aucun client à risque aujourd'hui."}

${recentReviews.length > 0 ? `DERNIERS AVIS : ${recentReviews.map(r => `${r.rating}★${r.comment ? " - " + r.comment : ""}`).join(" | ")}` : "Pas d'avis récents."}

Réponds UNIQUEMENT avec un JSON valide (pas de markdown, pas de \`\`\`json), avec cette structure exacte :
{
  "summary": "2-3 phrases de résumé motivant de la journée",
  "noShowAlerts": ["phrase courte par client à risque"] ou [] si aucun,
  "priceSuggestions": ["1-2 suggestions de prix basées sur la demande des services"] ou [] si rien à suggérer,
  "actionSuggestions": ["2-3 actions concrètes à faire aujourd'hui/cette semaine"],
  "monthlyComparison": "1-2 phrases comparant ce mois au précédent (RDV, revenu, bénéfice)",
  "financialInsights": "1-2 phrases sur la santé financière et tendances"
}`;

        // ── Call Gemini ──
        const apiKey = process.env.GEMINI_API_KEY;
        if (!apiKey) {
            throw new functions.https.HttpsError("failed-precondition", "GEMINI_API_KEY not set in .env");
        }

        const genAI = new GoogleGenerativeAI(apiKey);
        const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });
        const result = await model.generateContent(prompt);
        const rawText = result.response.text().trim();

        // Parse JSON response from Gemini
        let parsed: any;
        try {
            // Remove potential markdown code block markers
            const cleaned = rawText.replace(/^```json?\s*/i, "").replace(/```\s*$/i, "").trim();
            parsed = JSON.parse(cleaned);
        } catch (_) {
            // Fallback: return as plain summary (backward compatible)
            return { summary: rawText, generatedAt: now.toISOString() };
        }

        return {
            summary: parsed.summary || rawText,
            noShowAlerts: parsed.noShowAlerts || [],
            priceSuggestions: parsed.priceSuggestions || [],
            actionSuggestions: parsed.actionSuggestions || [],
            monthlyComparison: parsed.monthlyComparison || "",
            financialInsights: parsed.financialInsights || "",
            generatedAt: now.toISOString(),
        };
    } catch (error: any) {
        console.error("Error generating AI summary:", error);
        if (error instanceof functions.https.HttpsError) throw error;
        throw new functions.https.HttpsError("internal", "Failed to generate summary");
    }
});

// ============================================================
// 12. SMART AUTO-PROMOTIONS: Daily cron to generate targeted promos (rule-based)
// ============================================================
export const generateSmartPromotions = functions.pubsub
    .schedule("0 8 * * *") // Every day at 08:00
    .timeZone("Europe/Paris")
    .onRun(async () => {
        const salonsSnap = await db.collection("salons").get();
        const enabledSalons = salonsSnap.docs.filter(
            (d) => d.data().aiPromosEnabled === true
        );

        if (enabledSalons.length === 0) {
            console.log("No salons have smart promos enabled.");
            return;
        }

        for (const salonDoc of enabledSalons) {
            try {
                const salon = salonDoc.data();
                const salonId = salonDoc.id;

                // Get all completed appointments for this salon
                const apptsSnap = await db.collection("appointments")
                    .where("salonId", "==", salonId)
                    .get();
                const appts = apptsSnap.docs.map((d) => d.data());
                const completedAppts = appts.filter((a) => a.status === "completed");

                if (completedAppts.length < 3) {
                    console.log(`Salon ${salonId}: not enough data, skipping.`);
                    continue;
                }

                // Build client profiles
                const clientMap: Record<string, {
                    name: string; visits: number; totalSpent: number;
                    lastVisit: number; id: string;
                }> = {};

                for (const a of completedAppts) {
                    const cid = a.clientId;
                    if (!cid || cid === "walk-in") continue;
                    const dt = a.dateTime?.toDate ? a.dateTime.toDate().getTime() : new Date(a.dateTime).getTime();
                    if (!clientMap[cid]) {
                        clientMap[cid] = {
                            id: cid,
                            name: a.clientName || "Client",
                            visits: 0,
                            totalSpent: 0,
                            lastVisit: 0,
                        };
                    }
                    clientMap[cid].visits++;
                    clientMap[cid].totalSpent += (a.price || 0);
                    if (dt > clientMap[cid].lastVisit) {
                        clientMap[cid].lastVisit = dt;
                        clientMap[cid].name = a.clientName || clientMap[cid].name;
                    }
                }

                const clients = Object.values(clientMap);
                if (clients.length === 0) continue;

                const now = Date.now();
                const dayMs = 24 * 60 * 60 * 1000;

                // Check for existing smart promos created today to avoid duplicates
                const todayStart = new Date();
                todayStart.setHours(0, 0, 0, 0);
                const existingPromos = await db.collection("promotions")
                    .where("salonId", "==", salonId)
                    .get();
                const todaySmartPromos = existingPromos.docs.filter((d) => {
                    const data = d.data();
                    if (!data.isAiGenerated) return false;
                    const created = data.createdAt?.toDate ? data.createdAt.toDate() : new Date(0);
                    return created >= todayStart;
                });

                if (todaySmartPromos.length >= 3) {
                    console.log(`Salon ${salonId}: already has ${todaySmartPromos.length} smart promos today, skipping.`);
                    continue;
                }

                // Read owner-customizable config (with defaults)
                const cfg = salon.aiPromoConfig || {};
                const topPct = cfg.topClientPercent || 30;
                const winBackPct = cfg.winBackPercent || 20;
                const winBackWeeks = cfg.winBackWeeks || 3;
                const loyalPct = cfg.loyalPercent || 15;
                const loyalMin = cfg.loyalMinVisits || 10;

                // ── Rule-based promo generation ──
                const promos: Array<{
                    clientId: string; clientName: string; reason: string;
                    discountPercent: number; title: string; description: string;
                }> = [];

                // Already targeted client IDs (avoid duplicates)
                const targeted = new Set<string>();

                // Rule 1: WIN-BACK — clients absent for X+ weeks
                const absentClients = clients
                    .filter((c) => (now - c.lastVisit) > winBackWeeks * 7 * dayMs)
                    .sort((a, b) => b.visits - a.visits); // prioritize those who used to come often

                for (const c of absentClients) {
                    if (promos.length >= 3) break;
                    if (targeted.has(c.id)) continue;
                    const absentDays = Math.round((now - c.lastVisit) / dayMs);
                    // Get client lang for personalized promo text
                    let cIsEn = false;
                    try {
                        const cDoc = await db.collection("users").doc(c.id).get();
                        cIsEn = cDoc.data()?.lang === "en";
                    } catch (_) { /* default fr */ }
                    promos.push({
                        clientId: c.id,
                        clientName: c.name,
                        reason: "win_back",
                        discountPercent: winBackPct,
                        title: cIsEn ? `${c.name}, we miss you!` : `${c.name}, tu nous manques !`,
                        description: cIsEn
                            ? `It's been ${absentDays} days! Enjoy -${winBackPct}% on your next visit.`
                            : `Cela fait ${absentDays} jours ! Profite de -${winBackPct}% sur ta prochaine visite.`,
                    });
                    targeted.add(c.id);
                }

                // Rule 2: LOYAL — clients with X+ visits
                const loyalClients = clients
                    .filter((c) => c.visits >= loyalMin)
                    .sort((a, b) => b.visits - a.visits);

                for (const c of loyalClients) {
                    if (promos.length >= 3) break;
                    if (targeted.has(c.id)) continue;
                    let cIsEn2 = false;
                    try {
                        const cDoc = await db.collection("users").doc(c.id).get();
                        cIsEn2 = cDoc.data()?.lang === "en";
                    } catch (_) { /* default fr */ }
                    promos.push({
                        clientId: c.id,
                        clientName: c.name,
                        reason: "loyal",
                        discountPercent: loyalPct,
                        title: cIsEn2 ? `Thank you for your loyalty, ${c.name}!` : `Merci pour ta fidélité, ${c.name} !`,
                        description: cIsEn2
                            ? `${c.visits} visits with us! Here's -${loyalPct}% to thank you.`
                            : `${c.visits} visites chez nous ! Voici -${loyalPct}% pour te remercier.`,
                    });
                    targeted.add(c.id);
                }

                // Rule 3: TOP CLIENT — most visits in the last 30 days
                const thirtyDaysAgo = now - 30 * dayMs;
                const recentVisits: Record<string, number> = {};
                for (const a of completedAppts) {
                    const cid = a.clientId;
                    if (!cid || cid === "walk-in") continue;
                    const dt = a.dateTime?.toDate ? a.dateTime.toDate().getTime() : new Date(a.dateTime).getTime();
                    if (dt >= thirtyDaysAgo) {
                        recentVisits[cid] = (recentVisits[cid] || 0) + 1;
                    }
                }
                const topClient = Object.entries(recentVisits)
                    .sort((a, b) => b[1] - a[1])
                    .find(([id]) => !targeted.has(id) && clientMap[id]);

                if (topClient && promos.length < 3) {
                    const c = clientMap[topClient[0]];
                    let cIsEn3 = false;
                    try {
                        const cDoc = await db.collection("users").doc(c.id).get();
                        cIsEn3 = cDoc.data()?.lang === "en";
                    } catch (_) { /* default fr */ }
                    promos.push({
                        clientId: c.id,
                        clientName: c.name,
                        reason: "top_client",
                        discountPercent: topPct,
                        title: cIsEn3 ? `${c.name}, our best client this month!` : `${c.name}, notre meilleur client du mois !`,
                        description: cIsEn3
                            ? `${topClient[1]} visits this month! Enjoy -${topPct}% as a reward.`
                            : `${topClient[1]} visites ce mois-ci ! Profite de -${topPct}% en récompense.`,
                    });
                    targeted.add(c.id);
                }

                if (promos.length === 0) {
                    console.log(`Salon ${salonId}: no smart promos to generate.`);
                    continue;
                }

                const expiresAt = new Date(now + 7 * dayMs);

                for (const promo of promos) {
                    // Create promotion in Firestore
                    const promoRef = await db.collection("promotions").add({
                        salonId,
                        title: promo.title,
                        description: promo.description,
                        type: "percent",
                        discountPercent: promo.discountPercent,
                        isActive: true,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
                        isAiGenerated: true,
                        aiReason: promo.reason,
                        targetedClientId: promo.clientId,
                        targetedClientName: promo.clientName,
                    });

                    console.log(`Salon ${salonId}: smart promo created (${promo.reason}) for ${promo.clientName} → ${promoRef.id}`);

                    // Send push notification to the targeted client
                    if (promo.clientId) {
                        try {
                            const clientDoc = await db.collection("users").doc(promo.clientId).get();
                            const fcmToken = clientDoc.data()?.fcmToken;
                            const pLang: string = clientDoc.data()?.lang || "fr";
                            const pIsEn = pLang === "en";

                            if (fcmToken) {
                                await messaging.send({
                                    token: fcmToken,
                                    notification: {
                                        title: pIsEn ? `${salon.name} - Special offer for you!` : `${salon.name} - Offre spéciale pour toi !`,
                                        body: promo.title,
                                    },
                                    data: {
                                        type: "smart_promotion",
                                        salonId,
                                        promotionId: promoRef.id,
                                    },
                                });
                                console.log(`Push sent to ${promo.clientName} (${promo.clientId})`);
                            }

                            // Save in-app notification
                            await db.collection("notifications").add({
                                userId: promo.clientId,
                                title: pIsEn ? `${salon.name} - Special offer` : `${salon.name} - Offre spéciale`,
                                body: promo.title,
                                type: "smart_promotion",
                                salonId,
                                read: false,
                                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                            });
                        } catch (pushErr) {
                            console.error(`Push error for ${promo.clientId}:`, pushErr);
                        }
                    }
                }
            } catch (salonErr) {
                console.error(`Error processing salon ${salonDoc.id}:`, salonErr);
            }
        }

        console.log("Smart promotions generation complete.");
    });

// ============================================================
// 13. RATE LIMIT: Callable function to check before signup
// ============================================================
export const checkSignupLimit = functions.https.onCall(async (data, context) => {
    const email: string = data.email || "";
    const ip: string = context.rawRequest.ip || "unknown";

    // --- Block disposable email domains ---
    const disposable = [
        "yopmail.com", "tempmail.com", "guerrillamail.com", "mailinator.com",
        "throwaway.email", "temp-mail.org", "fakeinbox.com", "sharklasers.com",
        "guerrillamailblock.com", "grr.la", "dispostable.com", "trashmail.com",
        "10minutemail.com", "mailnesia.com", "getairmail.com",
    ];
    const domain = email.split("@")[1]?.toLowerCase();
    if (domain && disposable.includes(domain)) {
        throw new functions.https.HttpsError("permission-denied",
            "Les adresses email temporaires ne sont pas autorisées.");
    }

    // --- IP-based rate limit: max 3 accounts per hour ---
    const now = Date.now();
    const oneHourAgo = now - 3600000;
    const rateLimitRef = db.collection("_rateLimits").doc(`signup_${ip.replace(/[./]/g, "_")}`);

    try {
        const doc = await rateLimitRef.get();
        if (doc.exists) {
            const docData = doc.data();
            const timestamps: number[] = (docData?.timestamps || [])
                .filter((t: number) => t > oneHourAgo);

            if (timestamps.length >= 3) {
                console.warn(`Rate limit hit for IP ${ip} — ${timestamps.length} signups in last hour`);
                throw new functions.https.HttpsError("resource-exhausted",
                    "Trop de comptes créés depuis cette adresse. Réessayez dans une heure.");
            }
        }
    } catch (e: unknown) {
        if (e instanceof functions.https.HttpsError) throw e;
        console.error("Rate limit check error:", e);
    }

    // --- Global daily limit: max 50 accounts per day ---
    const today = new Date().toISOString().split("T")[0];
    const dailyRef = db.collection("_rateLimits").doc(`daily_${today}`);

    try {
        const doc = await dailyRef.get();
        const count = doc.exists ? (doc.data()?.count || 0) : 0;

        if (count >= 50) {
            console.warn(`Daily signup limit reached: ${count}`);
            throw new functions.https.HttpsError("resource-exhausted",
                "Limite quotidienne atteinte. Réessayez demain.");
        }
    } catch (e: unknown) {
        if (e instanceof functions.https.HttpsError) throw e;
        console.error("Daily limit check error:", e);
    }

    console.log(`✅ Signup check passed for ${email} from IP ${ip}`);
    return { allowed: true };
});

// ── Record successful signup (called after createUser succeeds) ──
export const recordSignup = functions.https.onCall(async (_data, context) => {
    const ip: string = context.rawRequest.ip || "unknown";
    const now = Date.now();
    const oneHourAgo = now - 3600000;

    // Update IP rate limit
    const rateLimitRef = db.collection("_rateLimits").doc(`signup_${ip.replace(/[./]/g, "_")}`);
    try {
        const doc = await rateLimitRef.get();
        const timestamps: number[] = doc.exists
            ? (doc.data()?.timestamps || []).filter((t: number) => t > oneHourAgo)
            : [];
        timestamps.push(now);
        await rateLimitRef.set({
            timestamps,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch (e) {
        console.error("Record signup IP error:", e);
    }

    // Increment daily counter
    const today = new Date().toISOString().split("T")[0];
    const dailyRef = db.collection("_rateLimits").doc(`daily_${today}`);
    try {
        await dailyRef.set({
            count: admin.firestore.FieldValue.increment(1),
            date: today,
        }, { merge: true });
    } catch (e) {
        console.error("Record signup daily error:", e);
    }

    return { ok: true };
});

// ============================================================
// 14. NOTIFY OWNER: When a client submits a Google review reward request
// ============================================================
export const onNewReviewReward = functions.firestore
    .document("reviewRewards/{rewardId}")
    .onCreate(async (snap) => {
        const reward = snap.data();
        const salonId: string = reward.salonId;
        const clientName: string = reward.clientName || "Un client";

        try {
            const salonDoc = await db.collection("salons").doc(salonId).get();
            if (!salonDoc.exists) return;
            const ownerId: string = salonDoc.data()?.ownerId;
            if (!ownerId) return;

            const ownerDoc = await db.collection("users").doc(ownerId).get();
            const fcmToken: string | undefined = ownerDoc.data()?.fcmToken;
            const oLang: string = ownerDoc.data()?.lang || "fr";
            const oIsEn = oLang === "en";

            const nTitle = oIsEn ? "New Google review to validate ⭐" : "Nouvel avis Google à valider ⭐";
            const nBody = oIsEn
                ? `${clientName} claims to have left a Google review. Verify and validate to send their discount.`
                : `${clientName} déclare avoir laissé un avis Google. Vérifiez et validez pour lui envoyer sa réduction.`;

            if (fcmToken) {
                await messaging.send({
                    token: fcmToken,
                    notification: { title: nTitle, body: nBody },
                    data: {
                        type: "review_reward_pending",
                        salonId,
                        rewardId: snap.id,
                    },
                    android: { priority: "high", notification: { channelId: "mon_salon_channel", sound: "default" } },
                    apns: { payload: { aps: { sound: "default", badge: 1 } } },
                });
            }

            // Save in-app notification for owner
            await db.collection("notifications").add({
                userId: ownerId,
                title: oIsEn ? "Google review to validate ⭐" : "Avis Google à valider ⭐",
                body: oIsEn
                    ? `${clientName} left a Google review. Validate to send their discount.`
                    : `${clientName} a laissé un avis Google. Validez pour lui envoyer sa réduction.`,
                type: "review_reward_pending",
                salonId,
                read: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log(`✅ Owner ${ownerId} notified for review reward ${snap.id}`);
        } catch (error) {
            console.error("Error in onNewReviewReward:", error);
        }
    });

// ============================================================
// 15. NOTIFY CLIENT: When owner validates a Google review reward
// ============================================================
export const onReviewRewardValidated = functions.firestore
    .document("reviewRewards/{rewardId}")
    .onUpdate(async (change) => {
        const before = change.before.data();
        const after = change.after.data();

        // Only trigger on pending → validated transition
        if (before.status !== "pending" || after.status !== "validated") return;

        const clientId: string = after.clientId;
        const promoCode: string = after.promoCode || "";
        const discountPercent: number = after.discountPercent || 10;
        const salonId: string = after.salonId;

        try {
            const salonDoc = await db.collection("salons").doc(salonId).get();
            const salonName: string = salonDoc.data()?.name || "Salon";

            const clientDoc = await db.collection("users").doc(clientId).get();
            const fcmToken: string | undefined = clientDoc.data()?.fcmToken;
            const cLang: string = clientDoc.data()?.lang || "fr";
            const cIsEn = cLang === "en";

            const rTitle = cIsEn ? "Your discount is ready! 🎉" : "Votre réduction est disponible ! 🎉";
            const rBody = cIsEn
                ? `Thank you for your review on ${salonName}! Your promo code: ${promoCode} (-${discountPercent}%)`
                : `Merci pour votre avis sur ${salonName} ! Votre code promo : ${promoCode} (-${discountPercent}%)`;

            if (fcmToken) {
                await messaging.send({
                    token: fcmToken,
                    notification: { title: rTitle, body: rBody },
                    data: {
                        type: "review_reward_validated",
                        salonId,
                        promoCode,
                    },
                    android: { priority: "high", notification: { channelId: "mon_salon_channel", sound: "default" } },
                    apns: { payload: { aps: { sound: "default", badge: 1 } } },
                });
            }

            // Save in-app notification for client
            await db.collection("notifications").add({
                userId: clientId,
                title: rTitle,
                body: cIsEn
                    ? `Promo code: ${promoCode} — ${discountPercent}% off at ${salonName}`
                    : `Code promo : ${promoCode} — ${discountPercent}% de réduction chez ${salonName}`,
                type: "review_reward_validated",
                salonId,
                promoCode,
                read: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            console.log(`✅ Client ${clientId} notified for validated reward, code: ${promoCode}`);
        } catch (error) {
            console.error("Error in onReviewRewardValidated:", error);
        }
    });
