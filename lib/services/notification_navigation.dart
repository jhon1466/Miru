import '../utils/notification_routing.dart';

/// Navegación desde push o notificación local.
class NotificationNavigation {
  static void handlePayload(String payload) => NotificationRouting.handlePayload(payload);
}
