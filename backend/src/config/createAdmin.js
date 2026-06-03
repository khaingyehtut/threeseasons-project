/**
 * Run this script once to create your admin account.
 *
 *   cd backend
 *   node src/config/createAdmin.js
 *
 * Change ADMIN_NAME, ADMIN_EMAIL and ADMIN_PASSWORD below before running.
 */

const path = require("path");
const fs = require("fs");
require("dotenv").config({ path: path.join(__dirname, "../../.env") });

const admin = require("firebase-admin");

// ─── Change these before running ─────────────────────────────────────────────
const ADMIN_NAME = "Admin";
const ADMIN_EMAIL = "admin@threeseasons.com";
const ADMIN_PASSWORD = "Admin@123";
// ─────────────────────────────────────────────────────────────────────────────

// Init Firebase Admin (reuse serviceAccountKey.json if present)
if (!admin.apps.length) {
  const keyFile = path.join(__dirname, "../../serviceAccountKey.json");
  if (fs.existsSync(keyFile)) {
    admin.initializeApp({
      credential: admin.credential.cert(require(keyFile)),
    });
  } else {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: process.env.FIREBASE_PROJECT_ID,
        clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
        privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, "\n"),
      }),
    });
  }
}

const db = admin.firestore();
const auth = admin.auth();

async function createAdmin() {
  console.log(`\nCreating admin: ${ADMIN_EMAIL} …`);

  let uid;

  // 1. Create Firebase Auth user (or fetch if already exists)
  try {
    const user = await auth.createUser({
      displayName: ADMIN_NAME,
      email: ADMIN_EMAIL,
      password: ADMIN_PASSWORD,
    });
    uid = user.uid;
    console.log(`✅ Auth user created  uid=${uid}`);
  } catch (err) {
    if (err.code === "auth/email-already-exists") {
      const existing = await auth.getUserByEmail(ADMIN_EMAIL);
      uid = existing.uid;
      console.log(`ℹ️  Auth user already exists  uid=${uid}`);
    } else {
      throw err;
    }
  }

  // 2. Write / overwrite Firestore profile with role = 'admin'
  await db.collection("users").doc(uid).set(
    {
      name: ADMIN_NAME,
      email: ADMIN_EMAIL,
      phone: "",
      avatar: "",
      role: "admin",
      address: {},
      isOnline: false,
      wishlist: [],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true } // keep any existing fields intact
  );

  console.log(`✅ Firestore doc  users/${uid}  role=admin`);
  console.log("\n─────────────────────────────────────────");
  console.log(`  Email    : ${ADMIN_EMAIL}`);
  console.log(`  Password : ${ADMIN_PASSWORD}`);
  console.log("─────────────────────────────────────────");
  console.log("\nLogin with these credentials in the app.\n");
}

createAdmin()
  .catch((err) => {
    console.error("❌ Error:", err.message);
    process.exit(1);
  })
  .finally(() => process.exit(0));
