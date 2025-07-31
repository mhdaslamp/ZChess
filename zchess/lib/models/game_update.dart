import 'package:flutter/foundation.dart'; // Added for debugPrint

class GameUpdate {
  final String status;
  final bool isMyTurn;
  final List<String> moves;
  final String fen; // Added FEN field
  final String? opponentName;
  final String? opponentRating;
  final String? myColor;
  final String? lastMove;
  final String? gameId; // Added gameId field
  final bool gameOver; // Added gameOver field

  // New fields for incoming challenges
  final String? incomingChallengeId;
  final String? incomingChallengerName;
  final String? incomingChallengeSpeed;
  final String? incomingChallengeTime;
  final String? incomingChallengeIncrement;
  final String? incomingChallengeVariant;
  final bool? incomingChallengeRated;


  GameUpdate({
    required this.status,
    required this.isMyTurn,
    required this.moves,
    required this.fen, // Make FEN required in constructor
    this.opponentName,
    this.opponentRating,
    this.myColor,
    this.lastMove,
    this.gameId, // Added gameId to constructor
    required this.gameOver, // Added gameOver to constructor

    // Challenge fields
    this.incomingChallengeId,
    this.incomingChallengerName,
    this.incomingChallengeSpeed,
    this.incomingChallengeTime,
    this.incomingChallengeIncrement,
    this.incomingChallengeVariant,
    this.incomingChallengeRated,
  });

  @override
  String toString() {
    return 'GameUpdate(status: $status, isMyTurn: $isMyTurn, moves: $moves, fen: $fen, opponentName: $opponentName, gameOver: $gameOver, gameId: $gameId, incomingChallengeId: $incomingChallengeId)';
  }
}
typedef GameUpdateCallback = void Function(GameUpdate);