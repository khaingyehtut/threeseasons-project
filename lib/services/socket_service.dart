import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../core/constants.dart';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  io.Socket? _socket;

  bool get isConnected => _socket?.connected == true;

  void connect() {
    if (_socket != null) {
      // Reuse existing socket instance — reconnect only if currently disconnected
      if (!isConnected) _socket!.connect();
      return;
    }
    _socket = io.io(
      AppConstants.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling']) // polling as fallback
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(5)
          .setReconnectionDelay(2000)
          .build(),
    );
    _socket!.onConnect((_) => debugPrint('[Socket] connected to ${AppConstants.socketUrl}'));
    _socket!.onDisconnect((_) => debugPrint('[Socket] disconnected'));
    _socket!.onConnectError((e) => debugPrint('[Socket] connect error: $e'));
    _socket!.connect();
  }

  void disconnect() {
    _socket?.disconnect();
    _socket = null;
  }

  void joinConversation(String conversationId) {
    _ensureConnected();
    _socket?.emit('join_conversation', conversationId);
  }

  void leaveConversation(String conversationId) {
    _socket?.emit('leave_conversation', conversationId);
  }

  void emitTyping(String conversationId, String userId) {
    _ensureConnected();
    _socket?.emit('typing', {'conversationId': conversationId, 'userId': userId});
  }

  void emitStopTyping(String conversationId, String userId) {
    _ensureConnected();
    _socket?.emit('stop_typing', {'conversationId': conversationId, 'userId': userId});
  }

  // ─── Messages ─────────────────────────────────────────────────────────────

  void emitMessage(String conversationId, Map<String, dynamic> message) {
    _ensureConnected();
    _socket?.emit('send_message', {
      'conversationId': conversationId,
      'message': message,
    });
  }

  void onNewMessage(void Function(dynamic) handler) {
    _socket?.on('new_message', handler);
  }

  void offMessageEvents() {
    _socket?.off('new_message');
  }

  // ─── Typing ───────────────────────────────────────────────────────────────

  void onTyping(void Function(dynamic) handler) {
    _socket?.on('typing', handler);
  }

  void onStopTyping(void Function(dynamic) handler) {
    _socket?.on('stop_typing', handler);
  }

  void offTypingEvents() {
    _socket?.off('typing');
    _socket?.off('stop_typing');
  }

  void _ensureConnected() {
    if (!isConnected) connect();
  }
}
