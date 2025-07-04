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
            Text(
              'Welcome to Lichess Client',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontSize: 24, // You can adjust this size as needed
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 40),
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