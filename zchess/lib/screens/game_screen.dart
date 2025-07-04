import 'package:flutter/material.dart';
import '../services/game_service.dart';
import '../models/game_update.dart';  // Add this import

class GameScreen extends StatefulWidget {
  final String accessToken;
  final String username;

  const GameScreen({
    required this.accessToken,
    required this.username,
  });

  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final GameService _gameService;
  String gameState = 'Initializing...';
  bool isMyTurn = false;
  List<String> moves = [];
  String? opponentName;
  String? opponentRating;
  String? myColor;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _gameService = GameService(
      accessToken: widget.accessToken,
      username: widget.username,
    );
    _initializeGame();
  }

  Future<void> _initializeGame() async {
    _gameService.onGameUpdate = (update) {
      setState(() {
        gameState = update.status;
        isMyTurn = update.isMyTurn;
        moves = update.moves;
        opponentName = update.opponentName;
        opponentRating = update.opponentRating;
        myColor = update.myColor;
        isLoading = false;
      });
    };

    try {
      await _gameService.startGame();
    } catch (e) {
      setState(() {
        gameState = 'Error: ${e.toString()}';
        isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _gameService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(opponentName != null
            ? 'vs $opponentName (${opponentRating ?? '?'})'
            : 'Lichess Game'),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Text(gameState),
          if (isMyTurn)
            ElevatedButton(
              onPressed: () => _gameService.makeMove('e2e4'),
              child: Text('Make Sample Move'),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: moves.length,
              itemBuilder: (context, index) => ListTile(
                title: Text(moves[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}