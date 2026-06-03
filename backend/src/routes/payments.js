const express  = require('express');
const multer   = require('multer');
const path     = require('path');
const crypto   = require('crypto');
const fs       = require('fs');
const admin    = require('firebase-admin');
const firebaseAuth = require('../middleware/firebaseAuth');

const router = express.Router();

// ── Storage ───────────────────────────────────────────────────────────────────
const SCREENSHOTS_DIR = path.join(__dirname, '../../paymentScreenshots');
if (!fs.existsSync(SCREENSHOTS_DIR)) fs.mkdirSync(SCREENSHOTS_DIR, { recursive: true });

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, SCREENSHOTS_DIR),
  filename:    (_req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    cb(null, `${Date.now()}-${crypto.randomBytes(8).toString('hex')}${ext}`);
  },
});

const ALLOWED = ['image/jpeg', 'image/jpg', 'image/png', 'image/webp'];
const fileFilter = (_req, file, cb) =>
  ALLOWED.includes(file.mimetype) ? cb(null, true)
    : cb(new multer.MulterError('LIMIT_UNEXPECTED_FILE', 'Only jpeg/png/webp allowed.'));

const upload = multer({ storage, fileFilter, limits: { fileSize: 10 * 1024 * 1024 } });

function serverBase() {
  const host = process.env.SERVER_HOST || '192.168.0.112';
  const port = process.env.PORT || 5001;
  return `http://${host}:${port}`;
}

