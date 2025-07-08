import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/game_update.dart';  // Add this import

class GameService {
  final String accessToken;
  final String username;
  GameUpdateCallback? onGameUpdate;

  http.Client? _eventClient;
  http.Client? _gameClient;
  WebSocketChannel? _gameSocket;
  String? _gameId;
  Timer? _pingTimer;
  int _reconnectAttempts = 0;

  GameService({
    required this.accessToken,
    required this.username,
  });

  Future<void> startGame() async {
    try {
      // Create a game seek
      final response = await http.post(
        Uri.parse('https://lichess.org/api/board/seek'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'rated=false&time=5&increment=3&variant=standard&color=random',
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to create seek: ${response.statusCode} - ${response.body}');
      }

      // Listen for game events
      _listenToEventStream();
    } catch (e) {
      _notifyError('Failed to start game: ${e.toString()}');
      rethrow;
    }
  }

  void _listenToEventStream() async {
    _eventClient?.close();
    _eventClient = http.Client();

    try {
      final request = http.Request(
        'GET',
        Uri.parse('https://lichess.org/api/stream/event'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/x-ndjson',
      });

      final response = await _eventClient!.send(request);

      response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isEmpty) return;
        final event = jsonDecode(line);
        if (event['type'] == 'gameStart') {
          _gameId = event['game']['id'];
          _connectToGameStream();
        }
      }, onError: (e) {
        _handleStreamError('Event stream error', e);
      }, onDone: () {
        _handleStreamDisconnect('Event stream closed');
      });
    } catch (e) {
      _handleStreamError('Event stream connection failed', e);
    }
  }

  void _connectToGameStream() {
    if (_gameId == null) return;

    _gameClient?.close();
    _gameClient = http.Client();

    try {
      final request = http.Request(
        'GET',
        Uri.parse('https://lichess.org/api/board/game/stream/$_gameId'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $accessToken',
        'Accept': 'application/x-ndjson',
      });

      final response = _gameClient!.send(request);

      response.asStream().listen((http.StreamedResponse streamedResponse) {
        streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          if (line.trim().isEmpty) return;
          _handleGameMessage(line);
        }, onError: (e) {
          _handleStreamError('Game stream error', e);
        }, onDone: () {
          _handleStreamDisconnect('Game stream closed');
        });
      });

      // Setup ping to keep connection alive
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        // Ping logic if needed
      });

      _reconnectAttempts = 0; // Reset on successful connection
    } catch (e) {
      _handleStreamError('Game stream connection failed', e);
    }
  }

  void _handleGameMessage(String message) {
    try {
      final data = jsonDecode(message);

      if (data['type'] == 'gameFull') {
        final gameInfo = _parseGameFull(data);
        onGameUpdate?.call(gameInfo);
      } else if (data['type'] == 'gameState') {
        final gameState = _parseGameState(data);
        onGameUpdate?.call(gameState);
      } else if (data['type'] == 'gameFinish') {
        onGameUpdate?.call(GameUpdate(
          status: 'Game finished: ${data['status']}',
          isMyTurn: false,
          moves: data['state']['moves']?.toString().split(' ') ?? [],
        ));
      }
    } catch (e) {
      _notifyError('Error processing game message: ${e.toString()}');
    }
  }

  GameUpdate _parseGameFull(Map<String, dynamic> data) {
    final opponent = data[data['white']['id'] == username ? 'black' : 'white'];
    final moves = (data['state']['moves']?.toString().split(' ') ?? []);
    final isMyTurn = data['white']['id'] == username
        ? moves.length.isEven
        : moves.length.isOdd;

    return GameUpdate(
      status: 'Game started - you are ${data['white']['id'] == username ? 'white' : 'black'}',
      isMyTurn: isMyTurn,
      moves: moves,
    );
  }

  GameUpdate _parseGameState(Map<String, dynamic> data) {
    final moves = (data['moves']?.toString().split(' ') ?? []);
    final isMyTurn = data['isMyTurn'] ?? false;
    final status = isMyTurn ? 'Your turn to move!' : 'Waiting for opponent...';

    return GameUpdate(
      status: status,
      isMyTurn: isMyTurn,
      moves: moves,
    );
  }

  Future<void> makeMove(String move) async {
    if (_gameId == null) {
      throw Exception('No active game to make move in');
    }

    final response = await http.post(
      Uri.parse('https://lichess.org/api/board/game/$_gameId/move/$move'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode != 200) {
      throw Exception('Move failed: ${response.statusCode} - ${response.body}');
    }
  }

  void _handleStreamError(String message, dynamic error) {
    _notifyError('$message: ${error.toString()}');
    _scheduleReconnect();
  }

  void _handleStreamDisconnect(String message) {
    _notifyError(message);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= 3) return;
    _reconnectAttempts++;

    Timer(const Duration(seconds: 2), () {
      if (_gameId == null) {
        _listenToEventStream();
      } else {
        _connectToGameStream();
      }
    });
  }

  void _notifyError(String message) {
    onGameUpdate?.call(GameUpdate(
      status: message,
      isMyTurn: false,
      moves: [],
    ));
  }

  void dispose() {
    _pingTimer?.cancel();
    _eventClient?.close();
    _gameClient?.close();
    _gameSocket?.sink.close();
  }
}