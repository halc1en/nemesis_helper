import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:nemesis_helper/l10n.dart';
import 'package:nemesis_helper/model/account.dart';
import 'package:nemesis_helper/model/json_data.dart';
import 'package:nemesis_helper/ui/ui_widget.dart';
import 'package:nemesis_helper/ui/utils.dart';

@immutable
class UIWidgetAuthenticate implements UIWidget {
  final String description;
  final UIWidget? child;

  const UIWidgetAuthenticate._({
    required this.description,
    required this.child,
  });

  /// Create a new [UIWidget] instance
  factory UIWidgetAuthenticate.fromJson(
      Map<String, dynamic> json, ReferenceData reference) {
    final childJson = json['widget'] as Map<String, dynamic>?;
    return UIWidgetAuthenticate._(
        description: json['description'] as String,
        child: (childJson == null)
            ? null
            : UIWidget.fromJson(childJson, reference));
  }

  @override
  Widget uiWidgetBuild(BuildContext context, bool insideScrollable) {
    // This will update upon login/logout
    return Consumer<Authentication>(builder: (context, auth, _) {
      if (Authentication.isSignedIn()) {
        return this.child?.uiWidgetBuild(context, insideScrollable) ??
            const SizedBox.shrink();
      }

      final children = [
        ListTile(
          title: Text(this.description,
              textAlign: TextAlign.start,
              style: Theme.of(context).textTheme.bodyMedium),
        ),
        const HDivider(),
        const LoginOtpButton(),
      ];

      return (insideScrollable)
          ? Column(children: children)
          : ListView(children: children);
    });
  }
}

class LoginOtpButton extends StatelessWidget {
  const LoginOtpButton({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () {
            showDialog<void>(
              context: context,
              builder: (context) => const _LoginOtpDialog(),
            );
          },
          icon: const Icon(Icons.login),
          label: Text(context.l10n.loginWithEmail),
        ),
      ),
    );
  }
}

class _LoginOtpDialog extends StatefulWidget {
  const _LoginOtpDialog({super.key});

  @override
  State<_LoginOtpDialog> createState() => _LoginOtpDialogState();
}

class _LoginOtpDialogState extends State<_LoginOtpDialog> {
  bool otpVerification = false;
  final emailController = TextEditingController();

  @override
  void dispose() {
    this.emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return (!this.otpVerification)
        ? _OtpEmailDialog(
            emailController: this.emailController,
            onOtpSent: () {
              setState(() => this.otpVerification = true);
            })
        : _OtpVerifyDialog(email: this.emailController.text);
  }
}

class _OtpEmailDialog extends StatefulWidget {
  const _OtpEmailDialog(
      {super.key, required this.onOtpSent, required this.emailController});

  final TextEditingController emailController;
  final void Function() onOtpSent;

  @override
  State<_OtpEmailDialog> createState() => _OtpEmailDialogState();
}

class _OtpEmailDialogState extends State<_OtpEmailDialog> {
  Future<void>? _signingIn;

  @override
  Widget build(BuildContext context) {
    return Consumer<Authentication>(builder: (context, auth, child) {
      return FutureBuilder(
        future: this._signingIn,
        builder: (context, snapshot) {
          return AlertDialog(
            title: Text(context.l10n.loginWithEmail),
            content: TextFormField(
              autofocus: true,
              enabled: snapshot.connectionState == ConnectionState.none,
              controller: this.widget.emailController,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: context.l10n.email),
              // Make sure validation updates 'OK' visibility
              onChanged: (String value) => setState(() {}),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) {
                if (value == null) return null;
                return EmailValidator.validate(value)
                    ? null
                    : context.l10n.invalidEmail;
              },
              onFieldSubmitted: (String email) {
                if (EmailValidator.validate(this.widget.emailController.text)) {
                  _signIn(context, auth);
                }
              },
            ),
            actions: <Widget>[
              TextButton(
                onPressed:
                    !EmailValidator.validate(this.widget.emailController.text)
                        ? null
                        : () => _signIn(context, auth),
                child: Text(context.l10n.login, textAlign: TextAlign.end),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.cancel, textAlign: TextAlign.end),
              ),
            ],
          );
        },
      );
    });
  }

  Future<void> _signIn(BuildContext context, Authentication auth) async {
    try {
      final result = auth.signInWithOtp(this.widget.emailController.text);
      setState(() {
        this._signingIn = result;
      });
      await result;
      widget.onOtpSent();
    } catch (e) {
      setState(() {
        this._signingIn = null;
      });
      if (context.mounted) {
        showSnackBarError(
            context, "${context.l10n.otpEmailFail}: ${e.toString()}");
        Navigator.of(context).pop();
      }
    }
  }
}

class _OtpVerifyDialog extends StatefulWidget {
  const _OtpVerifyDialog({super.key, required this.email});

  final String email;

  @override
  State<_OtpVerifyDialog> createState() => _OtpVerifyDialogState();
}

class _OtpVerifyDialogState extends State<_OtpVerifyDialog> {
  Future<void>? _verifying;
  final codeController = TextEditingController();

  @override
  void dispose() {
    codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<Authentication>(builder: (context, auth, child) {
      return FutureBuilder(
        future: this._verifying,
        builder: (context, snapshot) {
          return AlertDialog(
            title: Text(context.l10n.loginWithEmail),
            content: TextFormField(
              autofocus: true,
              enabled: snapshot.connectionState == ConnectionState.none,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 6,
              maxLines: 1,
              controller: this.codeController,
              decoration: InputDecoration(labelText: context.l10n.sixDigitCode),
              onChanged: (String code) {
                if (_validCode(code)) _verifyOTP(context, auth, token: code);
              },
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.l10n.cancel, textAlign: TextAlign.end),
              ),
            ],
          );
        },
      );
    });
  }

  bool _validCode(String code) {
    return code.length == 6 && int.tryParse(code) != null;
  }

  Future<void> _verifyOTP(BuildContext context, Authentication auth,
      {required String token}) async {
    try {
      final result = auth.verifyOTP(email: widget.email, token: token);
      setState(() {
        this._verifying = result;
      });
      await result;
    } catch (e) {
      setState(() {
        this._verifying = null;
      });
      if (context.mounted) {
        showSnackBarError(
            context, "${context.l10n.otpVerifyFail}: ${e.toString()}");
      }
    }
    if (context.mounted) Navigator.of(context).pop();
  }
}
