import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:chess/chess.dart' as chess_lib;
import '../models/game_update.dart';
import 'package:flutter/foundation.dart';

class GameService {
  final String accessToken;
  final String username;

  Function(GameUpdate)? onGameUpdate;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

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
  late chess_lib.Chess _chess;
  int _reconnectAttempts = 0;
  bool _isProcessingMove = false;
  bool _isRequestInProgress = false;
  DateTime? _lastRequestTime;

  GameService({required this.accessToken, required this.username}) {
    _chess = chess_lib.Chess();
  }

  Future<void> _makeThrottledRequest(Future Function() request) async {
    if (_isRequestInProgress) {
      throw Exception('Another request is already in progress');
    }
    if (_lastRequestTime != null &&
        DateTime.now().difference(_lastRequestTime!) < const Duration(seconds: 1)) {
      await Future.delayed(const Duration(seconds: 1));
    }

    _isRequestInProgress = true;
    try {
      return await request();
    } finally {
      _isRequestInProgress = false;
    }
  }

  Future<void> startGame() async {
    return _makeThrottledRequest(() async {
      if (_disposed) return;
      try {
        _updateGameStatus('Connecting to Lichess...');
        final authResponse = await http.get(
          Uri.parse('https://lichess.org/api/account'),
          headers: {'Authorization': 'Bearer $accessToken'},
        ).timeout(const Duration(seconds: 30));

        if (authResponse.statusCode != 200) {
          _handleError('Authentication failed. Please check your access token.');
          return;
        }
        _updateGameStatus('Looking for opponent...');
        await _createSeek();
        _listenToEventStream();

        _seekTimeout = Timer(const Duration(minutes: 2), () {
          if (_gameId == null && !_disposed) {
            _handleError('No opponent found. Try again.');
            dispose();
          }
        });
      } on TimeoutException {
        _handleError('Connection timeout. Retrying...');
        _scheduleReconnect();
      } catch (e) {
        _handleError('Failed to start game: ${e.toString()}');
        _scheduleReconnect();
      }
    });
  }

  void _updateGameStatus(String status) {
    if (onGameUpdate != null) {
      onGameUpdate!(GameUpdate(
        status: status,
        isMyTurn: false,
        moves: [],
        fen: _chess.fen,
        gameOver: false,
      ));
    }
  }

  Future<void> _createSeek() async {
    try {
      final response = await http.post(
        Uri.parse('https://lichess.org/api/board/seek'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'rated=false&clock.limit=300&clock.increment=3&variant=standard&color=random',
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 429) {
        throw Exception('Rate limited - please wait before trying again');
      } else if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('Failed to create seek: ${response.body}');
      }
    } on TimeoutException {
      throw Exception('Seek creation timed out');
    }
  }

