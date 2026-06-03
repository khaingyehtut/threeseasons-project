import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/announcement_model.dart';

class AnnouncementService {
  static final AnnouncementService _instance = AnnouncementService._internal();
  factory AnnouncementService() => _instance;
  AnnouncementService._internal();

  final _db = FirebaseFirestore.instance;

  Future<List<AnnouncementModel>> getActiveAnnouncements() async {
    final snap = await _db
        .collection('announcements')
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(10)
        .get();

    return snap.docs
        .map((doc) =>
            AnnouncementModel.fromJson({'id': doc.id, ...doc.data()}))
        .toList();
  }

  Stream<List<AnnouncementModel>> streamAll() {
    return _db
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) =>
                AnnouncementModel.fromJson({'id': doc.id, ...doc.data()}))
            .toList());
  }

  Future<void> create(Map<String, dynamic> data) async {
    data['createdAt'] = FieldValue.serverTimestamp();
    data['isActive'] = true;
    await _db.collection('announcements').add(data);
  }

  Future<void> toggleActive(String id, bool isActive) async {
    await _db
        .collection('announcements')
        .doc(id)
        .update({'isActive': isActive});
  }

  Future<void> delete(String id) async {
    await _db.collection('announcements').doc(id).delete();
  }
}
