import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

class WelcomeScreen extends StatefulWidget {
  @override
  _WelcomeScreenState createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final AuthService _authService = AuthService();
  bool isLoading = false;

  Future<void> _handleLogin() async {
    setState(() => isLoading = true);

    try {
      final userInfo = await _authService.login();
      if (userInfo != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(
              username: userInfo['username'],
              blitzRating: userInfo['perfs']?['blitz']?['rating'],
              accessToken: _authService.accessToken!,
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: ${e.toString()}')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Add logo here
            Image.asset(
              'lib/assets/logo.png', // Replace with your image path
              height:70,       // Adjust size as needed
            ),
            SizedBox(height: 5),

            Text(
              'ZChess',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 100),

            isLoading
                ? CircularProgressIndicator()
                : ElevatedButton(
              child: Text('Login with Lichess'),
              onPressed: _handleLogin,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

}