  void _listenToEventStream() {
    if (_disposed) return;
    _eventClient?.close();
    _eventClient = http.Client();
    _updateConnectionStatus(true);
    final request = http.Request('GET', Uri.parse('https://lichess.org/api/stream/event'));
    request.headers.addAll({'Authorization': 'Bearer $accessToken', 'Accept': 'application/x-ndjson'});
    _eventClient!.send(request).then((response) {
      _reconnectAttempts = 0;
      _updateConnectionStatus(true);
      response.stream.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        if (line.trim().isEmpty) return;
        try {
          final event = json.decode(line);
          _handleEvent(event);
        } catch (e) {
          debugPrint('Event parse error: $e\n$line');
        }
      }, onError: (e) => _handleStreamError('Event stream error', e), onDone: () => _handleStreamDisconnect('Event stream closed'));
    }).catchError((e) => _handleStreamError('Event connection failed', e));
  }

  void _connectToGameStream() {
    if (_disposed || _gameId == null || _gameClient != null) return;
    _gameClient?.close();
    _gameClient = http.Client();
    _updateConnectionStatus(true);
    final request = http.Request('GET', Uri.parse('https://lichess.org/api/board/game/stream/$_gameId'));
    request.headers.addAll({'Authorization': 'Bearer $accessToken', 'Accept': 'application/x-ndjson', 'Connection': 'keep-alive'});
    _gameClient!.send(request).then((response) {
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
        if (!_disposed && _gameId != null) {
          try {
            await http.get(Uri.parse('https://lichess.org/api/board/game/$_gameId/ping'), headers: {'Authorization': 'Bearer $accessToken'}).timeout(const Duration(seconds: 5));
          } catch (e) {
            debugPrint('Ping failed: $e');
          }
        }
      });
      response.stream.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        if (line.trim().isNotEmpty) {
          try {
            _handleGameMessage(line);
          } catch (e) {
            debugPrint('Game message error: $e\n$line');
          }
        }
      }, onError: (e) => _handleStreamError('Game stream error', e), onDone: () => _handleStreamDisconnect('Game stream closed'));
    }).catchError((e) => _handleStreamError('Game connection failed', e));
  }

  void _updateConnectionStatus(bool connected) {
    if (_isConnected != connected) {
      _isConnected = connected;
      debugPrint('Connection status changed: $_isConnected');
    }
  }

  void _handleEvent(Map<String, dynamic> event) {
    debugPrint('Event: ${event['type']}');
    switch (event['type']) {
      case 'gameStart':
        _handleGameStart(event);
        break;
      case 'challenge':
        if (_gameId == null) _handleChallenge(event);
        break;
      case 'gameFinish':
        _handleGameFinish(event['game']['status'].toString());
        break;
      default:
        debugPrint('Unhandled event type: ${event['type']}');
    }
  }

  void _handleGameStart(Map<String, dynamic> event) {
    if (_gameId != null) {
      debugPrint('Ignoring subsequent gameStart event for game ${event['game']['id']}');
      return;
    }
    _gameId = event['game']['id'];
    _playerColor = event['game']['color'].toString();
    _opponentName = event['game']['opponent']?['username']?.toString();
    _opponentRating = event['game']['opponent']?['rating']?.toString();
    _connectToGameStream();
  }

  void _handleChallenge(Map<String, dynamic> event) {
    final challenge = event['challenge'];
    onGameUpdate?.call(GameUpdate(
        status: 'Incoming Challenge',
        isMyTurn: false,
        moves: [],
        fen: _chess.fen,
        gameOver: false,
        incomingChallengeId: challenge['id'],
        incomingChallengerName: challenge['challenger']['username'],
        incomingChallengeSpeed: challenge['speed'],
        incomingChallengeTime: challenge['timeControl']?['initial']?.toString(),
        incomingChallengeIncrement: challenge['timeControl']?['increment']?.toString(),
        incomingChallengeVariant: challenge['variant']?['name'],
        incomingChallengeRated: challenge['rated']));
  }

  void _handleGameMessage(String message) {
    try {
      final data = json.decode(message);
      if (data is! Map<String, dynamic>) return;
      debugPrint('Game message: ${data['type']}');
      switch (data['type']) {
        case 'gameFull':
          _handleGameFull(data);
          break;
        case 'gameState':
          _handleGameState(data);
          break;
        case 'gameFinish':
          _handleGameFinish(data['status']?.toString() ?? 'unknown');
          break;
        default:
          debugPrint('Unhandled message type: ${data['type']}');
      }
    } catch (e) {
      debugPrint('Error parsing game message: $e\nMessage: $message');
    }
  }

  void _handleGameFull(Map<String, dynamic> data) {
    final state = data['state'] ?? {};
    moves = (state['moves']?.toString().split(' ') ?? []).where((s) => s.isNotEmpty).toList();
    _chess.reset();
    for (final uciMove in moves) {
      if (uciMove.length >= 4) {
        final from = uciMove.substring(0, 2);
        final to = uciMove.substring(2, 4);
        String? promotion;
        if (uciMove.length == 5) {
          promotion = uciMove.substring(4, 5);
        }
        _chess.move({'from': from, 'to': to, if (promotion != null) 'promotion': promotion});
      }
    }
    final currentFen = _chess.fen;
    onGameUpdate?.call(GameUpdate(
        gameId: _gameId,
        status: 'Game started',
        isMyTurn: _isMyTurn(),
        moves: moves,
        opponentName: _opponentName,
        opponentRating: _opponentRating,
        myColor: _playerColor,
        fen: currentFen,
        lastMove: moves.isNotEmpty ? moves.last : null,
        gameOver: state['status']?.toString() != 'started'));
  }

  void _handleGameState(Map<String, dynamic> data) {
    moves = (data['moves']?.toString().split(' ') ?? []).where((s) => s.isNotEmpty).toList();
    _chess.reset();
    for (final uciMove in moves) {
      if (uciMove.length >= 4) {
        final from = uciMove.substring(0, 2);
        final to = uciMove.substring(2, 4);
        String? promotion;
        if (uciMove.length == 5) {
          promotion = uciMove.substring(4, 5);
        }
        _chess.move({'from': from, 'to': to, if (promotion != null) 'promotion': promotion});
      }
    }
    final currentFen = _chess.fen;
    debugPrint(
        '''Game State Update: Moves: $moves FEN: $currentFen Status: ${data['status']} My Color: $_playerColor Turn: ${_chess.turn} Is My Turn: ${_isMyTurn()}''');
    onGameUpdate?.call(GameUpdate(
        gameId: _gameId,
        status: data['status']?.toString() ?? 'Game in progress',
        isMyTurn: _isMyTurn(),
        moves: moves,
        fen: currentFen,
        lastMove: moves.isNotEmpty ? moves.last : null,
        opponentName: _opponentName,
        opponentRating: _opponentRating,
        myColor: _playerColor,
        gameOver: data['status']?.toString() != 'started'));
  }

  void _cleanupCurrentGame() {
    debugPrint('Cleaning up finished game $_gameId');
    _pingTimer?.cancel();
    _pingTimer = null;
    _gameClient?.close();
    _gameClient = null;
    _gameId = null;
    _playerColor = null;
    _opponentName = null;
    _opponentRating = null;
    moves = [];
    _chess.reset();
  }

  void _handleGameFinish(String status) {
    onGameUpdate?.call(GameUpdate(status: 'Game finished: $status', isMyTurn: false, moves: moves, gameOver: true, fen: _chess.fen));
    _cleanupCurrentGame();
  }

  bool _isMyTurn() {
    if (_playerColor == null) return false;
    return (_playerColor == 'white' && _chess.turn == chess_lib.Color.WHITE) || (_playerColor == 'black' && _chess.turn == chess_lib.Color.BLACK);
  }

  bool isValidMove(String fromSquare, String toSquare, {String? promotion}) {
    try {
      final tempChess = chess_lib.Chess.fromFEN(_chess.fen);
      final move = {'from': fromSquare, 'to': toSquare, if (promotion != null) 'promotion': promotion};
      return tempChess.move(move) != null;
    } catch (e) {
      debugPrint('Move validation error: $e');
      return false;
    }
  }

  Future<bool> makeMove(String from, String to, String? promotion) async {
    if (_isProcessingMove || _gameId == null || !_isMyTurn()) return false;
    _isProcessingMove = true;
    try {
      from = from.toLowerCase();
      to = to.toLowerCase();
      debugPrint('''Validating move: From: $from To: $to Promotion: $promotion FEN: ${_chess.fen}''');
      if (!isValidMove(from, to, promotion: promotion)) {
        debugPrint('Move invalid according to local rules');
        return false;
      }
      String uciMove = from + to;
      if (promotion != null) uciMove += promotion.toLowerCase();
      debugPrint('Submitting UCI move: $uciMove');
      final response = await http
          .post(Uri.parse('https://lichess.org/api/board/game/$_gameId/move/$uciMove'), headers: {'Authorization': 'Bearer $accessToken'}).timeout(const Duration(seconds: 10));
      debugPrint('Server response: ${response.statusCode} - ${response.body}');
      if (response.statusCode != 200) {
        if (response.statusCode == 400) {
          await syncGameState();
        }
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('Move failed: $e');
      return false;
    } finally {
      _isProcessingMove = false;
    }
  }

  Future<void> syncGameState() async {
    if (_gameId == null || _disposed) return;
    try {
      final response =
      await http.get(Uri.parse('https://lichess.org/api/board/game/$_gameId'), headers: {'Authorization': 'Bearer $accessToken'}).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _handleGameFull(data);
      }
    } catch (e) {
      debugPrint('Failed to sync game state: $e');
    }
  }

  void _handleError(String message) {
    if (!_disposed && onGameUpdate != null) {
      onGameUpdate!(GameUpdate(status: message, isMyTurn: false, moves: moves, gameOver: true, fen: _chess.fen));
    }
    debugPrint('Error: $message');
  }

  void _handleStreamError(String message, dynamic error) {
    debugPrint('$message: $error');
    _updateConnectionStatus(false);
    if (!_disposed) {
      _scheduleReconnect();
    }
  }

  void _handleStreamDisconnect(String message) {
    debugPrint(message);
    _updateConnectionStatus(false);
    if (!_disposed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectAttempts++;
    final delay = Duration(seconds: min(pow(2, _reconnectAttempts).toInt(), 30));
    Timer(delay, () {
      if (!_disposed) {
        debugPrint('Attempting reconnect #$_reconnectAttempts');
        if (_gameId == null) {
          _listenToEventStream();
        } else {
          _connectToGameStream();
        }
      }
    });
  }

  Future<bool> acceptChallenge(String challengeId) async {
    try {
      final response = await http
          .post(Uri.parse('https://lichess.org/api/challenge/$challengeId/accept'), headers: {'Authorization': 'Bearer $accessToken'}).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      _handleError('Error accepting challenge: $e');
      return false;
    }
  }

  Future<bool> declineChallenge(String challengeId) async {
    try {
      final response = await http
          .post(Uri.parse('https://lichess.org/api/challenge/$challengeId/decline'), headers: {'Authorization': 'Bearer $accessToken'}).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      _handleError('Error declining challenge: $e');
      return false;
    }
  }

  Future<void> resign() async {
    if (_gameId == null || _disposed) return;
    try {
      await http
          .post(Uri.parse('https://lichess.org/api/board/game/$_gameId/resign'), headers: {'Authorization': 'Bearer $accessToken'}).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Error resigning: $e');
    }
  }

  void dispose() {
    if (!_disposed) {
      _disposed = true;
      _isConnected = false;
      _pingTimer?.cancel();
      _seekTimeout?.cancel();
      _eventClient?.close();
      _gameClient?.close();
      debugPrint('GameService disposed');
    }
  }
}