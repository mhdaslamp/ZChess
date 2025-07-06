import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/game_update.dart';

class GameService {
  final String accessToken;
  final String username;
  Function(GameUpdate)? onGameUpdate;

  http.Client? _eventClient;
  http.Client? _gameClient;
  String? _gameId;
  String? _playerColor;
  String? _opponentName;
  String? _opponentRating;
  Timer? _pingTimer;
  Timer? _seekTimeout;
  List<String> moves = [];
  bool _disposed = false;

  GameService({required this.accessToken, required this.username});

  Future<void> startGame() async {
    try {
      await _createSeek();
      _connectToEventStream();

      _seekTimeout = Timer(const Duration(minutes: 2), () {
        if (_gameId == null && !_disposed) {
          onGameUpdate?.call(GameUpdate(
            status: 'No opponent found. Try again.',
            isMyTurn: false,
            moves: moves,
            gameOver: true,
          ));
          dispose();
        }
      });
    } catch (e) {
      _handleError('Failed to start game: ${e.toString()}');
    }
  }

  Future<void> _createSeek() async {
    final response = await http.post(
      Uri.parse('https://lichess.org/api/board/seek'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: 'rated=false&clock.limit=300&clock.increment=3&variant=standard&color=random',
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to create seek: ${response.body}');
    }
  }

  void _connectToEventStream() {
    _eventClient?.close();
    _eventClient = http.Client();

    final request = http.Request(
      'GET',
      Uri.parse('https://lichess.org/api/stream/event'),
    );
    request.headers.addAll({
      'Authorization': 'Bearer $accessToken',
      'Accept': 'application/x-ndjson',
    });

    _eventClient!.send(request).then((response) {
      response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isEmpty) return;
        try {
          final event = json.decode(line);
          switch (event['type']) {
            case 'gameStart':
              _handleGameStart(event['game']);
              break;
            case 'gameFinish':
              _handleGameFinish();
              break;
            case 'challenge':
              _handleChallenge(event['challenge']);
              break;
          }
        } catch (e) {
          _handleError('Error processing event: $e');
        }
      }, onError: (error) => _handleError('Event stream error: $error'));
    }).catchError((e) => _handleError('Failed to connect to event stream: $e'));
  }

  void _handleGameStart(Map<String, dynamic> game) {
    _seekTimeout?.cancel();
    _gameId = game['id'];
    _playerColor = game['color'] == 'white' ? 'white' : 'black';
    _connectToGameStream();
  }

  void _connectToGameStream() {
    if (_gameId == null) return;

    _gameClient?.close();
    _gameClient = http.Client();

    final request = http.Request(
      'GET',
      Uri.parse('https://lichess.org/api/board/game/stream/$_gameId'),
    );
    request.headers.addAll({
      'Authorization': 'Bearer $accessToken',
      'Accept': 'application/x-ndjson',
    });

    _gameClient!.send(request).then((response) {
      // Start ping timer to maintain connection
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
        // Keep-alive ping
      });

      response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isEmpty) return;
        try {
          _handleGameEvent(json.decode(line));
        } catch (e) {
          _handleError('Error processing game event: $e');
        }
      }, onError: (error) => _handleError('Game stream error: $error'));
    }).catchError((e) => _handleError('Failed to connect to game stream: $e'));
  }

  void _handleGameEvent(Map<String, dynamic> event) {
    try {
      switch (event['type']) {
        case 'gameFull':
          final white = event['white'];
          final black = event['black'];
          final state = event['state'];

          moves = state['moves']?.split(' ') ?? [];
          final isWhite = _playerColor == 'white';

          _opponentName = isWhite ? black['name'] : white['name'];
          _opponentRating = isWhite
              ? black['rating']?.toString()
              : white['rating']?.toString();

          onGameUpdate?.call(GameUpdate(
            gameId: _gameId,
            status: 'Game started',
            isMyTurn: _isMyTurn(),
            moves: moves,
            opponentName: _opponentName,
            opponentRating: _opponentRating,
            myColor: _playerColor,
            fen: state['fen'],
            lastMove: moves.isNotEmpty ? moves.last : null,
            gameOver: state['status'] != 'started',
          ));
          break;

        case 'gameState':
          moves = event['moves']?.split(' ') ?? [];
          onGameUpdate?.call(GameUpdate(
            gameId: _gameId,
            status: event['status'] ?? 'Game in progress',
            isMyTurn: _isMyTurn(),
            moves: moves,
            fen: event['fen'],
            lastMove: moves.isNotEmpty ? moves.last : null,
            opponentName: _opponentName,
            opponentRating: _opponentRating,
            myColor: _playerColor,
            gameOver: event['status'] != 'started',
          ));
          break;

        case 'chatLine':
        // Handle chat messages if needed
          break;
      }
    } catch (e) {
      _handleError('Error processing game event: $e');
    }
  }

  bool _isMyTurn() {
    if (_playerColor == null) return false;
    return (_playerColor == 'white')
        ? moves.length % 2 == 0
        : moves.length % 2 == 1;
  }

  Future<void> makeMove(String move) async {
    if (_gameId == null) {
      _handleError('Not connected to game');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('https://lichess.org/api/board/game/$_gameId/move/$move'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode != 200) {
        _handleError('Move failed: ${response.body}');
      }
    } catch (e) {
      _handleError('Move failed: $e');
    }
  }

  Future<void> resign() async {
    if (_gameId == null) return;

    try {
      final response = await http.post(
        Uri.parse('https://lichess.org/api/board/game/$_gameId/resign'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode != 200) {
        _handleError('Resign failed: ${response.body}');
      }
    } catch (e) {
      _handleError('Resign failed: $e');
    }
  }

  void _handleGameFinish() {
    onGameUpdate?.call(GameUpdate(
      status: 'Game finished',
      isMyTurn: false,
      moves: moves,
      gameOver: true,
    ));
    dispose();
  }

  void _handleChallenge(Map<String, dynamic> challenge) {
    if (challenge['status'] == 'created') {
      http.post(
        Uri.parse('https://lichess.org/api/challenge/${challenge['id']}/decline'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
    }
  }

  void _handleError(String message) {
    if (!_disposed) {
      onGameUpdate?.call(GameUpdate(
        status: message,
        isMyTurn: false,
        moves: moves,
        gameOver: true,
      ));
    }
  }

  void dispose() {
    _disposed = true;
    _pingTimer?.cancel();
    _seekTimeout?.cancel();
    _eventClient?.close();
    _gameClient?.close();
  }
}