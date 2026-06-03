import 'package:get/get.dart';
import '../models/announcement_model.dart';
import '../services/announcement_service.dart';

class AnnouncementController extends GetxController {
  final _service = AnnouncementService();

  final announcements = <AnnouncementModel>[].obs;
  final isLoading = false.obs;

  Future<void> fetchActive() async {
    isLoading.value = true;
    try {
      announcements.value = await _service.getActiveAnnouncements();
    } catch (_) {
    } finally {
      isLoading.value = false;
    }
  }
}
