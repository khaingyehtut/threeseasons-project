import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/banner_model.dart';

class BannerService {
  static final BannerService _instance = BannerService._internal();
  factory BannerService() => _instance;
  BannerService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<BannerModel>> activeBannersStream() {
    return _db
        .collection('banners')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(BannerModel.fromDoc).toList();
      list.sort((a, b) => a.order.compareTo(b.order));
      return list;
    });
  }

  Stream<List<BannerModel>> allBannersStream() {
    return _db.collection('banners').snapshots().map((snap) {
      final list = snap.docs.map(BannerModel.fromDoc).toList();
      list.sort((a, b) => a.order.compareTo(b.order));
      return list;
    });
  }

  Future<BannerModel> createBanner({
    required String imageUrl,
    String title = '',
    String subtitle = '',
    bool isActive = true,
    int order = 0,
  }) async {
    final ref = await _db.collection('banners').add({
      'imageUrl': imageUrl,
      'title': title,
      'subtitle': subtitle,
      'isActive': isActive,
      'order': order,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final doc = await ref.get();
    return BannerModel.fromDoc(doc);
  }

  Future<void> updateBanner(String id, Map<String, dynamic> data) async {
    await _db.collection('banners').doc(id).update(data);
  }

  Future<void> deleteBanner(String id) async {
    await _db.collection('banners').doc(id).delete();
  }

  Future<void> toggleActive(String id, bool isActive) async {
    await _db.collection('banners').doc(id).update({'isActive': isActive});
  }
}
