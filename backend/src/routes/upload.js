const express = require('express');
const multer  = require('multer');
const path    = require('path');
const crypto  = require('crypto');
const fs      = require('fs');
const firebaseAuth = require('../middleware/firebaseAuth');

const router = express.Router();

// Save product images to backend/productImages/
const UPLOADS_DIR = path.join(__dirname, '../../productImages');
if (!fs.existsSync(UPLOADS_DIR)) {
  fs.mkdirSync(UPLOADS_DIR, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, UPLOADS_DIR),
  filename:    (_req, file, cb) => {
    const ext    = path.extname(file.originalname).toLowerCase();
    const random = crypto.randomBytes(8).toString('hex');
    cb(null, `${Date.now()}-${random}${ext}`);
  },
});

const ALLOWED = ['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp'];

const fileFilter = (_req, file, cb) => {
  if (ALLOWED.includes(file.mimetype)) {
    cb(null, true);
  } else {
    cb(new Error(`Unsupported file type "${file.mimetype}". Only jpeg, png, gif, and webp images are allowed.`));
  }
};

const upload = multer({ storage, fileFilter, limits: { fileSize: 10 * 1024 * 1024 } }); // 10 MB

// POST /api/upload
router.post('/', firebaseAuth, (req, res) => {
  console.log(`[Upload] Request received from uid=${req.user?.uid}`);

  upload.single('file')(req, res, (err) => {
    if (err instanceof multer.MulterError) {
      console.error('[Upload] Multer error:', err.code, err.message);
      if (err.code === 'LIMIT_FILE_SIZE') {
        return res.status(400).json({ success: false, message: 'File too large. Max 10 MB.' });
      }
      return res.status(400).json({ success: false, message: err.message });
    }
    if (err) {
      console.error('[Upload] Error:', err.message);
      return res.status(400).json({ success: false, message: err.message || 'Upload failed.' });
    }
    if (!req.file) {
      console.warn('[Upload] No file in request. Fields received:', Object.keys(req.body));
      return res.status(400).json({ success: false, message: 'No file provided. Use field name "file".' });
    }

    const port = process.env.PORT || 5001;
    // Use Mac LAN IP so real devices can load the image
    const host = process.env.SERVER_HOST || '192.168.0.112';
    const url  = `http://${host}:${port}/productImages/${req.file.filename}`;

    console.log(`[Upload] ✅ Saved: ${req.file.filename}  (${(req.file.size / 1024).toFixed(1)} KB)`);
    console.log(`[Upload] URL: ${url}`);

    return res.status(201).json({ success: true, url, filename: req.file.filename });
  });
});

// DELETE /api/upload/:filename
router.delete('/:filename', firebaseAuth, (req, res) => {
  const { filename } = req.params;

  // Prevent path traversal attacks
  if (filename.includes('/') || filename.includes('..')) {
    return res.status(400).json({ success: false, message: 'Invalid filename.' });
  }

  const filePath = path.join(UPLOADS_DIR, filename);

  if (!fs.existsSync(filePath)) {
    // Already gone — treat as success
    return res.status(200).json({ success: true, message: 'File not found (already deleted).' });
  }

  try {
    fs.unlinkSync(filePath);
    console.log(`[Upload] 🗑️  Deleted: ${filename}`);
    return res.status(200).json({ success: true, message: 'File deleted.' });
  } catch (e) {
    console.error('[Upload] Delete failed:', e.message);
    return res.status(500).json({ success: false, message: 'Could not delete file.' });
  }
});

module.exports = router;
