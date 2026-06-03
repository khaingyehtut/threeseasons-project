import 'app_router.dart';

/// Global navigation helpers — no BuildContext or GetX needed.
/// Use these everywhere instead of Navigator.pushNamed / Get.toNamed.

void goTo(String path, {Object? extra}) =>
    AppRouter.router.go(path, extra: extra);

void pushTo(String path, {Object? extra}) =>
    AppRouter.router.push(path, extra: extra);

void goBack() => AppRouter.router.pop();
