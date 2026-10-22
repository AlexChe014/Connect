import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../config/app_theme.dart';
import '../models/surveys/survey_form.dart';
import '../repositories/surveys_repository.dart';
import '../services/survey_pending_service.dart';
import '../utils/app_feedback.dart';
import '../widgets/app_empty_state.dart';
import '../widgets/app_glass.dart';
import '../widgets/booking_glass_form.dart';

/// Прохождение опроса по токену получателя (`/surveys/public/{token}`).
class SurveyFormScreen extends StatefulWidget {
  const SurveyFormScreen({super.key, required this.token, this.title});

  final String token;

  /// Заголовок из списка приглашений — показывается, пока грузится форма.
  final String? title;

  @override
  State<SurveyFormScreen> createState() => _SurveyFormScreenState();
}

class _SurveyFormScreenState extends State<SurveyFormScreen> {
  SurveyForm? _form;
  bool _isLoading = true;
  String? _loadError;

  /// Ответы по `question_id`: `String` (text/textarea — в контроллерах),
  /// `Object` варианта (single), `Set<Object>` (multi), `int` (rating/nps).
  final Map<int, Object> _answers = {};
  final Map<int, TextEditingController> _textControllers = {};
  final Map<int, GlobalKey> _questionKeys = {};
  final Map<int, String> _fieldErrors = {};

  bool _startSent = false;
  bool _isSubmitting = false;
  String? _submitError;

