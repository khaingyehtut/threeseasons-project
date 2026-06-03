import 'package:firebase_auth/firebase_auth.dart';
import 'package:three_seasons_project/features/auth/data/models/user_model.dart';
import 'package:three_seasons_project/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:three_seasons_project/services/auth_service.dart';

class AuthRepository implements IAuthRepository {
  final AuthService _service;

  AuthRepository({AuthService? service}) : _service = service ?? AuthService();

  @override
  Stream<User?> get authStateChanges => _service.authStateChanges;

  @override
  User? get currentUser => _service.currentUser;

  @override
  Future<UserModel> register(
    String name,
    String email,
    String password,
    String phone,
  ) => _service.register(name, email, password, phone);

  @override
  Future<UserModel> login(String email, String password) =>
      _service.login(email, password);

  @override
  Future<void> logout() => _service.logout();

  @override
  Future<UserModel> getProfile() => _service.getProfile();

  @override
  Future<UserModel> updateProfile(Map<String, dynamic> data) =>
      _service.updateProfile(data);

  @override
  Future<void> changePassword(String currentPassword, String newPassword) =>
      _service.changePassword(currentPassword, newPassword);

  @override
  Future<List<String>> toggleWishlist(String productId) =>
      _service.toggleWishlist(productId);

  @override
  Future<String?> getIdToken() => _service.getIdToken();
}
