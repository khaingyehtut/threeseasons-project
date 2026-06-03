import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  // ─── Register ────────────────────────────────────────────────────────────────

  Future<UserModel> register(
    String name,
    String email,
    String password,
    String phone,
  ) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user!;

      await user.updateDisplayName(name);

      final userDoc = {
        'name': name,
        'email': email,
        'phone': phone,
        'role': 'user',
        'avatar': '',
        'address': <String, dynamic>{},
        'wishlist': <String>[],
        'isOnline': true,
        'createdAt': FieldValue.serverTimestamp(),
        'lastSeen': FieldValue.serverTimestamp(),
      };

      await _db.collection('users').doc(user.uid).set(userDoc);

      return UserModel(
        id: user.uid,
        name: name,
        email: email,
        role: 'user',
        avatar: '',
        phone: phone,
        address: {},
        isOnline: true,
      );
    } on FirebaseAuthException catch (e) {
      throw _authError(e);
    }
  }

  // ─── Login ───────────────────────────────────────────────────────────────────

  Future<UserModel> login(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = credential.user!.uid;

      await _db.collection('users').doc(uid).update({
        'isOnline': true,
        'lastSeen': FieldValue.serverTimestamp(),
      });

      final doc = await _db.collection('users').doc(uid).get();
      return _userFromDoc(doc);
    } on FirebaseAuthException catch (e) {
      throw _authError(e);
    }
  }

  // ─── Logout ──────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      await _db.collection('users').doc(uid).update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    }
    await _auth.signOut();
  }

  // ─── Get Profile ─────────────────────────────────────────────────────────────

  Future<UserModel> getProfile() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');

    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) throw Exception('User profile not found');
    return _userFromDoc(doc);
  }

  // ─── Update Profile ───────────────────────────────────────────────────────────

  Future<UserModel> updateProfile(Map<String, dynamic> data) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');

    // Prevent overwriting protected fields
    data.remove('role');
    data.remove('email');
    data.remove('createdAt');

    await _db.collection('users').doc(uid).update(data);

    final doc = await _db.collection('users').doc(uid).get();
    return _userFromDoc(doc);
  }

  // ─── Forgot Password ─────────────────────────────────────────────────────────

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw _authError(e);
    }
  }

  // ─── Change Password ──────────────────────────────────────────────────────────

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw _authError(e);
    }
  }

  // ─── Toggle Wishlist ──────────────────────────────────────────────────────────

  Future<List<String>> toggleWishlist(String productId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated');

    final docRef = _db.collection('users').doc(uid);
    final doc = await docRef.get();
    final data = doc.data() ?? {};
    final wishlist = List<String>.from(data['wishlist'] ?? []);

    if (wishlist.contains(productId)) {
      await docRef.update({
        'wishlist': FieldValue.arrayRemove([productId]),
      });
      wishlist.remove(productId);
    } else {
      await docRef.update({
        'wishlist': FieldValue.arrayUnion([productId]),
      });
      wishlist.add(productId);
    }

    return wishlist;
  }

  // ─── Get Firebase ID Token (for upload server) ───────────────────────────────

  Future<String?> getIdToken() async {
    return await _auth.currentUser?.getIdToken();
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  UserModel _userFromDoc(DocumentSnapshot doc) {
    final data = Map<String, dynamic>.from(doc.data() as Map);

    DateTime? lastSeen;
    final rawLastSeen = data['lastSeen'];
    if (rawLastSeen is Timestamp) {
      lastSeen = rawLastSeen.toDate();
    }

    Map<String, dynamic>? address;
    final rawAddress = data['address'];
    if (rawAddress is Map) {
      address = Map<String, dynamic>.from(rawAddress);
    }

    return UserModel(
      id: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      role: data['role'] ?? 'user',
      avatar: data['avatar'] ?? '',
      phone: data['phone'] ?? '',
      address: address,
      isOnline: data['isOnline'] ?? false,
      lastSeen: lastSeen,
      wishlist: List<String>.from(data['wishlist'] ?? []),
    );
  }

  String _authError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email address.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'invalid-credential':
        return 'Invalid email or password. Please try again.';
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'invalid-email':
        return 'The email address is not valid.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      case 'requires-recent-login':
        return 'Please log in again before changing your password.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      default:
        return e.message ?? 'Authentication error. Please try again.';
    }
  }
}