  /// Не `null` — ответы отправлены, показываем экран благодарности.
  String? _successMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final form = await SurveysRepository.instance.getForm(widget.token);
      if (!mounted) return;
      for (final c in _textControllers.values) {
        c.dispose();
      }
      _textControllers.clear();
      _questionKeys.clear();
      for (final q in form.questions) {
        _questionKeys[q.id] = GlobalKey();
        if (q.type != SurveyQuestionType.single &&
            q.type != SurveyQuestionType.multi &&
            q.type != SurveyQuestionType.rating) {
          // text/textarea — ответ, nps — комментарий.
          _textControllers[q.id] = TextEditingController()
            ..addListener(() => _onTextChanged(q.id));
        }
      }
      if (form.alreadyCompleted) {
        SurveyPendingService.instance.markCompleted(widget.token);
      }
      setState(() {
        _form = form;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = AppFeedback.messageOf(
          e,
          fallback: 'Не удалось загрузить опрос',
        );
      });
    }
  }

  /// `start` — событие воронки «начал прохождение»: шлём один раз,
  /// при первом ответе, ошибки не мешают проходить опрос.
  void _markStarted() {
    if (_startSent) return;
    _startSent = true;
    unawaited(
      SurveysRepository.instance.start(widget.token).catchError((_) {}),
    );
  }

  void _onTextChanged(int questionId) {
    if (_textControllers[questionId]!.text.trim().isNotEmpty) _markStarted();
    if (_fieldErrors.containsKey(questionId)) {
      setState(() => _fieldErrors.remove(questionId));
    }
  }

  void _setAnswer(int questionId, Object? value) {
    _markStarted();
    setState(() {
      if (value == null) {
        _answers.remove(questionId);
      } else {
        _answers[questionId] = value;
      }
      _fieldErrors.remove(questionId);
    });
  }

  String _text(int questionId) =>
      _textControllers[questionId]?.text.trim() ?? '';

  String? _validate(SurveyQuestion q) {
    switch (q.type) {
      case SurveyQuestionType.multi:
        final selected = _answers[q.id] as Set<Object>?;
        if (q.isRequired && (selected == null || selected.isEmpty)) {
          return 'Выберите хотя бы один вариант';
        }
      case SurveyQuestionType.single:
      case SurveyQuestionType.rating:
        if (q.isRequired && _answers[q.id] == null) {
          return 'Выберите ответ';
        }
      case SurveyQuestionType.nps:
        final score = _answers[q.id] as int?;
        if (score == null) {
          return q.isRequired ? 'Выберите оценку' : null;
        }
        if (q.requireCommentForDetractors &&
            SurveyQuestion.isDetractorScore(score) &&
            _text(q.id).isEmpty) {
          return 'Расскажите, что можно улучшить';
        }
      default:
        if (q.isRequired && _text(q.id).isEmpty) {
          return 'Заполните поле';
        }
    }
    return null;
  }

  Object? _answerValue(SurveyQuestion q) {
    switch (q.type) {
      case SurveyQuestionType.multi:
        final selected = _answers[q.id] as Set<Object>?;
        if (selected == null || selected.isEmpty) return null;
        // Порядок вариантов — как в опросе, а не как кликали.
        return [
          for (final o in q.options)
            if (selected.contains(o.value)) o.value,
        ];
      case SurveyQuestionType.single:
      case SurveyQuestionType.rating:
        return _answers[q.id];
      case SurveyQuestionType.nps:
        final score = _answers[q.id] as int?;
        if (score == null) return null;
        final comment = _text(q.id);
        return comment.isEmpty ? score : {'score': score, 'comment': comment};
      default:
        final text = _text(q.id);
        return text.isEmpty ? null : text;
    }
  }

  Future<void> _submit() async {
    final form = _form;
    if (form == null || _isSubmitting) return;
    FocusManager.instance.primaryFocus?.unfocus();

    final errors = <int, String>{};
    for (final q in form.questions) {
      final error = _validate(q);
      if (error != null) errors[q.id] = error;
    }
    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(errors);
      _submitError = errors.isEmpty ? null : 'Ответьте на отмеченные вопросы';
    });
    if (errors.isNotEmpty) {
      final firstId = form.questions
          .firstWhere((q) => errors.containsKey(q.id))
          .id;
      final ctx = _questionKeys[firstId]?.currentContext;
      if (ctx != null) {
        unawaited(
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 300),
            alignment: 0.1,
          ),
        );
      }
      return;
    }

    final answers = <SurveyAnswer>[
      for (final q in form.questions)
        if (_answerValue(q) case final value?)
          SurveyAnswer(questionId: q.id, value: value),
    ];

    _markStarted();
    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });
    try {
      final message = await SurveysRepository.instance.submit(
        widget.token,
        answers,
      );
      if (!mounted) return;
      SurveyPendingService.instance.markCompleted(widget.token);
      unawaited(SurveyPendingService.instance.refreshQuietly());
      setState(() {
        _isSubmitting = false;
        _successMessage =
            message ??
            form.survey.successMessage ??
            'Спасибо! Ваши ответы отправлены.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitError = AppFeedback.messageOf(
          e,
          fallback: 'Не удалось отправить ответы',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _form?.survey.title ?? widget.title ?? '';
    return BookingGlassScaffold(
      title: title.isEmpty ? 'Опрос' : title,
      children: _buildBody(),
    );
  }

  List<Widget> _buildBody() {
    if (_isLoading) {
      return const [
        SizedBox(height: 160),
        Center(child: CupertinoActivityIndicator(radius: 14)),
      ];
    }

    final form = _form;
    if (form == null) {
      return [
        const SizedBox(height: 80),
        AppEmptyState(
          icon: CupertinoIcons.exclamationmark_triangle,
          message: _loadError ?? 'Не удалось загрузить опрос',
          onRetry: _load,
        ),
      ];
    }

    final successMessage = _successMessage;
    if (successMessage != null) {
      return [
        _SurveyResultView(
          icon: CupertinoIcons.checkmark_seal_fill,
          color: CupertinoColors.systemGreen,
          title: 'Ответы отправлены',
          message: successMessage,
        ),
      ];
    }
    if (form.alreadyCompleted) {
      return const [
        _SurveyResultView(
          icon: CupertinoIcons.checkmark_seal_fill,
          color: CupertinoColors.systemGreen,
          title: 'Опрос пройден',
          message: 'Вы уже ответили на этот опрос. Спасибо за участие!',
        ),
      ];
    }
    if (!form.isOpen) {
      return const [
        _SurveyResultView(
          icon: CupertinoIcons.lock_fill,
          color: CupertinoColors.systemGrey,
          title: 'Опрос закрыт',
          message: 'Приём ответов по этому опросу завершён.',
        ),
      ];
    }

    final survey = form.survey;
    final closesAt = form.closesAt;
    final questionCount = form.questions.length;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (survey.title.isNotEmpty)
              Text(
                survey.title,
                style: const TextStyle(
                  fontSize: 26,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
            if (survey.description != null) ...[
              const SizedBox(height: 8),
              Text(
                survey.description!,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: CupertinoIcons.list_bullet,
                  label: _questionsLabel(questionCount),
                ),
                if (survey.isAnonymous)
                  const _InfoChip(
                    icon: CupertinoIcons.eye_slash_fill,
                    label: 'Анонимно',
                  ),
                if (closesAt != null)
                  _InfoChip(
                    icon: CupertinoIcons.clock_fill,
                    label:
                        'До ${DateFormat('d MMMM, HH:mm', 'ru_RU').format(closesAt)}',
                  ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      for (var i = 0; i < questionCount; i++)
        Padding(
          key: _questionKeys[form.questions[i].id],
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _QuestionCard(
            index: i + 1,
            question: form.questions[i],
            error: _fieldErrors[form.questions[i].id],
            child: _buildInput(form.questions[i]),
          ),
        ),
      if (_submitError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text(
            _submitError!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: CupertinoColors.systemRed.resolveFrom(context),
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: AppPrimaryButton(
          label: survey.submitButtonText ?? 'Отправить',
          isLoading: _isSubmitting,
          onPressed: _submit,
        ),
      ),
    ];
  }

  static String _questionsLabel(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    final word = mod10 == 1 && mod100 != 11
        ? 'вопрос'
        : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
        ? 'вопроса'
        : 'вопросов';
    return '$count $word';
  }

  Widget _buildInput(SurveyQuestion q) {
    switch (q.type) {
      case SurveyQuestionType.single:
        return _OptionsInput(
          options: q.options,
          multiple: false,
          selected: {?_answers[q.id]},
          onToggle: (value) =>
              _setAnswer(q.id, _answers[q.id] == value ? null : value),
        );
      case SurveyQuestionType.multi:
        final selected = (_answers[q.id] as Set<Object>?) ?? const <Object>{};
        return _OptionsInput(
          options: q.options,
          multiple: true,
          selected: selected,
          onToggle: (value) {
            final next = {...selected};
            if (!next.remove(value)) next.add(value);
            _setAnswer(q.id, next.isEmpty ? null : next);
          },
        );
      case SurveyQuestionType.rating:
        return _RatingInput(
          max: q.ratingMax,
          value: _answers[q.id] as int?,
          onChanged: (v) => _setAnswer(q.id, v),
        );
      case SurveyQuestionType.nps:
        final score = _answers[q.id] as int?;
        final needsComment =
            score != null &&
            q.requireCommentForDetractors &&
            SurveyQuestion.isDetractorScore(score);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _NpsInput(value: score, onChanged: (v) => _setAnswer(q.id, v)),
            if (score != null) ...[
              const SizedBox(height: 12),
              _TextInput(
                controller: _textControllers[q.id]!,
                placeholder: needsComment
                    ? 'Что нам стоит улучшить? (обязательно)'
                    : 'Комментарий (необязательно)',
                maxLines: 3,
              ),
            ],
          ],
        );
      case SurveyQuestionType.textarea:
        return _TextInput(
          controller: _textControllers[q.id]!,
          placeholder: 'Ваш ответ',
          maxLines: 5,
        );
      default:
        return _TextInput(
          controller: _textControllers[q.id]!,
          placeholder: 'Ваш ответ',
          maxLines: 1,
        );
    }
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.index,
    required this.question,
    required this.child,
    this.error,
  });

  final int index;
  final SurveyQuestion question;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null;
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final red = CupertinoColors.systemRed.resolveFrom(context);
    return Container(
      // Красная кромка поверх стекла — сразу видно, какой вопрос пропущен.
      foregroundDecoration: hasError
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: red, width: 1.5),
            )
          : null,
      child: AppFlatGlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(
                      alpha: isDark ? 0.28 : 0.14,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: question.label),
                          if (question.isRequired)
                            TextSpan(
                              text: ' *',
                              style: TextStyle(color: red),
                            ),
                        ],
                      ),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (question.description != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 36),
                child: Text(
                  question.description!,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            child,
            if (hasError) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    CupertinoIcons.exclamationmark_circle_fill,
                    size: 15,
                    color: red,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      error!,
                      style: TextStyle(fontSize: 13, color: red),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({
    required this.controller,
    required this.placeholder,
    required this.maxLines,
  });

  final TextEditingController controller;
  final String placeholder;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      minLines: maxLines > 1 ? 2 : 1,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.sentences,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemFill.resolveFrom(context),
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}

