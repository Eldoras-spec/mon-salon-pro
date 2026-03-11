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

            // Format date
            const dateTime = appointment.dateTime?.toDate
                ? appointment.dateTime.toDate()
                : new Date(appointment.dateTime);
            const dateStr = dateTime.toLocaleDateString("fr-FR", {
                day: "2-digit",
                month: "long",
                year: "numeric",
            });
            const timeStr = dateTime.toLocaleTimeString("fr-FR", {
                hour: "2-digit",
                minute: "2-digit",
            });

            // Save in-app notification for the owner
            await db.collection("notifications").add({
                userId: ownerId,
                title: "Nouvelle Réservation ! 🎉",
                body: `${serviceName} - ${salonName} le ${dateStr} à ${timeStr}`,
                type: "new_appointment",
                isRead: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // Send push notification to the salon owner
            await messaging.send({
                token: fcmToken,
                notification: {
                    title: "Nouvelle Réservation ! 🎉",
                    body: `${serviceName} - ${salonName} le ${dateStr} à ${timeStr}`,
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

                    // Save in-app notification
                    await db.collection("notifications").add({
                        userId: waitlistClientId,
                        title: `Créneau disponible chez ${salonName} !`,
                        body: `Un créneau s'est libéré pour le ${appointmentDate.toLocaleDateString("fr-FR", { day: "2-digit", month: "long" })}. Réservez vite !`,
                        type: "waitlist",
                        isRead: false,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                        salonId: salonId,
                    });

                    // Send FCM push
                    const wClientDoc = await db.collection("users").doc(waitlistClientId).get();
                    const wToken: string | undefined = wClientDoc.data()?.fcmToken;
                    if (wToken) {
                        await messaging.send({
                            token: wToken,
                            notification: {
                                title: `Créneau disponible ! 🎉`,
                                body: `Un créneau s'est libéré chez ${salonName}. Réservez maintenant !`,
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
            // Get client's FCM token
            const clientDoc = await db.collection("users").doc(clientId).get();
            const fcmToken: string | undefined = clientDoc.data()?.fcmToken;

            if (!fcmToken) {
                console.log(`No FCM token for client ${clientId}, skipping.`);
                return;
            }

            // Build notification based on status
            let title = "";
            let body = "";

            switch (newStatus) {
                case "cancelled":
                    title = "Rendez-vous Annulé ❌";
                    body = `Votre RDV "${serviceName}" chez ${salonName} a été annulé.`;
                    break;
                case "confirmed":
                    title = "Rendez-vous Confirmé ✅";
                    body = `Votre RDV "${serviceName}" chez ${salonName} est confirmé !`;
                    break;
                case "completed":
                    title = "Rendez-vous Terminé 🌟";
                    body = `Merci pour votre visite chez ${salonName} ! Laissez un avis.`;
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
            const notifTitle = `Message de ${senderDisplayName} 💬`;
            const notifBody = text.length > 80 ? text.substring(0, 80) + "…" : text;

            // Fetch recipient FCM token
            const recipientDoc = await db.collection("users").doc(recipientId).get();
            const fcmToken: string | undefined = recipientDoc.data()?.fcmToken;

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

        const notifTitle = `Nouvelle offre chez ${salonName} ✨`;
        const notifBody = promoTitle;

        // ── Batch-write Firestore notifications + collect FCM tokens ─────────
        const batch = db.batch();
        const tokens: string[] = [];

        for (const userDoc of usersSnap.docs) {
            const userData = userDoc.data();

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

            // FCM token (may be absent if user never granted permission)
            const fcmToken: string | undefined = userData?.fcmToken;
            if (fcmToken) tokens.push(fcmToken);
        }

        await batch.commit();
        console.log(`✅ ${usersSnap.size} in-app notification(s) written.`);

        // ── Send FCM push notifications ──────────────────────────────────────
        if (tokens.length === 0) {
            console.log("No FCM tokens available, skipping push notifications.");
            return;
        }

        const fcmResponse = await messaging.sendEachForMulticast({
            tokens,
            notification: {
                title: notifTitle,
                body: notifBody,
            },
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
        });

        console.log(
            `✅ FCM push: ${fcmResponse.successCount} sent, ` +
            `${fcmResponse.failureCount} failed (out of ${tokens.length} tokens).`
        );
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
                const timeStr = dateTime.toLocaleTimeString("fr-FR", {
                    hour: "2-digit",
                    minute: "2-digit",
                });

                // Get client's FCM token
                const clientDoc = await db.collection("users").doc(clientId).get();
                const fcmToken: string | undefined = clientDoc.data()?.fcmToken;

                if (!fcmToken) return;

                await messaging.send({
                    token: fcmToken,
                    notification: {
                        title: "Rappel : RDV aujourd'hui ! ⏰",
                        body: `${serviceName} chez ${salonName} à ${timeStr}`,
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
                const timeStr = dateTime.toLocaleTimeString("fr-FR", {
                    hour: "2-digit",
                    minute: "2-digit",
                });

                // Get client's FCM token
                const clientDoc = await db.collection("users").doc(clientId).get();
                const fcmToken: string | undefined = clientDoc.data()?.fcmToken;

                if (!fcmToken) return;

                await messaging.send({
                    token: fcmToken,
                    notification: {
                        title: "Rappel : RDV demain ! 📋",
                        body: `${serviceName} chez ${salonName} demain à ${timeStr}`,
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
                    title: "Rappel : RDV demain ! 📋",
                    body: `${serviceName} chez ${salonName} demain à ${timeStr}`,
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

            // Save in-app notification for owner
            await db.collection("notifications").add({
                userId: ownerId,
                title: "Nouvelle commande boutique",
                body: `${clientName} a commandé ${itemCount} article${itemCount > 1 ? "s" : ""} pour ${grandTotal} MAD`,
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
                        title: "🛍️ Nouvelle commande",
                        body: `${clientName} — ${itemCount} article${itemCount > 1 ? "s" : ""} · ${grandTotal} MAD`,
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
        let title = "";
        let body = "";

        switch (newStatus) {
            case "confirmed":
                title = "Commande confirmée ✅";
                body = "Votre commande a été confirmée par le salon.";
                break;
            case "delivered":
                title = "Commande livrée 📦";
                body = "Votre commande a été marquée comme livrée.";
                break;
            case "cancelled":
                title = "Commande annulée ❌";
                body = "Votre commande a été annulée par le salon.";
                break;
            default:
                return;
        }

        try {
            const clientDoc = await db.collection("users").doc(clientId).get();
            if (!clientDoc.exists) return;

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

            // Save in-app notification
            await db.collection("notifications").add({
                userId: ownerId,
                title: "⚠️ Stock bas",
                body: `${productName} — il ne reste que ${newStock} unité${newStock > 1 ? "s" : ""}`,
                type: "low_stock",
                salonId: salonId,
                isRead: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            if (fcmToken) {
                await messaging.send({
                    token: fcmToken,
                    notification: {
                        title: "⚠️ Stock bas",
                        body: `${productName} — ${newStock} restant${newStock > 1 ? "s" : ""}`,
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
// ============================================================
export const generateDailySummary = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Auth required");
    }

    const salonId: string = data.salonId;
    if (!salonId) {
        throw new functions.https.HttpsError("invalid-argument", "salonId required");
    }

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

        // Fetch all salon appointments in one query (no composite index needed)
        const allApptsSnap = await db.collection("appointments")
            .where("salonId", "==", salonId)
            .get();

        const allAppts = allApptsSnap.docs.map(d => d.data());

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

        // Most popular service this week
        const serviceCounts: Record<string, number> = {};
        for (const a of weekAppts) {
            const name = a.serviceName || "Autre";
            serviceCounts[name] = (serviceCounts[name] || 0) + 1;
        }
        const topService = Object.entries(serviceCounts)
            .sort((a, b) => b[1] - a[1])[0];

        // Reviews (single-field query, sort in code to avoid composite index)
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

        const dayNames = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"];
        const todayName = dayNames[now.getDay()];

        const prompt = `Tu es l'assistant IA du salon "${salon.name}". Génère un résumé concis et motivant pour le propriétaire. Parle en français, tutoie-le. Sois bref (3-4 phrases max). Pas de bullet points, juste du texte fluide.

Données du jour (${todayName}) :
- ${todayCount} RDV aujourd'hui (${todayUpcoming} à venir, ${todayCompleted} terminés)
- Revenu aujourd'hui : ${todayRevenue} MAD

Données de la semaine :
- ${weekCount} RDV cette semaine (${weekCancelled} annulés)
- Revenu semaine : ${weekRevenue} MAD
- Variation vs semaine dernière : ${weekChange > 0 ? "+" : ""}${weekChange}% en RDV, ${revenueChange > 0 ? "+" : ""}${revenueChange}% en revenu
${topService ? `- Service le plus demandé : ${topService[0]} (${topService[1]} fois)` : ""}

${recentReviews.length > 0 ? `Derniers avis : ${recentReviews.map(r => `${r.rating}★${r.comment ? " - " + r.comment : ""}`).join(" | ")}` : "Pas d'avis récents."}

Donne un résumé encourageant avec un conseil actionnable si pertinent (ex: créneau vide à combler, service populaire à mettre en avant, etc).`;

        // ── Call Gemini ──
        const apiKey = process.env.GEMINI_API_KEY;
        if (!apiKey) {
            throw new functions.https.HttpsError("failed-precondition", "GEMINI_API_KEY not set in .env");
        }

        const genAI = new GoogleGenerativeAI(apiKey);
        const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });
        const result = await model.generateContent(prompt);
        const summary = result.response.text();

        return { summary, generatedAt: now.toISOString() };
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
                    promos.push({
                        clientId: c.id,
                        clientName: c.name,
                        reason: "win_back",
                        discountPercent: winBackPct,
                        title: `${c.name}, tu nous manques !`,
                        description: `Cela fait ${absentDays} jours ! Profite de -${winBackPct}% sur ta prochaine visite.`,
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
                    promos.push({
                        clientId: c.id,
                        clientName: c.name,
                        reason: "loyal",
                        discountPercent: loyalPct,
                        title: `Merci pour ta fidélité, ${c.name} !`,
                        description: `${c.visits} visites chez nous ! Voici -${loyalPct}% pour te remercier.`,
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
                    promos.push({
                        clientId: c.id,
                        clientName: c.name,
                        reason: "top_client",
                        discountPercent: topPct,
                        title: `${c.name}, notre meilleur client du mois !`,
                        description: `${topClient[1]} visites ce mois-ci ! Profite de -${topPct}% en récompense.`,
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

                            if (fcmToken) {
                                await messaging.send({
                                    token: fcmToken,
                                    notification: {
                                        title: `${salon.name} - Offre spéciale pour toi !`,
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
                                title: `${salon.name} - Offre spéciale`,
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
