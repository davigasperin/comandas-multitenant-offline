import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../constants/app_constants.dart';

enum SocketConnectionState { disconnected, connecting, connected }

class SocketService {
  final FlutterSecureStorage _storage;
  final String _url;
  io.Socket? _socket;

  final _connectionStateController =
      StreamController<SocketConnectionState>.broadcast();
  final _orderEventsController = StreamController<String>.broadcast();

  SocketConnectionState _currentState = SocketConnectionState.disconnected;

  SocketService(this._storage, {String? url})
      : _url = url ?? AppConstants.wsUrl;

  Stream<SocketConnectionState> get connectionStateStream =>
      _connectionStateController.stream;
  SocketConnectionState get currentState => _currentState;
  Stream<String> get orderEventsStream => _orderEventsController.stream;

  Future<void> connect() async {
    final token = await _storage.read(key: AppConstants.storageKeyAccessToken);
    final tenantId =
        await _storage.read(key: AppConstants.storageKeySelectedTenantId);

    if (token == null || tenantId == null) {
      _updateState(SocketConnectionState.disconnected);
      return;
    }

    _socket?.dispose();

    _updateState(SocketConnectionState.connecting);

    _socket = io.io(
      _url,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .enableAutoConnect()
          .enableReconnection()
          .setAuth({'token': token, 'tenantId': tenantId})
          .build(),
    );

    _socket?.onConnect((_) {
      _updateState(SocketConnectionState.connected);
      _orderEventsController.add('connect');
    });

    _socket?.onReconnect((_) {
      _updateState(SocketConnectionState.connected);
      _orderEventsController.add('reconnect');
    });

    _socket?.on('order:created', (data) {
      _orderEventsController.add('order:created');
    });

    _socket?.on('order:updated', (data) {
      _orderEventsController.add('order:updated');
    });

    _socket?.onDisconnect((_) {
      _updateState(SocketConnectionState.disconnected);
    });

    _socket?.onConnectError((_) {
      _updateState(SocketConnectionState.disconnected);
    });
  }

  void _updateState(SocketConnectionState state) {
    _currentState = state;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _updateState(SocketConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    _connectionStateController.close();
    _orderEventsController.close();
  }
}