class _OptionsInput extends StatelessWidget {
  const _OptionsInput({
    required this.options,
    required this.multiple,
    required this.selected,
    required this.onToggle,
  });

  final List<SurveyOption> options;
  final bool multiple;
  final Set<Object> selected;
  final ValueChanged<Object> onToggle;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return Text(
        'Нет вариантов ответа',
        style: TextStyle(
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      );
    }
    return Column(
      children: [
        for (final option in options)
          // Варианты — отдельные «плашки», выбранная подсвечена синим.
          _OptionRow(
            label: option.label,
            multiple: multiple,
            selected: selected.contains(option.value),
            onTap: () => onToggle(option.value),
          ),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.multiple,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool multiple;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = multiple
        ? (selected
              ? CupertinoIcons.checkmark_square_fill
              : CupertinoIcons.square)
        : (selected
              ? CupertinoIcons.checkmark_circle_fill
              : CupertinoIcons.circle);
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    return Semantics(
      checked: selected,
      button: true,
      label: label,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.primary.withValues(alpha: isDark ? 0.24 : 0.10)
                  : CupertinoColors.tertiarySystemFill.resolveFrom(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.6)
                    : const Color(0x00000000),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected
                      ? AppColors.primary
                      : CupertinoColors.systemGrey2.resolveFrom(context),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RatingInput extends StatelessWidget {
  const _RatingInput({
    required this.max,
    required this.value,
    required this.onChanged,
  });

  final int max;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = value ?? 0;
    return Wrap(
      spacing: 4,
      children: [
        for (var i = 1; i <= max; i++)
          Semantics(
            button: true,
            selected: i == value,
            label: 'Оценка $i из $max',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Повторный тап по выбранной звезде снимает оценку.
              onTap: () => onChanged(i == value ? null : i),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  i <= current ? CupertinoIcons.star_fill : CupertinoIcons.star,
                  size: max > 5 ? 26 : 32,
                  color: i <= current
                      ? CupertinoColors.systemYellow
                      : CupertinoColors.systemGrey3.resolveFrom(context),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _NpsInput extends StatelessWidget {
  const _NpsInput({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  static Color _colorFor(int score) {
    if (score <= 6) return CupertinoColors.systemRed;
    if (score <= 8) return CupertinoColors.systemOrange;
    return CupertinoColors.systemGreen;
  }

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (var score = 0; score <= 10; score++) ...[
              if (score > 0) const SizedBox(width: 3),
              Expanded(
                child: Semantics(
                  button: true,
                  selected: score == value,
                  label: 'Оценка $score',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(score == value ? null : score),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: score == value
                            ? _colorFor(score)
                            : CupertinoColors.tertiarySystemFill.resolveFrom(
                                context,
                              ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$score',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: score == value
                              ? CupertinoColors.white
                              : CupertinoColors.label.resolveFrom(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              'Маловероятно',
              style: TextStyle(fontSize: 12, color: secondary),
            ),
            const Spacer(),
            Text(
              'Обязательно',
              style: TextStyle(fontSize: 12, color: secondary),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = CupertinoColors.secondaryLabel.resolveFrom(context);
    return AppGlass(
      borderRadius: BorderRadius.circular(16),
      shadows: AppGlass.controlShadow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Итоговое состояние формы: отправлено / уже пройден / закрыт.
class _SurveyResultView extends StatelessWidget {
  const _SurveyResultView({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final tint = CupertinoDynamicColor.resolve(color, context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 56, 16, 0),
      child: Column(
        children: [
          // Значок в стеклянном медальоне с мягкой подложкой своего цвета.
          AppGlass(
            borderRadius: BorderRadius.circular(56),
            child: Container(
              width: 112,
              height: 112,
              alignment: Alignment.center,
              color: tint.withValues(alpha: isDark ? 0.24 : 0.14),
              child: Icon(icon, size: 56, color: tint),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.35,
                color: CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
            ),
          ),
          const SizedBox(height: 32),
          AppPrimaryButton(
            label: 'Готово',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
