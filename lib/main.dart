// main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'UIdemo.dart'; // Your local chess board

void main() => runApp(MyApp());

const LICHESS_CLIENT_ID = 'lichess.org'; // Public client
const REDIRECT_URI = 'com.example.lichessapp://oauthredirect';
const LICHESS_API = 'https://lichess.org/api';

final FlutterAppAuth appAuth = FlutterAppAuth();

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lichess Chess',
      theme: ThemeData(
        primarySwatch: Colors.brown,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: LichessLoginPage(),
    );
  }
}

class LichessLoginPage extends StatefulWidget {
  @override
  _LichessLoginPageState createState() => _LichessLoginPageState();
}

class _LichessLoginPageState extends State<LichessLoginPage> {
  String? username;
  int? blitzRating;
  String? accessToken;
  WebSocketChannel? eventChannel;
  StreamSubscription? eventSubscription;

  bool _isLoggingIn = false; // To show loading indicator during login

  @override
  void dispose() {
    eventChannel?.sink.close();
    eventSubscription?.cancel();
    super.dispose();
  }

  Future<void> loginWithLichess() async {
    setState(() {
      _isLoggingIn = true;
    });
    try {
      final request = AuthorizationTokenRequest(
        LICHESS_CLIENT_ID,
        REDIRECT_URI,
        serviceConfiguration: AuthorizationServiceConfiguration(
          authorizationEndpoint: 'https://lichess.org/oauth',
          tokenEndpoint: 'https://lichess.org/api/token',
        ),
        scopes: ['preference:read', 'challenge:write', 'board:play'],
      );

      print('🔑 OAuth request: ${jsonEncode({
        'clientId': request.clientId,
        'redirectUrl': request.redirectUrl,
        'scopes': request.scopes,
        'authorizationEndpoint': request.serviceConfiguration?.authorizationEndpoint ?? 'N/A',
        'tokenEndpoint': request.serviceConfiguration?.tokenEndpoint ?? 'N/A',
      })}');

      final result = await appAuth.authorizeAndExchangeCode(request);

