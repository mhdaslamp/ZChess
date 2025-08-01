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
  // Game state variables
  late final GameService _gameService;
  late chess.Chess _chess;
  late ChessBoardController _boardController;

  String _status = 'Connecting...';
  String? _opponentName;
  String? _opponentRating;
  bool _isMyTurn = false;
  bool _gameOver = false;
  PlayerColor _playerColor = PlayerColor.white;
  String? _gameId;
  String _lastFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  // Move selection variables
  String? _selectedSquare;
  List<String> _possibleMoveSquares = [];

  // Incoming challenge state variables
  String? _incomingChallengeId;
  String? _incomingChallengerName;
  String? _incomingChallengeVariant;
  String? _incomingChallengeTime;
  String? _incomingChallengeIncrement;
  bool? _incomingChallengeRated;


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
    _gameService.startGame();
  }

  Future<String?> _showPromotionDialog(BuildContext context) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Pawn Promotion'),
          content: SizedBox(
            width: double.minPositive,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _buildPromotionButton('Queen', 'q'),
                _buildPromotionButton('Rook', 'r'),
                _buildPromotionButton('Bishop', 'b'),
                _buildPromotionButton('Knight', 'n'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPromotionButton(String label, String piece) {
    return TextButton(
      onPressed: () => Navigator.of(context).pop(piece),
      child: Text(label),
    );
  }

  void _initializeGame() {
    _gameService.onGameUpdate = (GameUpdate update) {
      if (!mounted) return;

      if (update.incomingChallengeId != null && update.incomingChallengeId != _incomingChallengeId) {
        setState(() {
          _incomingChallengeId = update.incomingChallengeId;
          _incomingChallengerName = update.incomingChallengerName;
          _incomingChallengeVariant = update.incomingChallengeVariant;
          _incomingChallengeTime = update.incomingChallengeTime;
          _incomingChallengeIncrement = update.incomingChallengeIncrement;
          _incomingChallengeRated = update.incomingChallengeRated;
        });
        _showChallengeDialog(update);
      }

      setState(() {
        _status = update.status;
        _isMyTurn = update.isMyTurn;
        _gameOver = update.gameOver;
        _opponentName = update.opponentName;
        _opponentRating = update.opponentRating;
        _gameId = update.gameId;

        if (update.myColor != null) {
          _playerColor = update.myColor == 'white'
              ? PlayerColor.white
              : PlayerColor.black;
        }

        if (update.fen != _lastFen) {
          try {
            _boardController.loadFen(update.fen);
            _chess.load(update.fen);
            _lastFen = update.fen;
            _selectedSquare = null;
            _possibleMoveSquares = [];
          } catch (e) {
            _showSnackBar('Error updating board: $e');
          }
        }
      });
    };
  }

  void _onSquareTapped(String square) {
    if (!_isMyTurn || _gameOver) {
      _showSnackBar("It's not your turn or game is over");
      return;
    }

    setState(() {
      if (_selectedSquare == null) {
        final piece = _chess.get(square);
        if (piece != null &&
            ((_playerColor == PlayerColor.white && piece.color == chess.Color.WHITE) ||
                (_playerColor == PlayerColor.black && piece.color == chess.Color.BLACK))) {
          _selectedSquare = square;
          _possibleMoveSquares = _chess.moves({'square': square, 'verbose': true})
              .whereType<Map<String, dynamic>>()
              .map((move) => move['to'] as String)
              .toList();
        }
      } else {
        if (_possibleMoveSquares.contains(square)) {
          _attemptMove(_selectedSquare!, square);
        }
        _selectedSquare = null;
        _possibleMoveSquares = [];
      }
    });
  }

  Future<void> _attemptMove(String from, String to) async {
    try {
      String? promotion;
      final piece = _chess.get(from);

      if (piece?.type == chess.PieceType.PAWN &&
          ((piece?.color == chess.Color.WHITE && to[1] == '8') ||
              (piece?.color == chess.Color.BLACK && to[1] == '1'))) {
        promotion = await _showPromotionDialog(context);
        if (promotion == null) return;
      }

      final success = await _gameService.makeMove(from, to, promotion);
      if (!success) {
        _showSnackBar("Invalid move");
      }
    } catch (e) {
      _showSnackBar("Move failed: $e");
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }


  void _showGameOverDialog(String title, String message) {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: <Widget>[
              TextButton(
                child: const Text('Back to Home'),
                onPressed: () {
                  _gameService.dispose();
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }
  }

  void _showChallengeDialog(GameUpdate update) {
    if (mounted && update.incomingChallengeId != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Incoming Chess Challenge!'),
            content: Text('Challenge from: ${update.incomingChallengerName ?? 'Unknown'}\n'
                'Variant: ${update.incomingChallengeVariant ?? 'Standard'}\n'
                'Time: ${update.incomingChallengeTime ?? '?'}+${update.incomingChallengeIncrement ?? '?'}'),
            actions: <Widget>[
              TextButton(
                child: const Text('Decline'),
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _gameService.declineChallenge(update.incomingChallengeId!);
                  setState(() => _incomingChallengeId = null);
                  _showSnackBar('Challenge declined.');
                },
              ),
              TextButton(
                child: const Text('Accept'),
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _gameService.acceptChallenge(update.incomingChallengeId!);
                  setState(() => _incomingChallengeId = null);
                  _showSnackBar('Challenge accepted. Starting game...');
                },
              ),
            ],
          );
        },
      );
    }
  }

  Widget _buildGameControls() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!_gameOver)
            ElevatedButton(
              onPressed: () async {
                final confirmResign = await showDialog<bool>(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text('Resign Game?'),
                      content: const Text('Are you sure you want to resign?'),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Resign'),
                        ),
                      ],
                    );
                  },
                ) ?? false;

                if (confirmResign) {
                  try {
                    await _gameService.resign();
                  } catch (e) {
                    _showSnackBar('Failed to resign: ${e.toString()}');
                  }
                }
              },
              child: const Text('Resign'),
            ),
          const SizedBox(width: 20),
          if (_gameOver)
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('New Game'),
            ),
        ],
      ),
    );
  }

  Offset _getSquarePosition(String square, double squareSize) {
    final int fileIndex = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final int rankIndex = int.parse(square[1]) - 1;

    final double left = fileIndex * squareSize;
    final double top = (_playerColor == PlayerColor.white ? (7 - rankIndex) : rankIndex) * squareSize;

    return Offset(left, top);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_opponentName != null
            ? 'vs $_opponentName (${_opponentRating ?? '?'})'
            : 'Chess Game'),
        actions: [
          if (_gameOver)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _gameService.dispose();
                Navigator.pop(context);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(_status.isEmpty
                ? 'Connecting...'
                : (_gameService.isConnected ? _status : 'Reconnecting...'),
              style: TextStyle(
                fontSize: 16,
                color: _isMyTurn
                    ? Colors.green
                    : (_gameService.isConnected ? Colors.blue : Colors.red),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double boardSize = constraints.maxWidth < constraints.maxHeight
                      ? constraints.maxWidth
                      : constraints.maxHeight;
                  final double squareSize = boardSize / 8;

                  List<Widget> highlights = [];

                  if (_selectedSquare != null) {
                    final offset = _getSquarePosition(_selectedSquare!, squareSize);
                    highlights.add(
                      Positioned(
                        left: offset.dx,
                        top: offset.dy,
                        width: squareSize,
                        height: squareSize,
                        child: Container(
                          color: Colors.yellow.withOpacity(0.5),
                        ),
                      ),
                    );
                  }

                  for (String possibleSquare in _possibleMoveSquares) {
                    final offset = _getSquarePosition(possibleSquare, squareSize);
                    final chess.Piece? targetPiece = _chess.get(possibleSquare);
                    final bool isCapture = targetPiece != null &&
                        ((_playerColor == PlayerColor.white && targetPiece.color == chess.Color.BLACK) ||
                            (_playerColor == PlayerColor.black && targetPiece.color == chess.Color.WHITE));

                    highlights.add(
                      Positioned(
                        left: offset.dx + (isCapture ? 0 : squareSize * 0.35),
                        top: offset.dy + (isCapture ? 0 : squareSize * 0.35),
                        width: isCapture ? squareSize : squareSize * 0.3,
                        height: isCapture ? squareSize : squareSize * 0.3,
                        child: Container(
                          decoration: BoxDecoration(
                            color: isCapture ? Colors.red.withOpacity(0.7) : Colors.blue.withOpacity(0.7),
                            shape: isCapture ? BoxShape.rectangle : BoxShape.circle,
                            border: isCapture ? Border.all(color: Colors.red, width: 2.0) : null,
                          ),
                        ),
                      ),
                    );
                  }

                  return Stack(
                    children: [
                      ChessBoard(
                        controller: _boardController,
                        boardOrientation: _playerColor,
                        size: boardSize,
                        enableUserMoves: false,
                      ),
                      Positioned.fill(
                        child: GestureDetector(
                          onTapUp: (_isMyTurn && !_gameOver) ? (details) {
                            final RenderBox renderBox = context.findRenderObject() as RenderBox;
                            final Offset localPosition = renderBox.globalToLocal(details.globalPosition);

                            if (localPosition.dx >= 0 && localPosition.dx < boardSize &&
                                localPosition.dy >= 0 && localPosition.dy < boardSize) {

                              // ===================================================================
                              // ## THE FIX IS HERE ##
                              // The column calculation now inverts based on player color to match
                              // the visual orientation of the board.
                              // ===================================================================
                              final int col = (_playerColor == PlayerColor.white)
                                  ? (localPosition.dx / squareSize).floor()
                                  : (7 - (localPosition.dx / squareSize).floor());

                              final int row = (_playerColor == PlayerColor.white)
                                  ? (7 - (localPosition.dy / squareSize).floor())
                                  : (localPosition.dy / squareSize).floor();

                              if (col >= 0 && col < 8 && row >= 0 && row < 8) {
                                final String file = String.fromCharCode('a'.codeUnitAt(0) + col);
                                final String rank = (row + 1).toString();
                                final String tappedSquare = '$file$rank';
                                _onSquareTapped(tappedSquare);
                              }
                            }
                          } : null,
                        ),
                      ),
                      ...highlights,
                    ],
                  );
                },
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
          _buildGameControls(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _gameService.dispose();
    super.dispose();
  }
}