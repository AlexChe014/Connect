import 'package:flutter/cupertino.dart';

import '../config/api_config.dart';
import '../config/branding.dart';
import '../services/auth_service.dart';
import '../services/branding_service.dart';
import '../services/location_gate_service.dart';
import '../services/notification_preferences_service.dart';
import '../services/push_notification_service.dart';
import '../utils/app_feedback.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _backendController = TextEditingController();
  final _backendFocus = FocusNode();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _backendController.text = ApiConfig.customBackendHost ?? '';
    _backendFocus.addListener(_onBackendFocusChange);
    BrandingService.instance.refresh();
  }

  @override
  void dispose() {
    _backendFocus
      ..removeListener(_onBackendFocusChange)
      ..dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _backendController.dispose();
    super.dispose();
  }

  void _onBackendFocusChange() {
    if (!_backendFocus.hasFocus) {
      _normalizeBackendField();
    }
  }

  String? _normalizeBackendField() {
    final raw = _backendController.text.trim();
    if (raw.isEmpty) {
      BrandingService.instance.refresh();
      return '';
    }
    final normalized = ApiConfig.normalizeBackendHost(raw);
    if (normalized == null) return null;
    if (normalized != _backendController.text) {
      _backendController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }
    BrandingService.instance.refresh(host: normalized);
    return normalized;
  }

  Future<void> _showAlert(String message, {String title = 'Ошибка'}) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Ок'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final backend = _normalizeBackendField() ?? _backendController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = 'Введите корректный email');
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Введите пароль');
      return;
    }
    if (backend.isNotEmpty && !ApiConfig.isBackendHostValid(backend)) {
      setState(() {
        _errorMessage =
            'Некорректный адрес бэкенда. Пример: https://connect.xondev.ru';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      await ApiConfig.setBackendHost(backend.isEmpty ? null : backend);
      await AuthService.instance.login(email, password);
      await BrandingService.instance.refresh();

      final location = await LocationGateService.instance.verifyForEmail(email);
      if (!location.allowed) {
        await AuthService.instance.logout();
        if (!mounted) return;
        setState(() {
          _errorMessage =
              location.message ?? 'Не удалось подтвердить геопозицию.';
          _isLoading = false;
        });
        await _showAlert(
          location.message ?? 'Не удалось подтвердить геопозицию.',
          title: 'Геолокация',
        );
        return;
      }

      await PushNotificationService.instance.registerAfterLogin();
      await NotificationPreferencesService.instance.syncAll();
      if (mounted) {
        Navigator.of(context).pushReplacementNamed(
          '/home',
          arguments: {'initialIndex': 3},
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = AppFeedback.messageOf(
            e,
            fallback: 'Произошла ошибка. Попробуйте снова.',
          );
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: '.SF Pro Text',
          decoration: TextDecoration.none,
          color: CupertinoColors.label.resolveFrom(context),
          fontSize: 16,
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxFormWidth =
                  constraints.maxWidth >= 700 ? 480.0 : constraints.maxWidth;

              return Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxFormWidth,
                      minHeight: (constraints.maxHeight - 48)
                          .clamp(0.0, double.infinity),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const BrandingLoginLogo(height: 96),
                        const SizedBox(height: 24),
                        const Text(
                          'Connect',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Корпоративный сервис для сотрудников компании',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: CupertinoColors.secondaryLabel
                                .resolveFrom(context),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: CupertinoColors
                                .secondarySystemGroupedBackground
                                .resolveFrom(context),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                CupertinoIcons.info_circle,
                                color: CupertinoColors.activeBlue
                                    .resolveFrom(context),
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Приложение предназначено только для сотрудников компании. '
                                  'Вход выполняется по корпоративной учётной записи. '
                                  'Регистрация для внешних пользователей недоступна.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    color: CupertinoColors.secondaryLabel
                                        .resolveFrom(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        CupertinoListSection.insetGrouped(
                          margin: EdgeInsets.zero,
                          children: [
                            _AuthField(
                              controller: _backendController,
                              focusNode: _backendFocus,
                              placeholder: 'Адрес сервера',
                              icon: CupertinoIcons.link,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              onEditingComplete: _normalizeBackendField,
                            ),
                            _AuthField(
                              controller: _emailController,
                              placeholder: 'Email',
                              icon: CupertinoIcons.mail,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                            ),
                            _AuthField(
                              controller: _passwordController,
                              placeholder: 'Пароль',
                              icon: CupertinoIcons.lock,
                              obscureText: _obscurePassword,
                              suffix: CupertinoButton(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                child: Icon(
                                  _obscurePassword
                                      ? CupertinoIcons.eye
                                      : CupertinoIcons.eye_slash,
                                  size: 20,
                                  color: CupertinoColors.secondaryLabel
                                      .resolveFrom(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: CupertinoColors.systemRed
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  CupertinoIcons.exclamationmark_triangle,
                                  color: CupertinoColors.systemRed,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      color: CupertinoColors.systemRed,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: CupertinoButton.filled(
                            onPressed: _isLoading ? null : _submit,
                            child: _isLoading
                                ? const CupertinoActivityIndicator(
                                    color: CupertinoColors.white,
                                  )
                                : const Text('Войти'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Поле авторизации в едином apple-style: иконка слева, плейсхолдер вместо
/// лейбла, без Material-рамки — вписывается в [CupertinoListSection.insetGrouped].
class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.placeholder,
    required this.icon,
    this.focusNode,
    this.keyboardType,
    this.autocorrect = true,
    this.obscureText = false,
    this.onEditingComplete,
    this.suffix,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String placeholder;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool autocorrect;
  final bool obscureText;
  final VoidCallback? onEditingComplete;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      focusNode: focusNode,
      placeholder: placeholder,
      keyboardType: keyboardType,
      autocorrect: autocorrect,
      obscureText: obscureText,
      onEditingComplete: onEditingComplete,
      decoration: const BoxDecoration(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      prefix: Padding(
        padding: const EdgeInsets.only(left: 4, right: 8),
        child: Icon(
          icon,
          size: 20,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
      suffix: suffix == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: 4),
              child: suffix,
            ),
    );
  }
}
