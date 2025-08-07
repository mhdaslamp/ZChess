// UIdemo.dart
import 'package:flutter/material.dart';
import 'package:flutter_chess_board/flutter_chess_board.dart';
import 'package:chess/chess.dart' as chess;
import 'dart:math';
import 'dart:async'; // Import for Timer

enum GameMode {
  humanVsBot,
  humanVsHuman,
}

class LocalChessBoardScreen extends StatefulWidget {
  // RE-ADDED: initialGameMode as a required parameter
  final GameMode initialGameMode;

  const LocalChessBoardScreen({super.key, required this.initialGameMode});

  @override
  State<LocalChessBoardScreen> createState() => _LocalChessBoardScreenState();
}

class _LocalChessBoardScreenState extends State<LocalChessBoardScreen> {
  ChessBoardController controller = ChessBoardController();

  String? _selectedSquare;
  List<String> _possibleMoveSquares = [];

  final GlobalKey _boardKey = GlobalKey();

  late GameMode _gameMode; // Initialize from widget parameter
  final chess.Color _botColor = chess.Color.BLACK; // Bot is always black
  bool _isProcessingBotMove = false;

  Timer? _currentTurnTimer;
  Duration _whiteTimeRemaining = const Duration(minutes: 5);
  Duration _blackTimeRemaining = const Duration(minutes: 5);
  final Duration _timeIncrement = const Duration(seconds: 0);

  final Map<String, int> _pieceValues = {
    'p': 1, 'n': 3, 'b': 3, 'r': 5, 'q': 9, 'k': 0
  };

  int _whiteCapturedPoints = 0;
  int _blackCapturedPoints = 0;

