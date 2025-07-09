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
  late chess.Chess _chess; // Local chess.js instance for client-side move validation and state
  late ChessBoardController _boardController;

  // Corrected nullability for state variables to match GameUpdate fields
  String _status = 'Creating game...'; // status from GameUpdate is now required String
  String? _opponentName; // opponentName from GameUpdate is String?
  String? _opponentRating; // opponentRating from GameUpdate is String?
  bool _isMyTurn = false; // isMyTurn from GameUpdate is required bool
  bool _gameOver = false; // gameOver from GameUpdate is required bool
  PlayerColor _playerColor = PlayerColor.white; // This will be set by GameService
  String? _gameId; // gameId from GameUpdate is String?
  String _lastFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'; // Initial FEN

  // State for user interaction to handle potential promotions and highlights
  String? _selectedSquare;
  List<String> _possibleMoveSquares = [];

  @override
  void initState() {
    super.initState();
    _chess = chess.Chess(); // Initialize local chess board instance
    _boardController = ChessBoardController();

    _gameService = GameService(
      accessToken: widget.accessToken,
      username: widget.username,
    );

    _initializeGame();
    _gameService.startGame();
  }

  void _initializeGame() {
    _gameService.onGameUpdate = (GameUpdate update) {
      debugPrint('Game Update Received:');
      debugPrint('FEN: ${update.fen}');
      debugPrint('Status: ${update.status}');
      debugPrint('IsMyTurn: ${update.isMyTurn}');
      if (mounted) { // Ensure the widget is still in the tree
        setState(() {
          // These are now directly assigned as they are required and non-nullable in GameUpdate
          _status = update.status;
          _isMyTurn = update.isMyTurn;
          _gameOver = update.gameOver;

          // These are nullable in GameUpdate, so assigned to nullable state variables
          _opponentName = update.opponentName;
          _opponentRating = update.opponentRating;
          _gameId = update.gameId;


          if (update.myColor != null) {
            _playerColor = update.myColor == 'white'
                ? PlayerColor.white
                : PlayerColor.black;
          }

          // Only update board if FEN has changed
          if (update.fen != _lastFen) {
            try {
              // Update the UI board controller
              _boardController.loadFen(update.fen!);

              // ✅ Update the internal chess logic state as well
              _chess.load(update.fen!);

              _lastFen = update.fen!;

              // Clear selection states
              _selectedSquare = null;
              _possibleMoveSquares = [];
            } catch (e) {
              if (mounted) {
                _showSnackBar('Error updating board: $e');
              }
            }
          }

          // If game is over, notify the user and potentially navigate back
          if (_gameOver) {
            _showGameOverDialog('Game Over', _status); // Pass status from GameUpdate
          }
        });
      }
    };
  }

  // This function is for handling taps to select squares and show possible moves
  void _onSquareTapped(String square) async {
    if (!_isMyTurn || _gameOver) {
      final currentFen = _boardController.getFen();
      final tempChess = chess.Chess()..load(currentFen);
      // Ignore taps if it's not our turn or game is over
      print("Tap ignored: Not my turn or game over. IsMyTurn: $_isMyTurn, GameOver: $_gameOver");
      return;
    }

    final currentFen = _boardController.getFen();
    _chess.load(currentFen);
    final chess.Piece? tappedPiece = _chess.get(square);
    final bool isTappedSquareOccupied = tappedPiece != null;
    final bool isTappedPieceOfCurrentPlayer = isTappedSquareOccupied &&
        ((_playerColor == PlayerColor.white && tappedPiece.color == chess.Color.WHITE) ||
            (_playerColor == PlayerColor.black && tappedPiece.color == chess.Color.BLACK));

    setState(() {
      if (_selectedSquare == null) {
        // No square selected, select the tapped square if it's our piece
        if (isTappedPieceOfCurrentPlayer) {
          _selectedSquare = square;
          // Get possible moves in verbose format and filter for valid 'to' squares
          _possibleMoveSquares = _chess
              .moves({'square': square, 'verbose': true})
              .whereType<Map<String, dynamic>>() // Ensure we only process maps
              .map((moveMap) => moveMap['to'] as String)
              .toList();
        } else {
          // Tapped an empty square or opponent's piece without a selected piece
          _possibleMoveSquares = [];
        }
      } else {
        // A square is already selected
        if (_selectedSquare == square) {
          // Tapped the same selected square, deselect
          _selectedSquare = null;
          _possibleMoveSquares = [];
        } else if (_possibleMoveSquares.contains(square)) {
          // Tapped a valid move target, attempt the move
          _attemptMove(_selectedSquare!, square); // _attemptMove uses from/to strings directly
          // Clear selected square and possible moves immediately,
          // the board will update when Lichess sends the new FEN
          _selectedSquare = null;
          _possibleMoveSquares = [];
        } else if (isTappedPieceOfCurrentPlayer) {
          // Tapped a different piece of the current player, switch selection
          _selectedSquare = square;
          _possibleMoveSquares = _chess
              .moves({'square': square, 'verbose': true})
              .whereType<Map<String, dynamic>>() // Ensure we only process maps
              .map((moveMap) => moveMap['to'] as String)
              .toList();
        } else {
          // Tapped an invalid target or opponent's piece, clear selection
          _selectedSquare = null;
          _possibleMoveSquares = [];
        }
      }
    });
  }

  Future<void> _attemptMove(String from, String to) async {
    debugPrint('=== MOVE ATTEMPT STARTED ===');
    debugPrint('Attempting move: $from$to');
    debugPrint('Current FEN: ${_boardController.getFen()}');
    debugPrint('IsMyTurn: $_isMyTurn, GameOver: $_gameOver');

    if (!_isMyTurn || _gameOver) {
      debugPrint('Move rejected - not player\'s turn or game over');
      return;
    }

    // Load current state
    final currentFen = _boardController.getFen();
    final tempChess = chess.Chess()..load(currentFen);

    // Check for promotion
    String? promotionPiece;
    final piece = tempChess.get(from);
    if (piece?.type == chess.PieceType.PAWN &&
        ((piece?.color == chess.Color.WHITE && to[1] == '8') ||
            (piece?.color == chess.Color.BLACK && to[1] == '1'))) {
      promotionPiece = await _showPromotionDialog(context);
      if (promotionPiece == null) {
        debugPrint('Promotion cancelled by user');
        return;
      }
      debugPrint('Promotion piece selected: $promotionPiece');
    }

    try {
      // First validate locally
      final moves = tempChess.moves({'square': from, 'verbose': true});
      final isValidMove = moves.any((m) =>
      m is Map && m['from'] == from && m['to'] == to);

      if (!isValidMove) {
        _showSnackBar('Invalid move');
        return;
      }

      // Send to server
      debugPrint('Sending validated move to server');
      final success = await _gameService.makeMove(from, to, promotionPiece);

      if (!success) {
        _showSnackBar('Server rejected the move');
        return;
      }

      // Update UI state
      setState(() {
        _selectedSquare = null;
        _possibleMoveSquares = [];
      });

    } catch (e) {
      debugPrint('Move error: $e');
      _showSnackBar('Move failed: ${e.toString()}');
      if (mounted) {
        _boardController.loadFen(_lastFen);
      }
    }
  }  String _pieceToSymbol(chess.Piece piece) {


    switch (piece.type) {
      case chess.PieceType.PAWN: return piece.color == chess.Color.WHITE ? 'P' : 'p';
      case chess.PieceType.KNIGHT: return piece.color == chess.Color.WHITE ? 'N' : 'n';
      case chess.PieceType.BISHOP: return piece.color == chess.Color.WHITE ? 'B' : 'b';
      case chess.PieceType.ROOK: return piece.color == chess.Color.WHITE ? 'R' : 'r';
      case chess.PieceType.QUEEN: return piece.color == chess.Color.WHITE ? 'Q' : 'q';
      case chess.PieceType.KING: return piece.color == chess.Color.WHITE ? 'K' : 'k';
      default: return '?';
    }
  }
  String _pieceToChar(chess.Piece piece) {
    final char = piece.type.toString().substring(10, 11).toLowerCase();
    return piece.color == chess.Color.WHITE ? char.toUpperCase() : char;
  }  Future<String?> _showPromotionDialog(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false, // Force user to pick a promotion piece
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Pawn Promotion'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop('q'),
                child: const Text('Queen'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop('r'),
                child: const Text('Rook'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop('b'),
                child: const Text('Bishop'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop('n'),
                child: const Text('Knight'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
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
                  Navigator.of(context).pop(); // Close dialog
                  Navigator.of(context).pop(); // Go back to previous screen
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
          if (!_gameOver) // Only show resign button if game is not over
            ElevatedButton(
              onPressed: _isMyTurn && !_gameOver ? () async {
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
                    // GameService will handle the game finish via stream
                  } catch (e) {
                    _showSnackBar('Failed to resign: ${e.toString()}');
                  }
                }
              } : null, // Disable if not player's turn or game over
              child: const Text('Resign'),
            ),
          const SizedBox(width: 20),
          if (_gameOver)
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('New Game'), // This will navigate back to game creation screen
            ),
        ],
      ),
    );
  }

  Offset _getSquarePosition(String square, double squareSize) {
    final int fileIndex = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final int rankIndex = int.parse(square[1]) - 1;

    // Adjust for board orientation dynamically based on _playerColor
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
              onPressed: () => Navigator.pop(context), // Go back to previous screen
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double boardSize = constraints.maxWidth < constraints.maxHeight
                      ? constraints.maxWidth
                      : constraints.maxHeight;
                  final double squareSize = boardSize / 8;

                  List<Widget> highlights = [];

                  // Selected square highlight
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

                  // Possible moves highlights
                  for (String possibleSquare in _possibleMoveSquares) {
                    final offset = _getSquarePosition(possibleSquare, squareSize);
                    // Determine if the target square has an opponent's piece for a capture indicator
                    final chess.Piece? targetPiece = _chess.get(possibleSquare);
                    final bool isCapture = targetPiece != null &&
                        ((_playerColor == PlayerColor.white && targetPiece.color == chess.Color.BLACK) ||
                            (_playerColor == PlayerColor.black && targetPiece.color == chess.Color.WHITE));

                    highlights.add(
                      Positioned(
                        left: offset.dx + (isCapture ? 0 : squareSize * 0.35), // Full square for capture
                        top: offset.dy + (isCapture ? 0 : squareSize * 0.35),
                        width: isCapture ? squareSize : squareSize * 0.3,
                        height: isCapture ? squareSize : squareSize * 0.3,
                        child: Container(
                          decoration: BoxDecoration(
                            color: isCapture ? Colors.red.withOpacity(0.7) : Colors.blue.withOpacity(0.7),
                            shape: isCapture ? BoxShape.rectangle : BoxShape.circle,
                            border: isCapture ? Border.all(color: Colors.red, width: 2.0) : null, // Add border for capture
                          ),
                        ),
                      ),
                    );
                  }

                  return Stack(
                    children: [
                      ChessBoard(
                        controller: _boardController,
                        boardOrientation: _playerColor, // Set dynamically by GameService
                        size: boardSize,
                        enableUserMoves: false, // <<-- THIS IS THE KEY!
                        // onMove callback is NOT used when enableUserMoves is false.
                        // We handle user input via GestureDetector below.
                      ),
                      // GestureDetector to handle square taps for move selection and highlights
                      Positioned.fill(
                        child: GestureDetector(
                          onTapUp: (_isMyTurn && !_gameOver) ? (details) {
                            // Calculate which square was tapped
                            final RenderBox renderBox = context.findRenderObject() as RenderBox;
                            final Offset localPosition = renderBox.globalToLocal(details.globalPosition);

                            final int col = (localPosition.dx / squareSize).floor();
                            // Invert row calculation if player is white (boardOrientation is white)
                            // because ChessBoard renders A1 at bottom-left for white, A8 at top-left.
                            // So, y=0 is rank 8 for white, and y=boardSize is rank 1.
                            final int row = (_playerColor == PlayerColor.white)
                                ? (7 - (localPosition.dy / squareSize).floor())
                                : (localPosition.dy / squareSize).floor(); // If black, 0 is rank 1

                            if (col >= 0 && col < 8 && row >= 0 && row < 8) {
                              final String file = String.fromCharCode('a'.codeUnitAt(0) + col);
                              final String rank = (row + 1).toString();
                              final String tappedSquare = '$file$rank';
                              _onSquareTapped(tappedSquare); // Call our custom tap handler
                            }
                          } : null, // Disable GestureDetector if not turn or game over
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
    _boardController.dispose();
    super.dispose();
  }
}
