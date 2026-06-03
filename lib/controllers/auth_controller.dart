import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';

class AuthController extends GetxController {
  final _authService = AuthService();

  final user = Rxn<UserModel>();
  final wishlist = <String>[].obs;
  final isLoading = false.obs;
  final error = Rxn<String>();

  bool get isLoggedIn => user.value != null;
  bool get isAdmin => user.value?.isAdmin ?? false;
  bool isFavorite(String productId) => wishlist.contains(productId);

  Future<void> initialize() async {
    isLoading.value = true;
    error.value = null;
    try {
      final fbUser = FirebaseAuth.instance.currentUser;
      if (fbUser != null) {
        user.value = await _authService.getProfile();
        wishlist.value = List<String>.from(user.value?.wishlist ?? []);
        _saveFcmToken(fbUser.uid);
      }
    } catch (e) {
      user.value = null;
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> login(String email, String password) async {
    isLoading.value = true;
    error.value = null;
    try {
      user.value = await _authService.login(email, password);
      wishlist.value = List<String>.from(user.value?.wishlist ?? []);
      if (user.value != null) _saveFcmToken(user.value!.id);
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> retryFcmToken() async {
    final uid = user.value?.id;
    if (uid != null) await _saveFcmToken(uid);
  }

  Future<void> _saveFcmToken(String uid) async {
    try {
      final token = await NotificationService().getToken();
      if (token == null) {
        debugPrint('[FCM] token is null — permission denied or Play Services unavailable');
        return;
      }
      // Use set+merge so it works even if the doc was just created
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'fcmToken': token}, SetOptions(merge: true));
      debugPrint('[FCM] token saved for uid=$uid');
    } catch (e) {
      debugPrint('[FCM] _saveFcmToken failed: $e');
    }
  }

  Future<bool> register(
    String name,
    String email,
    String password,
    String phone,
  ) async {
    isLoading.value = true;
    error.value = null;
    try {
      user.value = await _authService.register(name, email, password, phone);
      if (user.value != null) _saveFcmToken(user.value!.id);
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> logout() async {
    isLoading.value = true;
    try {
      await _authService.logout();
    } catch (_) {}
    user.value = null;
    wishlist.clear();
    error.value = null;
    isLoading.value = false;
  }

  Future<bool> updateProfile(Map<String, dynamic> data) async {
    isLoading.value = true;
    error.value = null;
    try {
      user.value = await _authService.updateProfile(data);
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> changePassword(String currentPassword, String newPassword) async {
    isLoading.value = true;
    error.value = null;
    try {
      await _authService.changePassword(currentPassword, newPassword);
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> toggleWishlist(String productId) async {
    // Optimistic update
    if (wishlist.contains(productId)) {
      wishlist.remove(productId);
    } else {
      wishlist.add(productId);
    }
    try {
      final updated = await _authService.toggleWishlist(productId);
      wishlist.value = updated;
    } catch (e) {
      // Revert on failure
      if (wishlist.contains(productId)) {
        wishlist.remove(productId);
      } else {
        wishlist.add(productId);
      }
      error.value = e.toString();
    }
  }

  Future<bool> sendPasswordReset(String email) async {
    isLoading.value = true;
    error.value = null;
    try {
      await _authService.sendPasswordResetEmail(email);
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  void clearError() => error.value = null;
}
