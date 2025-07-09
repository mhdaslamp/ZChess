import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;

import 'package:chess/chess.dart' as chess_lib;
import '../models/game_update.dart'; // Make sure this path is correct
import 'package:flutter/foundation.dart';

class GameService {
  final String accessToken;
  final String username;

  Function(GameUpdate)? onGameUpdate;

  http.Client? _eventClient;
  http.Client? _gameClient;
  String? _gameId;
  String? _playerColor; // 'white' or 'black'
  String? _opponentName;
  String? _opponentRating;
  Timer? _pingTimer;
  Timer? _seekTimeout;
  List<String> moves = []; // Keep track of move history in SAN for internal state
  bool _disposed = false;
  late chess_lib.Chess _chess; // The main chess game state
  int _reconnectAttempts = 0;

  GameService({required this.accessToken, required this.username}) {
    _chess = chess_lib.Chess(); // Initialize the chess board once
  }

  Future<void> startGame() async {
    try {
      await _createSeek();
      _listenToEventStream();

      _seekTimeout = Timer(const Duration(minutes: 5), () {
        if (_gameId == null && !_disposed) {
          onGameUpdate?.call(GameUpdate(
            status: 'No opponent found. Try again.',
            isMyTurn: false,
            moves: [],
            gameOver: true,
            fen: _chess.fen, // _chess.fen is a runtime value, so GameUpdate constructor must not be const
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
      body: 'rated=false&clock.limit=300&clock.increment=3&variant=standard&color=white',
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Failed to create seek: ${response.statusCode} - ${response.body}');
    }
  }

  void _listenToEventStream() {
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
          if (event['type'] == 'gameStart') {
            _gameId = event['game']['id'];
            _playerColor = event['game']['color'].toString();
            _connectToGameStream();
          } else if (event['type'] == 'gameFinish') {
            _gameId = event['game']['id'];
            _handleGameFinish(event['game']['status'].toString());
          }
        } catch (e) {
          _handleError('Error processing event: $e');
        }
      }, onError: (error) {
        _handleStreamError('Event stream error', error);
      }, onDone: () {
        _handleStreamDisconnect('Event stream closed');
      });
    }).catchError((e) {
      _handleStreamError('Failed to connect to event stream', e);
    });
  }