// ── POST /api/payments/upload ─────────────────────────────────────────────────
router.post('/upload', firebaseAuth, (req, res) => {
  upload.single('screenshot')(req, res, async (err) => {
    if (err instanceof multer.MulterError) {
      if (err.code === 'LIMIT_FILE_SIZE')
        return res.status(400).json({ success: false, message: 'File too large. Max 10 MB.' });
      return res.status(400).json({ success: false, message: err.message });
    }
    if (err) return res.status(400).json({ success: false, message: err.message });
    if (!req.file) return res.status(400).json({ success: false, message: 'Screenshot is required.' });

    const { amount, paymentMethod, orderId, note } = req.body;
    if (!amount || !paymentMethod)
      return res.status(400).json({ success: false, message: 'amount and paymentMethod are required.' });

    const screenshotUrl = `${serverBase()}/paymentScreenshots/${req.file.filename}`;

    try {
      const docRef = await admin.firestore().collection('payments').add({
        userId:             req.user.uid,
        orderId:            orderId || null,
        amount:             parseFloat(amount),
        paymentMethod,
        screenshotUrl,
        screenshotFilename: req.file.filename,
        note:               note || '',
        status:             'pending',
        adminNote:          '',
        createdAt:          admin.firestore.FieldValue.serverTimestamp(),
        updatedAt:          admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`[Payment] ✅ Created ${docRef.id} uid=${req.user.uid}`);
      return res.status(201).json({ success: true, paymentId: docRef.id, screenshotUrl });
    } catch (e) {
      console.error('[Payment] Firestore error:', e.message);
      return res.status(500).json({ success: false, message: 'Failed to save payment record.' });
    }
  });
});

// ── PATCH /api/payments/:id/approve ──────────────────────────────────────────
router.patch('/:id/approve', firebaseAuth, async (req, res) => {
  try {
    const callerDoc = await admin.firestore().collection('users').doc(req.user.uid).get();
    if (callerDoc.data()?.role !== 'admin')
      return res.status(403).json({ success: false, message: 'Admin access required.' });

    const paymentRef = admin.firestore().collection('payments').doc(req.params.id);
    const paymentDoc = await paymentRef.get();
    if (!paymentDoc.exists)
      return res.status(404).json({ success: false, message: 'Payment not found.' });
    if (paymentDoc.data().status !== 'pending')
      return res.status(400).json({ success: false, message: 'Payment already processed.' });

    const { adminNote } = req.body;
    await paymentRef.update({
      status:     'approved',
      adminNote:  adminNote || '',
      approvedBy: req.user.uid,
      updatedAt:  admin.firestore.FieldValue.serverTimestamp(),
    });

    const { userId, paymentMethod, amount } = paymentDoc.data();
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    const fcmToken = userDoc.data()?.fcmToken;

    const notifBody = `Your ${paymentMethod} payment of ${amount} MMK has been approved! ✅`;

    if (fcmToken) {
      await admin.messaging().send({
        token: fcmToken,
        notification: { title: 'Payment Approved ✅', body: notifBody },
        data: { type: 'payment_approved', paymentId: req.params.id },
        android: { priority: 'high', notification: { channelId: 'three_seasons_v3' } },
      }).catch(e => console.warn('[FCM] notify failed:', e.message));
    }

    const approveExpireAt = new Date();
    approveExpireAt.setDate(approveExpireAt.getDate() + 30);
    await admin.firestore().collection('notifications').add({
      userId, title: 'Payment Approved ✅', body: notifBody,
      type: 'payment_approved', data: { paymentId: req.params.id },
      isRead: false, createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expireAt: admin.firestore.Timestamp.fromDate(approveExpireAt),
    });

    console.log(`[Payment] ✅ Approved ${req.params.id}`);
    return res.json({ success: true, message: 'Payment approved.' });
  } catch (e) {
    console.error('[Payment] Approve error:', e.message);
    return res.status(500).json({ success: false, message: e.message });
  }
});

// ── PATCH /api/payments/:id/reject ────────────────────────────────────────────
router.patch('/:id/reject', firebaseAuth, async (req, res) => {
  try {
    const callerDoc = await admin.firestore().collection('users').doc(req.user.uid).get();
    if (callerDoc.data()?.role !== 'admin')
      return res.status(403).json({ success: false, message: 'Admin access required.' });

    const paymentRef = admin.firestore().collection('payments').doc(req.params.id);
    const paymentDoc = await paymentRef.get();
    if (!paymentDoc.exists)
      return res.status(404).json({ success: false, message: 'Payment not found.' });
    if (paymentDoc.data().status !== 'pending')
      return res.status(400).json({ success: false, message: 'Payment already processed.' });

    const { adminNote } = req.body;
    await paymentRef.update({
      status:     'rejected',
      adminNote:  adminNote || '',
      rejectedBy: req.user.uid,
      updatedAt:  admin.firestore.FieldValue.serverTimestamp(),
    });

    const { userId, paymentMethod, amount } = paymentDoc.data();
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    const fcmToken = userDoc.data()?.fcmToken;
    const notifBody = `Your ${paymentMethod} payment of ${amount} MMK was rejected.${adminNote ? ' Reason: ' + adminNote : ''}`;

    if (fcmToken) {
      await admin.messaging().send({
        token: fcmToken,
        notification: { title: 'Payment Rejected ❌', body: notifBody },
        data: { type: 'payment_rejected', paymentId: req.params.id },
        android: { priority: 'high', notification: { channelId: 'three_seasons_v3' } },
      }).catch(e => console.warn('[FCM] notify failed:', e.message));
    }

    const rejectExpireAt = new Date();
    rejectExpireAt.setDate(rejectExpireAt.getDate() + 30);
    await admin.firestore().collection('notifications').add({
      userId, title: 'Payment Rejected ❌', body: notifBody,
      type: 'payment_rejected', data: { paymentId: req.params.id },
      isRead: false, createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expireAt: admin.firestore.Timestamp.fromDate(rejectExpireAt),
    });

    console.log(`[Payment] ❌ Rejected ${req.params.id}`);
    return res.json({ success: true, message: 'Payment rejected.' });
  } catch (e) {
    console.error('[Payment] Reject error:', e.message);
    return res.status(500).json({ success: false, message: e.message });
  }
});

module.exports = router;
