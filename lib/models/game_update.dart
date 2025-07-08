class GameUpdate {
  final String status;
  final bool isMyTurn;
  final List<String> moves;
  final String? opponentName;
  final String? opponentRating;
  final String? myColor;
  final String? lastMove;

  GameUpdate({
    required this.status,
    required this.isMyTurn,
    required this.moves,
    this.opponentName,
    this.opponentRating,
    this.myColor,
    this.lastMove,
  });
}
typedef GameUpdateCallback = void Function(GameUpdate);