      if (result != null) {
        final userInfo = await fetchUserInfo(result.accessToken!);
        setState(() {
          accessToken = result.accessToken;
          username = userInfo['username'];
          blitzRating = userInfo['perfs']?['blitz']?['rating'];
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Logged in as $username')),
          );
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lichess login cancelled.')),
        );
      }
    } catch (e) {
      print('❌ Error during login: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: ${e.toString()}')),
      );
    } finally {
      setState(() {
        _isLoggingIn = false;
      });
    }
  }

  Future<Map<String, dynamic>> fetchUserInfo(String token) async {
    final response = await http.get(
      Uri.parse('$LICHESS_API/account'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('❌ Failed to fetch user info: ${response.statusCode} ${response.body}');
    }
  }

  Future<void> createChallenge() async {
    if (accessToken == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please login to Lichess first.')),
      );
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Creating game... waiting for opponent.')),
      );
      final response = await http.post(
        Uri.parse('$LICHESS_API/board/seek'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'rated=false&clock.limit=300&clock.increment=0&color=random',
      );

      if (response.statusCode == 200 || response.statusCode == 204) {
        print('✅ Seek created. Waiting for player...');
        listenToEventStream(accessToken!);
      } else {
        print('❌ Failed to create seek: ${response.statusCode} ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create game: ${response.body}')),
        );
      }
    } catch (e) {
      print('❌ Error creating challenge: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating game: ${e.toString()}')),
      );
    }
  }

  void listenToEventStream(String token) {
    print('🔄 Starting HTTP stream for Lichess events...');

    final client = http.Client();
    final request = http.Request('GET', Uri.parse('https://lichess.org/api/stream/event'));
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['Accept'] = 'application/x-ndjson';

    // Cancel any previous subscription to avoid multiple listeners
    eventSubscription?.cancel();

    client.send(request).then((response) {
      if (response.statusCode != 200) {
        print('❌ HTTP event stream failed to connect with status: ${response.statusCode}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to connect to Lichess events: ${response.statusCode}')),
        );
        return;
      }
      eventSubscription = response.stream // Assign the result of .listen()
          .transform(utf8.decoder)
          .transform(const LineSplitter()) // each line is a separate event
          .listen((line) {
        if (line.isEmpty) return; // Ignore empty lines

        print('📩 Event: $line');
        try {
          final data = jsonDecode(line);
          if (data['type'] == 'gameStart') {
            final gameId = data['game']['id'];
            final opponent = data['game']['opponent']['username'];
            print('🎮 Game started with $opponent (ID: $gameId)');

            // Stop listening to event stream once game starts
            eventSubscription?.cancel();
            eventSubscription = null; // Clear subscription

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChessGameScreen(
                  gameId: gameId,
                  token: token,
                  opponent: opponent,
                  playerColor: data['game']['source'] == 'api' ? (data['game']['fullId']!.startsWith(gameId + 'w') ? 'white' : 'black') : null, // Infer player color if possible
                ),
              ),
            );
          } else if (data['type'] == 'challenge') {
            // Handle incoming challenges here if needed, e.g., show a dialog to accept/decline
            print('🎯 Incoming challenge from ${data['challenge']['challenger']['username']}');
          }
        } catch (e) {
          print('❌ Failed to parse event: $e');
        }
      }, onError: (e) {
        print('❌ HTTP event stream error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lichess event stream error.')),
        );
      }, onDone: () {
        print('ℹ️ HTTP event stream closed');
        if (eventSubscription != null) { // Only show if not intentionally cancelled
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lichess event stream disconnected.')),
          );
        }
      });
    }).catchError((e) {
      print('❌ Failed to connect to HTTP stream (initial error): $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to connect to Lichess: ${e.toString()}')),
      );
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lichess Chess'),
        actions: [
          if (username != null)
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Logged in as $username',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    if (blitzRating != null)
                      Text(
                        'Blitz: $blitzRating',
                        style: const TextStyle(fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Welcome to Lichess Chess!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 40),

              // Original "Play" button now navigates to the selection screen
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const _GameModeSelectionScreen(), // Navigate to the new inner widget
                    ),
                  );
                },
                icon: const Icon(Icons.videogame_asset),
                label: const Text('Play Offline Game'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 20),

              // Lichess Login Button / Play Online Button
              if (username == null)
                _isLoggingIn
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton.icon(
                  onPressed: loginWithLichess,
                  icon: const Icon(Icons.login),
                  label: const Text('Login with Lichess (Online)'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    textStyle: const TextStyle(fontSize: 18),
                    backgroundColor: Colors.green, // Highlight login button
                  ),
                )
              else // If logged in, show "Play Online"
                ElevatedButton.icon(
                  onPressed: createChallenge,
                  icon: const Icon(Icons.group),
                  label: const Text('Play Online (Human vs. Human)'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    textStyle: const TextStyle(fontSize: 18),
                    backgroundColor: Colors.blue, // Highlight online play button
                  ),
                ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// --- NEW WIDGET: GameModeSelectionScreen (as an inner class) ---
// This widget provides the two separate buttons for game mode selection.
class _GameModeSelectionScreen extends StatelessWidget {
  const _GameModeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Game Mode'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose your opponent:',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 40),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LocalChessBoardScreen(
                        initialGameMode: GameMode.humanVsHuman,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.people),
                label: const Text('Human vs Human (Offline)'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(fontSize: 20),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const LocalChessBoardScreen(
                        initialGameMode: GameMode.humanVsBot,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.computer),
                label: const Text('Human vs Bot (Offline)'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  textStyle: const TextStyle(fontSize: 20),
                  backgroundColor: Colors.lightBlue, // Different color for bot
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChessGameScreen extends StatefulWidget {
  final String gameId;
  final String token;
  final String opponent;
  final String? playerColor; // 'white' or 'black'

  ChessGameScreen({
    super.key,
    required this.gameId,
    required this.token,
    required this.opponent,
    this.playerColor,
  });

  @override
  _ChessGameScreenState createState() => _ChessGameScreenState();
}

class _ChessGameScreenState extends State<ChessGameScreen> {
  late IOWebSocketChannel gameChannel;
  String gameState = 'Loading...';

  @override
  void initState() {
    super.initState();
    connectToGame();
  }

  void connectToGame() {
    final uri = Uri.parse('wss://lichess.org/api/board/game/stream/${widget.gameId}');

    gameChannel = IOWebSocketChannel.connect(
      uri,
      headers: {
        'Authorization': 'Bearer ${widget.token}',
      },
    );

    gameChannel.stream.listen((message) {
      if (message.trim().isEmpty) return;

      try {
        final data = jsonDecode(message);
        print('Game update: $data');

        if (data['type'] == 'gameFull') {
          setState(() {
            gameState = 'Game started with ${widget.opponent} (ID: ${widget.gameId})';
            if (widget.playerColor != null) {
              gameState += '\nYou are playing as ${widget.playerColor!.toUpperCase()}';
            }
          });
        } else if (data['type'] == 'gameState') {
          setState(() {
            gameState = 'Game in progress - Last move: ${data['moves'].split(' ').last}';
            // In a real app, you would parse data['moves'] and update your chess board UI here.
            // Example: controller.game.load_pgn(pgnString);
            // This would require passing the controller to this screen or managing the chess state here.
          });
        } else if (data['type'] == 'chatLine') {
          print('Chat: ${data['username']}: ${data['text']}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Chat: ${data['username']}: ${data['text']}')),
          );
        } else if (data['type'] == 'gameOver') {
          String winner = '';
          if (data['winner'] != null) {
            winner = data['winner'] == widget.playerColor ? 'You won!' : '${widget.opponent} won!';
          } else {
            winner = 'The game was a draw.';
          }
          setState(() {
            gameState = 'Game Over! $winner Reason: ${data['status']}';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Game Over! $winner Reason: ${data['status']}')),
          );
          // Potentially show a dialog and navigate back
        }
      } catch (e) {
        print('Error parsing game message: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing game update.')),
        );
      }
    }, onError: (err) {
      print('Game WebSocket error: $err');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Game connection error: ${err.toString()}')),
      );
    }, onDone: () {
      print('Game WebSocket closed');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Game disconnected.')),
      );
    });
  }

  @override
  void dispose() {
    gameChannel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Game vs ${widget.opponent}')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Game ID: ${widget.gameId}',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                'Opponent: ${widget.opponent}',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (widget.playerColor != null)
                Text(
                  'Your color: ${widget.playerColor!.toUpperCase()}',
                  style: Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 30),
              Card(
                elevation: 4,
                margin: const EdgeInsets.all(8),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    gameState,
                    style: const TextStyle(fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}