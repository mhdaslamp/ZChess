class GameUpdate {
  final String? gameId;
  final String status;
  final bool isMyTurn;
  final List<String> moves;
  final String? opponentName;
  final String? opponentRating;
  final String? myColor;
  final String fen; // <--- Make sure it's String, not String?
  final String? lastMove;
  final bool gameOver;

  GameUpdate({
    this.gameId,
    required this.status,
    required this.isMyTurn,
    required this.moves,
    this.opponentName,
    this.opponentRating,
    this.myColor,
    required this.fen, // <--- Make sure it's required
    this.lastMove,
    required this.gameOver,
  });
}