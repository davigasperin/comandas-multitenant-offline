import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../constants/app_constants.dart';

enum SocketConnectionState { disconnected, connecting, connected }

class SocketService with WidgetsBindingObserver {
  final FlutterSecureStorage _storage;
  final String _url;
  io.Socket? _socket;
  Timer? _retry;
  bool _enabled = false;
  bool _disposed = false;
  int _generation = 0;

  final _connectionStateController =
      StreamController<SocketConnectionState>.broadcast();
  final _orderEventsController = StreamController<String>.broadcast();
  SocketConnectionState _currentState = SocketConnectionState.disconnected;

  SocketService(this._storage, {String? url})
      : _url = url ?? AppConstants.wsUrl {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  Stream<SocketConnectionState> get connectionStateStream =>
      _connectionStateController.stream;
  SocketConnectionState get currentState => _currentState;
  Stream<String> get orderEventsStream => _orderEventsController.stream;

  Future<void> connect() async {
    if (_disposed) return;
    _enabled = true;
    _retry?.cancel();
    final generation = ++_generation;
    _socket?.dispose();
    _socket = null;
    _updateState(SocketConnectionState.connecting);
    try {
      final token = await _storage.read(key: AppConstants.storageKeyAccessToken);
      final tenantId =
          await _storage.read(key: AppConstants.storageKeySelectedTenantId);
      if (_disposed || !_enabled || generation != _generation) return;
      if (token == null || tenantId == null) {
        disconnect();
        return;
      }
      final socket = io.io(
        _url,
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .disableAutoConnect()
            .disableReconnection()
            .enableForceNew()
            .setAuth({'token': token, 'tenantId': tenantId})
            .build(),
      );
      _socket = socket;
      socket.onConnect((_) {
        if (generation != _generation || _disposed) return;
        _retry?.cancel();
        _updateState(SocketConnectionState.connected);
        _orderEventsController.add('connect');
      });
      for (final event in ['order:created', 'order:updated']) {
        socket.on(event, (_) {
          if (generation == _generation && !_disposed) {
            _orderEventsController.add(event);
          }
        });
      }
      void retry(dynamic _) {
        if (generation == _generation) _scheduleRetry();
      }
      socket.onDisconnect(retry);
      socket.onConnectError(retry);
      socket.connect();
    } catch (_) {
      if (generation == _generation) _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (!_enabled || _disposed) return;
    _updateState(SocketConnectionState.disconnected);
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 3), connect);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _enabled && !_disposed) {
      unawaited(connect());
    }
  }

  void _updateState(SocketConnectionState state) {
    _currentState = state;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }

  void disconnect() {
    _enabled = false;
    ++_generation;
    _retry?.cancel();
    _socket?.dispose();
    _socket = null;
    _updateState(SocketConnectionState.disconnected);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    disconnect();
    _connectionStateController.close();
    _orderEventsController.close();
  }
}
