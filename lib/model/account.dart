import 'package:flutter/material.dart';
import 'package:retry/retry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Store cached account info locally
class Account {
  Account(this.notifyListeners) {
    if (Authentication.isSignedIn()) _updateCachedInfo();
  }

  final VoidCallback notifyListeners;
  Future<String>? name;
  Future<List<String>>? friends;

  static Future<List<String>> findFriendsByPrefix(String prefix) async {
    try {
      final List<dynamic> response = await Supabase.instance.client
          .rpc<List<dynamic>>('find_friends_by_prefix',
              params: {'start': prefix});
      return response
          .map((row) => (row as Map<String, dynamic>)['name']! as String)
          .toList();
    } catch (e) {
      return Future.value([]);
    }
  }

  Future<void> updateName(String newName) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;

    if (user == null) throw ('Updating user name while user is disconnected');

    await client.from('profiles').update({'name': newName}).eq('uid', user.id);
    this.name = Future.value(newName);
  }

  Future<void> addFriend(String friend) async {
    final name = await this.name;
    if (name == null) {
      throw ('Adding friend while connection is not initialized');
    }

    final List<String> friends;
    try {
      await Supabase.instance.client
          .from('friends')
          .insert({'name1': name, 'name2': friend});
      friends = await _fetchFriends(name);
    } catch (e) {
      print("Count not add friend $friend: $e");
      return;
    }

    this.friends = Future.value(friends);
    this.notifyListeners();
  }

  Future<void> removeFriend(String friend) async {
    final name = await this.name;
    if (name == null) {
      throw ('Removing friend while connection is not initialized');
    }

    final List<String> friends;
    try {
      await Supabase.instance.client
          .from('friends')
          .delete()
          .eq('name1', name)
          .eq('name2', friend);
      friends = await _fetchFriends(name);
    } catch (e) {
      print("Count not remove friend $friend: $e");
      return;
    }

    this.friends = Future.value(friends);
    this.notifyListeners();
  }

  Future<List<String>> _fetchFriends(String? name) async {
    if (name == null) return [];

    return Supabase.instance.client
        .from('friends')
        .select('name1, name2')
        .or('name1.eq.$name,name2.eq.$name')
        .then((rows) => rows.map((row) {
              final name1 = row['name1'] as String;
              final name2 = row['name2'] as String;
              return name1 != name ? name1 : name2;
            }).toList());
  }

  Future<void> _updateCachedInfo() async {
    final name = await retry(() => Supabase.instance.client
        .from('profiles')
        .select('name')
        .single()
        .then((row) => row['name'] as String));
    final friends = await retry(() => this._fetchFriends(name));

    this.name = Future.value(name);
    this.friends = Future.value(friends);
    notifyListeners();
  }

  void _forgetCachedInfo() {
    this.name = null;
    this.friends = null;
    notifyListeners();
  }
}

/// A simple helper for authentication
class Authentication extends ChangeNotifier {
  Authentication() {
    this.account = Account(() => notifyListeners());
  }

  late Account account;

  static bool isSignedIn() =>
      Supabase.instance.client.auth.currentSession != null;

  /// Send one-time password to [email]
  Future<void> signInWithOtp(String email) async {
    await Supabase.instance.client.auth.signInWithOtp(email: email);
  }

  /// Verify one-time password [token] sent to [email]
  Future<AuthResponse> verifyOTP(
      {required String email, required String token}) async {
    final result = await Supabase.instance.client.auth
        .verifyOTP(email: email, token: token, type: OtpType.email);
    if (isSignedIn()) await this.account._updateCachedInfo();
    return result;
  }

  /// Sign out current user
  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
    this.account._forgetCachedInfo();
  }

  /// Sign out current user and delete account with all associated data
  Future<void> deleteUserAndSignOut() async {
    await Supabase.instance.client.rpc<void>('delete_current_user');
    await Supabase.instance.client.auth.signOut();
    this.account._forgetCachedInfo();
  }
}
