import 'package:flutter/material.dart';
import 'game_screen.dart';

class HomeScreen extends StatelessWidget {
  final String username;
  final int? blitzRating;
  final String accessToken;

  const HomeScreen({
    required this.username,
    required this.blitzRating,
    required this.accessToken,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Welcome, $username!')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Blitz Rating: ${blitzRating ?? 'N/A'}',
                style: TextStyle(fontSize: 24)),
            SizedBox(height: 40),
            ElevatedButton(
              child: Text('Start New Game'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GameScreen(
                      accessToken: accessToken,
                      username: username,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}