  @override
  void initState() {
    super.initState();
    _gameMode = widget.initialGameMode; // Set initial game mode from parameter
    controller.addListener(_onBoardChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startTimer(controller.game.turn);
      _checkAndMakeBotMove(); // Only runs if _gameMode is humanVsBot
      _checkGameOver();
    });
  }

  @override
  void dispose() {
    _currentTurnTimer?.cancel();
    controller.removeListener(_onBoardChanged);
    controller.dispose();
    super.dispose();
  }

  void _startTimer(chess.Color color) {
    _currentTurnTimer?.cancel();

    if (controller.game.game_over) {
      return;
    }

    _currentTurnTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (color == chess.Color.WHITE) {
          if (_whiteTimeRemaining.inSeconds > 0) {
            _whiteTimeRemaining = _whiteTimeRemaining - const Duration(seconds: 1);
          } else {
            timer.cancel();
            _handleTimeout(color);
          }
        } else { // Black's turn
          if (_blackTimeRemaining.inSeconds > 0) {
            _blackTimeRemaining = _blackTimeRemaining - const Duration(seconds: 1);
          } else {
            timer.cancel();
            _handleTimeout(color);
          }
        }
      });
    });
  }

  void _stopTimers() {
    _currentTurnTimer?.cancel();
    _currentTurnTimer = null;
  }

  void _resetTimers() {
    _stopTimers();
    setState(() {
      _whiteTimeRemaining = const Duration(minutes: 5);
      _blackTimeRemaining = const Duration(minutes: 5);
    });
  }

  void _handleTimeout(chess.Color timedOutColor) {
    _stopTimers();
    String winner = timedOutColor == chess.Color.WHITE ? 'Black' : 'White';
    _showGameOverDialog('Game Over!', '$winner wins by Timeout!');
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  void _onBoardChanged() {
    // Clear possible moves if game is over or a new turn
    if (_selectedSquare != null) {
      _calculateAndSetPossibleMoves(_selectedSquare!);
    } else {
      setState(() {
        _possibleMoveSquares = [];
      });
    }

    // Apply increment to the player who just *completed* their turn
    if (controller.game.turn == chess.Color.BLACK) { // White just moved
      setState(() {
        _whiteTimeRemaining += _timeIncrement;
      });
    } else { // Black just moved
      setState(() {
        _blackTimeRemaining += _timeIncrement;
      });
    }

    _stopTimers();
    if (!controller.game.game_over) {
      _startTimer(controller.game.turn);
    }

    _checkGameOver();
    if (_gameMode == GameMode.humanVsBot) {
      _checkAndMakeBotMove();
    }
  }

  void _calculateAndSetPossibleMoves(String square) {
    final chess.Chess game = controller.game;
    // Ensure the selected piece belongs to the current turn's player
    if (game.get(square)?.color != controller.game.turn) {
      setState(() {
        _selectedSquare = null;
        _possibleMoveSquares = [];
      });
      return;
    }

    final List<dynamic> rawMoves = game.moves({
      'square': square,
      'verbose': true,
    });

    setState(() {
      _selectedSquare = square;
      _possibleMoveSquares = rawMoves.map((moveMap) => moveMap['to'] as String).toList();
    });
  }

  void _onPieceTap(String tappedSquare) async {
    // Prevent interaction if bot is thinking or game is over
    if (_isProcessingBotMove || controller.game.game_over) {
      print("Local game tap ignored: _isProcessingBotMove=$_isProcessingBotMove, game_over=${controller.game.game_over}");
      return;
    }

    final chess.Chess game = controller.game;
    final bool isTappedSquareOccupied = game.get(tappedSquare) != null;
    final bool isTappedPieceOfCurrentPlayer = isTappedSquareOccupied &&
        ((game.turn == chess.Color.WHITE && game.get(tappedSquare)!.color == chess.Color.WHITE) ||
            (game.turn == chess.Color.BLACK && game.get(tappedSquare)!.color == chess.Color.BLACK));

    if (_selectedSquare == null) {
      // If no piece is selected, and tapped piece belongs to current turn, select it
      if (isTappedPieceOfCurrentPlayer) {
        _calculateAndSetPossibleMoves(tappedSquare);
      } else {
        setState(() {
          _possibleMoveSquares = []; // Clear highlights if tapping an empty square or opponent's piece
        });
      }
    } else {
      // A piece is already selected
      if (_selectedSquare == tappedSquare) {
        // Tapped the same piece, deselect it
        setState(() {
          _selectedSquare = null;
          _possibleMoveSquares = [];
        });
      } else if (_possibleMoveSquares.contains(tappedSquare)) {
        // Tapped a valid move square, attempt the move
        String? promotionPiece;
        final chess.Piece? selectedPiece = game.get(_selectedSquare!);

        bool isPromotionMove = false;
        if (selectedPiece != null &&
            selectedPiece.type == chess.PieceType.PAWN &&
            ((selectedPiece.color == chess.Color.WHITE && tappedSquare[1] == '8') ||
                (selectedPiece.color == chess.Color.BLACK && tappedSquare[1] == '1'))) {
          isPromotionMove = true;
          promotionPiece = await _showPromotionDialog(context);
          if (promotionPiece == null) {
            // Promotion cancelled, deselect
            setState(() {
              _selectedSquare = null;
              _possibleMoveSquares = [];
            });
            return;
          }
        }

        final chess.Piece? capturedPiece = game.get(tappedSquare);
        if (capturedPiece != null) {
          final int points = _pieceValues[capturedPiece.type.toLowerCase()] ?? 0;
          setState(() {
            if (game.turn == chess.Color.WHITE) {
              _whiteCapturedPoints += points;
            } else {
              _blackCapturedPoints += points;
            }
          });
        }

        final moveResult = controller.game.move({
          'from': _selectedSquare!,
          'to': tappedSquare,
          'promotion': promotionPiece,
        });

        if (moveResult != null) {
          controller.notifyListeners(); // Notify ChessBoard to redraw
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid move. Please select a valid move.')),
          );
        }

        setState(() {
          _selectedSquare = null;
          _possibleMoveSquares = [];
        });
      } else if (isTappedPieceOfCurrentPlayer) {
        // Tapped another one of current player's pieces, select it instead
        _calculateAndSetPossibleMoves(tappedSquare);
      } else {
        // Tapped an opponent's piece or empty square, deselect current
        setState(() {
          _selectedSquare = null;
          _possibleMoveSquares = [];
        });
      }
    }
  }


  void _handleBoardTap(Offset localPosition) {
    if (_isProcessingBotMove || controller.game.game_over) return; // Allow tap in PvP

    final RenderBox? renderBox = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      debugPrint("Error: Could not find RenderBox for ChessBoard.");
      return;
    }

    final Size boardSize = renderBox.size;
    final double squareSize = boardSize.width / 8;

    final int col = (localPosition.dx / squareSize).floor();
    final int row = 7 - (localPosition.dy / squareSize).floor();

    if (col >= 0 && col < 8 && row >= 0 && row < 8) {
      final String file = String.fromCharCode('a'.codeUnitAt(0) + col);
      final String rank = (row + 1).toString();
      final String tappedSquare = '$file$rank';

      _onPieceTap(tappedSquare);
    }
  }

  Offset _getSquarePosition(String square, double squareSize) {
    final int fileIndex = square.codeUnitAt(0) - 'a'.codeUnitAt(0);
    final int rankIndex = int.parse(square[1]) - 1;

    final double left = fileIndex * squareSize;
    final double top = (7 - rankIndex) * squareSize;

    return Offset(left, top);
  }

  int _evaluateBoard(chess.Chess game) {
    int score = 0;
    for (int i = 0; i < 64; i++) {
      final piece = game.board[i];
      if (piece != null) {
        int value = _pieceValues[piece.type.toLowerCase()] ?? 0;
        if (piece.color == _botColor) {
          score += value;
        } else {
          score -= value;
        }
      }
    }

    if (game.in_checkmate) {
      if (game.turn == _botColor) {
        score += 10000;
      } else {
        score -= 10000;
      }
    } else if (game.in_stalemate || game.in_draw || game.insufficient_material) {
      score = 0;
    }

    score += (game.moves().length * 0.1).toInt();

    return score;
  }

  void _checkAndMakeBotMove() async {
    if (_gameMode == GameMode.humanVsHuman || _isProcessingBotMove || controller.game.game_over || controller.game.turn != _botColor) {
      return;
    }

    setState(() {
      _isProcessingBotMove = true;
    });

    // Simulate thinking time
    int thinkingTimeSeconds = 2;
    for (int i = 0; i < thinkingTimeSeconds; i++) {
      await Future.delayed(const Duration(seconds: 1));
    }

    final chess.Chess game = controller.game;
    final List<dynamic> allLegalMoves = game.moves({'verbose': true});

    if (allLegalMoves.isNotEmpty) {
      String? bestFrom;
      String? bestTo;
      String? bestPromotion;
      int bestScore = -999999;

      for (var moveMap in allLegalMoves) {
        final String fromSquare = moveMap['from'] as String;
        final String toSquare = moveMap['to'] as String;
        final String? promotion = moveMap['promotion'] as String?;

        final chess.Chess tempGame = game.copy();
        final chess.Piece? capturedPiece = tempGame.get(toSquare);
        tempGame.move({'from': fromSquare, 'to': toSquare, 'promotion': promotion});

        int currentMoveScore = _evaluateBoard(tempGame);

        if (capturedPiece != null && capturedPiece.color != _botColor) {
          currentMoveScore += (_pieceValues[capturedPiece.type.toLowerCase()] ?? 0);
        }

        if (currentMoveScore > bestScore) {
          bestScore = currentMoveScore;
          bestFrom = fromSquare;
          bestTo = toSquare;
          bestPromotion = promotion;
        }
      }

      if (bestFrom != null && bestTo != null) {
        final chess.Piece? capturedPiece = game.get(bestTo!);
        if (capturedPiece != null && capturedPiece.color != _botColor) {
          final int points = _pieceValues[capturedPiece.type.toLowerCase()] ?? 0;
          setState(() {
            _blackCapturedPoints += points;
          });
        }

        controller.game.move({
          'from': bestFrom,
          'to': bestTo,
          'promotion': bestPromotion,
        });
        controller.notifyListeners();
      }
    }

    setState(() {
      _isProcessingBotMove = false;
    });
  }

  Future<String?> _showPromotionDialog(BuildContext context) async {
    return showDialog<String>(
      context: context,
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

  void _checkGameOver() {
    final chess.Chess game = controller.game;
    String? result;

    if (game.in_checkmate) {
      result = game.turn == chess.Color.WHITE ? 'Black wins by Checkmate!' : 'White wins by Checkmate!';
    } else if (game.in_stalemate) {
      result = 'Draw by Stalemate!';
    } else if (game.in_draw) {
      result = 'Draw!';
    } else if (game.insufficient_material) {
      result = 'Draw by Insufficient Material!';
    }

    if (result != null) {
      _showGameOverDialog('Game Over!', result);
    }
  }

  void _showGameOverDialog(String title, String message) {
    _stopTimers();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: const Text('Play Again'),
              onPressed: () {
                Navigator.of(context).pop();
                _resetGame();
              },
            ),
          ],
        );
      },
    );
  }

  void _resetGame() {
    controller.resetBoard();
    setState(() {
      _selectedSquare = null;
      _possibleMoveSquares = [];
      _isProcessingBotMove = false;
      _whiteCapturedPoints = 0;
      _blackCapturedPoints = 0;
    });
    _resetTimers();
    if (_gameMode == GameMode.humanVsBot) {
      _checkAndMakeBotMove();
    }
  }

  @override
  Widget build(BuildContext context) {
    String screenTitle = _gameMode == GameMode.humanVsBot ? 'Human vs Bot (Offline)' : 'Human vs Human (Offline)';

    return Scaffold(
      appBar: AppBar(
        title: Text(screenTitle),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Removed Game Mode Selector - it's now on the previous screen
            // Black's Timer and Captured Points (Player 2 or Bot)
            Text(
              'Black: ${_formatDuration(_blackTimeRemaining)} (Captured: $_blackCapturedPoints)',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: controller.game.turn == chess.Color.BLACK ? Colors.red : Colors.black,
              ),
            ),
            const SizedBox(height: 15),

            LayoutBuilder(
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
                  highlights.add(
                    Positioned(
                      left: offset.dx + squareSize * 0.35,
                      top: offset.dy + squareSize * 0.35,
                      width: squareSize * 0.3,
                      height: squareSize * 0.3,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.7),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }

                return GestureDetector(
                  onTapUp: (_isProcessingBotMove && _gameMode == GameMode.humanVsBot) || controller.game.game_over ? null : (details) {
                    _handleBoardTap(details.localPosition);
                  },
                  child: Stack(
                    children: [
                      ChessBoard(
                        key: _boardKey,
                        controller: controller,
                        boardColor: BoardColor.brown,
                        boardOrientation: PlayerColor.white, // Always orient for White at bottom
                        enableUserMoves: false, // We handle moves manually
                        onMove: () {
                          setState(() {
                            _selectedSquare = null;
                            _possibleMoveSquares = [];
                          });
                        },
                      ),
                      ...highlights,
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 15),

            // White's Timer and Captured Points (Player 1)
            Text(
              'White: ${_formatDuration(_whiteTimeRemaining)} (Captured: $_whiteCapturedPoints)',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: controller.game.turn == chess.Color.WHITE ? Colors.red : Colors.black,
              ),
            ),
            const SizedBox(height: 20),

            // --- Game Control Buttons ---
            ElevatedButton(
              onPressed: _resetGame,
              child: const Text('Reset Board'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () {
                // Determine winner based on current turn for resignation
                String winner = controller.game.turn == chess.Color.WHITE ? 'Black' : 'White';
                _showGameOverDialog('Resignation', '${controller.game.turn == chess.Color.WHITE ? 'White' : 'Black'} resigned. $winner wins!');
              },
              child: const Text('Resign'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}