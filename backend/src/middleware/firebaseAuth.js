const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');
require('dotenv').config();

// Initialize Firebase Admin SDK exactly once.
// Priority: serviceAccountKey.json file in backend root > .env variables
if (!admin.apps.length) {
  const keyFilePath = path.join(__dirname, '../../serviceAccountKey.json');

  if (fs.existsSync(keyFilePath)) {
    // Use the downloaded JSON file directly (recommended)
    const serviceAccount = require(keyFilePath);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    console.log('✅ Firebase Admin initialized from serviceAccountKey.json');
  } else {
    // Fallback: use individual .env variables
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: process.env.FIREBASE_PROJECT_ID,
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
      }),
    });
    console.log('✅ Firebase Admin initialized from .env variables');
  }
}

/**
 * Express middleware that verifies a Firebase ID token supplied as a Bearer
 * token in the Authorization header.
 *
 * On success  : sets req.user to the decoded token payload and calls next().
 * On failure  : responds with 401 JSON and does NOT call next().
 */
async function firebaseAuth(req, res, next) {
  const authHeader = req.headers.authorization || '';

  if (!authHeader.startsWith('Bearer ')) {
    return res.status(401).json({
      success: false,
      message: 'Unauthorized: missing or malformed Authorization header.',
    });
  }

  const token = authHeader.split('Bearer ')[1].trim();

  if (!token) {
    return res.status(401).json({
      success: false,
      message: 'Unauthorized: token is empty.',
    });
  }

  try {
    const decoded = await admin.auth().verifyIdToken(token);
    req.user = decoded; // { uid, email, name, picture, ... }
    next();
  } catch (err) {
    console.error('Firebase token verification failed:', err.message);
    return res.status(401).json({
      success: false,
      message: 'Unauthorized: invalid or expired token.',
    });
  }
}

module.exports = firebaseAuth;
