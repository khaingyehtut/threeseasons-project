const express  = require('express');
const admin    = require('firebase-admin');
const firebaseAuth = require('../middleware/firebaseAuth');

const router = express.Router();

// ── Helper ────────────────────────────────────────────────────────────────────

async function sendToToken(token, title, body, data = {}) {
  if (!token) return null;
  // FCM requires all data values to be strings
  const stringData = Object.fromEntries(
    Object.entries(data).map(([k, v]) => [k, String(v)])
  );
  return admin.messaging().send({
    token,
    notification: { title, body },
    data: stringData,
    android: { priority: 'high', notification: { sound: 'notification_sound', channelId: 'three_seasons_v3' } },
    apns:    { payload: { aps: { sound: 'notification_sound.aiff', badge: 1 } } },
  });
}

// ── POST /api/notifications/send ─────────────────────────────────────────────
// Send to a single FCM token.
// Body: { token, title, body, data? }
router.post('/send', firebaseAuth, async (req, res) => {
  const { token, title, body, data } = req.body;
  if (!token || !title || !body) {
    return res.status(400).json({ success: false, message: 'token, title and body are required.' });
  }
  try {
    const result = await sendToToken(token, title, body, data);
    return res.json({ success: true, messageId: result });
  } catch (e) {
    // Invalid or expired FCM tokens are expected — treat as a soft failure, not a server error.
    const invalidTokenCodes = [
      'messaging/invalid-registration-token',
      'messaging/registration-token-not-registered',
      'messaging/invalid-argument',
    ];
    const isInvalidToken = invalidTokenCodes.some(c => e.code === c || (e.message || '').includes(c));
    if (isInvalidToken) {
      console.warn('[FCM] invalid/expired token — skipping:', e.code || e.message);
      return res.json({ success: false, reason: 'invalid-token', message: e.message });
    }
    console.error('[FCM] send failed:', e.message);
    return res.status(500).json({ success: false, message: e.message });
  }
});

// ── POST /api/notifications/send-to-users ────────────────────────────────────
// Fetch all regular user FCM tokens from Firestore and send to each.
// Body: { title, body, data? }
router.post('/send-to-users', firebaseAuth, async (req, res) => {
  const { title, body, data } = req.body;
  if (!title || !body) {
    return res.status(400).json({ success: false, message: 'title and body are required.' });
  }
  try {
    const snap = await admin.firestore()
      .collection('users')
      .where('role', '==', 'user')
      .get();

    console.log(`[FCM] Found ${snap.docs.length} regular user(s) in Firestore`);

    const tokens = snap.docs
      .map(d => d.data().fcmToken)
      .filter(t => t && t.length > 0);

    if (tokens.length === 0) {
      console.warn('[FCM] No user FCM tokens found');
      return res.json({ success: true, message: 'No user tokens found.', sent: 0, total: 0 });
    }

    const results = await Promise.allSettled(
      tokens.map(t => sendToToken(t, title, body, data))
    );

    const sent = results.filter(r => r.status === 'fulfilled').length;
    console.log(`[FCM] announcement sent to ${sent}/${tokens.length} users`);
    return res.json({ success: true, sent, total: tokens.length });
  } catch (e) {
    console.error('[FCM] send-to-users failed:', e.message);
    return res.status(500).json({ success: false, message: e.message });
  }
});

// ── POST /api/notifications/send-to-admins ───────────────────────────────────
// Fetch all admin FCM tokens from Firestore and send to each.
// Body: { title, body, data? }
router.post('/send-to-admins', firebaseAuth, async (req, res) => {
  const { title, body, data } = req.body;
  if (!title || !body) {
    return res.status(400).json({ success: false, message: 'title and body are required.' });
  }
  try {
    const snap = await admin.firestore()
      .collection('users')
      .where('role', '==', 'admin')
      .get();

    console.log(`[FCM] Found ${snap.docs.length} admin user(s) in Firestore`);

    const tokens = snap.docs
      .map(d => {
        const token = d.data().fcmToken;
        console.log(`[FCM] Admin uid=${d.id} fcmToken=${token ? token.substring(0, 20) + '...' : 'MISSING'}`);
        return token;
      })
      .filter(t => t && t.length > 0);

    if (tokens.length === 0) {
      console.warn('[FCM] No admin FCM tokens found — admin must log in on device first');
      return res.json({ success: true, message: 'No admin tokens found.' });
    }

    const results = await Promise.allSettled(
      tokens.map(t => sendToToken(t, title, body, data))
    );

    const sent = results.filter(r => r.status === 'fulfilled').length;
    console.log(`[FCM] sent to ${sent}/${tokens.length} admins`);
    return res.json({ success: true, sent, total: tokens.length });
  } catch (e) {
    console.error('[FCM] send-to-admins failed:', e.message);
    return res.status(500).json({ success: false, message: e.message });
  }
});

module.exports = router;