  void _connectToGameStream() {
    if (_gameId == null || _disposed) return;

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
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 20), (_) {});

      response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (line.trim().isEmpty) return;
        try {
          _handleGameMessage(line);
        } catch (e) {
          _handleError('Error processing game event: $e');
        }
      }, onError: (error) {
        _handleStreamError('Game stream error', error);
      }, onDone: () {
        _handleStreamDisconnect('Game stream closed');
      });

      _reconnectAttempts = 0;
    }).catchError((e) {
      _handleStreamError('Failed to connect to game stream', e);
    });
  }

  void _handleGameMessage(String message) {
    try {
      final data = json.decode(message);

      if (data['type'] == 'gameFull') {
        final white = data['white'] ?? {};
        final black = data['black'] ?? {};
        final state = data['state'] ?? {};

        moves = (state['moves']?.toString().split(' ') ?? []).where((s) => s.isNotEmpty).toList();
        final isWhitePlayer = _playerColor == 'white';

        _opponentName = (isWhitePlayer ? black['name'] : white['name'])?.toString();
        _opponentRating = (isWhitePlayer ? black['rating'] : white['rating'])?.toString();

        final fen = state['fen']?.toString() ?? _chess.fen;
        _updateChessState(fen);

        onGameUpdate?.call(GameUpdate(
          gameId: _gameId,
          status: 'Game started',
          isMyTurn: _isMyTurn(),
          moves: moves,
          opponentName: _opponentName,
          opponentRating: _opponentRating,
          myColor: _playerColor,
          fen: fen,
          lastMove: moves.isNotEmpty ? moves.last : null,
          gameOver: state['status']?.toString() != 'started',
        ));
      } else if (data['type'] == 'gameState') {
        final String movesString = data['moves']?.toString() ?? '';
        moves = movesString.split(' ').where((s) => s.isNotEmpty).toList();

        final fen = data['fen']?.toString() ?? _chess.fen;
        _updateChessState(fen);

        onGameUpdate?.call(GameUpdate(
          gameId: _gameId,
          status: (data['status']?.toString() ?? 'Game in progress'),
          isMyTurn: _isMyTurn(),
          moves: moves,
          fen: fen,
          lastMove: moves.isNotEmpty ? moves.last : null,
          opponentName: _opponentName,
          opponentRating: _opponentRating,
          myColor: _playerColor,
          gameOver: data['status']?.toString() != 'started',
        ));
      } else if (data['type'] == 'gameFinish') {
        _handleGameFinish(data['status']?.toString() ?? 'unknown');
      }
    } catch (e) {
      _handleError('Error processing game message: $e');
    }
  }

  void _handleGameFinish(String status) {
    onGameUpdate?.call(GameUpdate(
      status: 'Game finished: $status',
      isMyTurn: false,
      moves: moves,
      gameOver: true,
      fen: _chess.fen,
    ));
    dispose();
  }

  void _handleStreamError(String message, dynamic error) {
    _handleError('$message: ${error.toString()}');
    if (!_disposed && _gameId != null && _reconnectAttempts < 3) {
      _scheduleReconnect();
    } else if (_gameId == null) {
      onGameUpdate?.call(GameUpdate(
        status: message,
        isMyTurn: false,
        gameOver: true,
        moves: [],
        fen: _chess.fen,
      ));
      dispose();
    }
  }

  void _handleStreamDisconnect(String message) {
    _handleError(message);
    if (!_disposed && _gameId != null && _reconnectAttempts < 3) {
      _scheduleReconnect();
    } else if (_gameId == null) {
      onGameUpdate?.call(GameUpdate(
        status: message,
        isMyTurn: false,
        gameOver: true,
        moves: [],
        fen: _chess.fen,
      ));
      dispose();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= 3 || _disposed) {
      _handleError('Max reconnect attempts reached. Please restart.');
      onGameUpdate?.call(GameUpdate(
        status: 'Connection lost. Restart app.',
        gameOver: true,
        isMyTurn: false,
        moves: [],
        fen: _chess.fen,
      ));
      dispose();
      return;
    }
    _reconnectAttempts++;

    Timer(const Duration(seconds: 2 ), () {
      if (_gameId == null) {
        _listenToEventStream();
      } else {
        _connectToGameStream();
      }
    });
  }

  void _updateChessState(String fen) {
    try {
      _chess.load(fen);
    } catch (e) {
      _handleError('Failed to load chess state from FEN: $e');
      _chess.reset();
    }
  }

  bool _isMyTurn() {
    if (_playerColor == null) return false;
    final chess_lib.Color currentTurn = _chess.turn;
    if (_playerColor == 'white' && currentTurn == chess_lib.Color.WHITE) {
      return true;
    } else if (_playerColor == 'black' && currentTurn == chess_lib.Color.BLACK) {
      return true;
    }
    return false;
  }

  // This method is primarily for UI validation before sending
  // It checks if a move from 'from' to 'to' is valid.
  bool isValidMove(String fromSquare, String toSquare, {String? promotion}) {
    final tempChess = chess_lib.Chess.fromFEN(_chess.fen);
    try {
      // Prepare the move in UCI format
      String uciMove = fromSquare.toLowerCase() + toSquare.toLowerCase();
      if (promotion != null) {
        uciMove += promotion.toLowerCase();
      }

      // Attempt the move and return the result
      return tempChess.move(uciMove);
    } catch (e) {
      print('Local move validation error: $e');
      return false;
    }
  }
  Future<bool> makeMove(String from, String to, String? promotion) async {
    if (_gameId == null) {
      _handleError('Not connected to game');
      return false;
    }

    if (!_isMyTurn()) {
      _handleError('It\'s not your turn.');
      return false;
    }

    try {
      // Convert to UCI format (e2e4 or e7e8q for promotion)
      String uciMove = from.toLowerCase() + to.toLowerCase();
      if (promotion != null) {
        uciMove += promotion.toLowerCase();
      }

      debugPrint('Sending UCI move to server: $uciMove');

      final response = await http.post(
        Uri.parse('https://lichess.org/api/board/game/$_gameId/move/$uciMove'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
        debugPrint('Server rejected move: $error');
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('Move failed: $e');
      return false;
    }
  }// (including the `isValidMove` method, which is correct as is)
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

  void _handleError(String message) {
    if (!_disposed) {
      onGameUpdate?.call(GameUpdate(
        status: message,
        isMyTurn: false,
        moves: moves,
        gameOver: true,
        fen: _chess.fen,
      ));
    }
  }

  void dispose() {
    _disposed = true;
    _pingTimer?.cancel();
    _seekTimeout?.cancel();
    _eventClient?.close();
    _gameClient?.close();
    print('GameService disposed');
  }
}