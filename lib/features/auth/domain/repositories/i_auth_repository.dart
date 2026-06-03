import 'package:firebase_auth/firebase_auth.dart';
import 'package:three_seasons_project/features/auth/data/models/user_model.dart';

abstract class IAuthRepository {
  Stream<User?> get authStateChanges;
  User? get currentUser;
  Future<UserModel> register(String name, String email, String password, String phone);
  Future<UserModel> login(String email, String password);
  Future<void> logout();
  Future<UserModel> getProfile();
  Future<UserModel> updateProfile(Map<String, dynamic> data);
  Future<void> changePassword(String currentPassword, String newPassword);
  Future<List<String>> toggleWishlist(String productId);
  Future<String?> getIdToken();
}
