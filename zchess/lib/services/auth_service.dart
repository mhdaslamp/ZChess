import 'dart:convert';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:http/http.dart' as http;

class AuthService {
  static const String _clientId = 'lichess.org';
  static const String _redirectUri = 'com.example.zchess://oauthredirect';
  static const String _apiUrl = 'https://lichess.org/api';

  final FlutterAppAuth _appAuth = FlutterAppAuth();
  String? accessToken;

  Future<Map<String, dynamic>> login() async {
    final result = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        _clientId,
        _redirectUri,
        serviceConfiguration: AuthorizationServiceConfiguration(
          authorizationEndpoint: 'https://lichess.org/oauth',
          tokenEndpoint: 'https://lichess.org/api/token',
        ),
        scopes: ['preference:read', 'challenge:write', 'board:play'],
      ),
    );

    if (result?.accessToken != null) {
      accessToken = result!.accessToken;
      return await _fetchUserInfo();
    }
    throw Exception('Login failed - no access token received');
  }

  Future<Map<String, dynamic>> _fetchUserInfo() async {
    final response = await http.get(
      Uri.parse('$_apiUrl/account'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    }
    throw Exception('Failed to fetch user info: ${response.statusCode}');
  }
}