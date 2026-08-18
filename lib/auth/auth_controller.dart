import 'package:flutter/foundation.dart';

import 'auth_api.dart';
import 'auth_models.dart';
import 'auth_store.dart';

enum AuthStatus { bootstrapping, signedOut, signedIn }

class AuthController extends ChangeNotifier {
  AuthController._();
  static final AuthController instance = AuthController._();

  final AuthApi _api = AuthApi();
  final AuthStore _store = AuthStore();

  AuthStatus status = AuthStatus.bootstrapping;
  AuthUser? user;
  AuthTokens? _tokens;
  String? lastError;

  bool get isSignedIn => status == AuthStatus.signedIn && user != null;

  Future<void> bootstrap() async {
    status = AuthStatus.bootstrapping;
    lastError = null;
    notifyListeners();

    final saved = await _store.load();
    if (saved == null) {
      status = AuthStatus.signedOut;
      user = null;
      _tokens = null;
      notifyListeners();
      return;
    }

    _tokens = saved.tokens;
    user = saved.user;

    try {
      // Обновляем access и профиль; при сбое сети оставляем кэш сессии.
      final refreshed = await _api.refresh(saved.tokens.refreshToken);
      final me = await _api.me(refreshed.accessToken);
      _tokens = refreshed;
      user = me;
      await _store.save(refreshed, me);
      status = AuthStatus.signedIn;
    } on AuthApiException catch (e) {
      if (e.statusCode == 401) {
        await _clearLocal();
        status = AuthStatus.signedOut;
      } else {
        // Офлайн / временная ошибка — пускаем по кэшу.
        status = AuthStatus.signedIn;
      }
    } catch (_) {
      status = AuthStatus.signedIn;
    }
    notifyListeners();
  }

  Future<bool> login({required String login, required String password}) async {
    lastError = null;
    notifyListeners();
    try {
      final tokens = await _api.login(login: login, password: password);
      final me = await _api.me(tokens.accessToken);
      _tokens = tokens;
      user = me;
      await _store.save(tokens, me);
      status = AuthStatus.signedIn;
      notifyListeners();
      return true;
    } on AuthApiException catch (e) {
      lastError = e.message;
      notifyListeners();
      return false;
    } catch (e) {
      lastError = 'Нет связи с сервером';
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _clearLocal();
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<void> _clearLocal() async {
    await _store.clear();
    _tokens = null;
    user = null;
    lastError = null;
  }

  /// На будущее: заголовок Authorization для облачных запросов.
  String? get accessToken => _tokens?.accessToken;
}
