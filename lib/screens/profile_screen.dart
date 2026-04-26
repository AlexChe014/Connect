import 'package:flutter/material.dart';

import '../services/api_repository.dart';
import '../services/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final stored = await AuthService.instance.getStoredUser();
      final api = await ApiRepository.instance.getProfile();

      if (mounted) {
        setState(() {
          _profile = api ?? stored ?? {};
          _isLoading = false;
        });
      }
    } catch (_) {
      final stored = await AuthService.instance.getStoredUser();

      if (mounted) {
        setState(() {
          _profile = stored ?? {};
          _isLoading = false;
        });
      }
    }
  }

  /// Две буквы (фамилия + имя) или первая буква e-mail, без RangeError на пустых полях.
  String get _initials {
    final p = _profile;
    if (p == null) return '?';
    final parts = <String>[];
    for (final key in ['surname', 'name']) {
      final t = (p[key] ?? '').toString().trim();
      if (t.isNotEmpty) parts.add(t.substring(0, 1));
    }
    if (parts.isEmpty) {
      final e = (p['email'] ?? '').toString().trim();
      if (e.isNotEmpty) return e[0].toUpperCase();
      return '?';
    }
    return parts.take(2).join().toUpperCase();
  }

  String get _displayName {
    final p = _profile;
    if (p == null) return 'Пользователь';
    final s = (p['surname'] ?? '').toString().trim();
    final n = (p['name'] ?? '').toString().trim();
    if (s.isNotEmpty && n.isNotEmpty) return '$s $n';
    if (n.isNotEmpty) return n;
    if (s.isNotEmpty) return s;
    final e = (p['email'] ?? '').toString().trim();
    if (e.isNotEmpty) return e;
    return 'Пользователь';
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти'),
        content: const Text('Вы уверены, что хотите выйти из аккаунта?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await AuthService.instance.logout();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        centerTitle: true,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
            heightFactor: 1,
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            _initials,
                            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                          ),
                        ),
                                              const SizedBox(height: 20),
                        Text(
                          _displayName,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (_profile?['position'] != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _profile!['position'].toString(),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                          ),
                        ],
                        const SizedBox(height: 48),
                        OutlinedButton.icon(
                          onPressed: _logout,
                          icon: const Icon(Icons.logout),
                          label: const Text('Выйти из аккаунта'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Theme.of(context).colorScheme.error,
                            side: BorderSide(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                      ],
                    ),
              ),
          ),
    );
  }
}
