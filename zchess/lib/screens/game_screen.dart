import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:chess/chess.dart' as chess;
import '../services/game_service.dart';
import '../models/game_update.dart';

class GameScreen extends StatefulWidget {
  final String accessToken;
  final String username;

  const GameScreen({
    required this.accessToken,
    required this.username,
    Key? key,
  }) : super(key: key);

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameService _gameService;
  late chess.Chess _chess;
  late ChessBoardController _boardController;
  String _status = 'Creating game...';
  String? _opponentName;
  String? _opponentRating;
  bool _isMyTurn = false;
  bool _gameOver = false;
  PlayerColor _playerColor = PlayerColor.white; // Default to white

  @override
  void initState() {
    super.initState();
    _chess = chess.Chess();
    _boardController = ChessBoardController();
    _gameService = GameService(
      accessToken: widget.accessToken,
      username: widget.username,
    );
    _initializeGame();
  }

  void _initializeGame() {
    _gameService.onGameUpdate = (GameUpdate update) {
      setState(() {
        _status = update.status;
        _isMyTurn = update.isMyTurn;
        _opponentName = update.opponentName;
        _opponentRating = update.opponentRating;
        _gameOver = update.gameOver;

        // Update player color if available
        if (update.myColor != null) {
          _playerColor = update.myColor == 'white'
              ? PlayerColor.white
              : PlayerColor.black;
        }

        // Update board position if changed
        if (update.fen != null && update.fen != _chess.fen) {
          _chess.load(update.fen!);
          _boardController.loadFen(update.fen!);
        }

        // Make last move on board
        if (update.lastMove != null && update.lastMove!.length == 4) {
          String from = update.lastMove!.substring(0, 2);
          String to = update.lastMove!.substring(2, 4);
          _boardController.makeMove(from: from, to: to);
        }
      });
    };

    _gameService.startGame();
  }

  @override
  void dispose() {
    _gameService.dispose();
    _boardController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_opponentName != null
            ? 'vs $_opponentName (${_opponentRating ?? '?'})'
            : 'Lichess Game'),
        actions: [
          if (_gameOver)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              _status,
              style: TextStyle(
                fontSize: 16,
                color: _isMyTurn ? Colors.green : Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: ChessBoard(
                controller: _boardController,
                boardOrientation: _playerColor,
                enableUserMoves: _isMyTurn && !_gameOver,

              ),
            ),
          ),
          if (_isMyTurn && !_gameOver)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Your turn!',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}