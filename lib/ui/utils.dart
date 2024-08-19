import 'package:flutter/material.dart';

void showSnackBarError(BuildContext context, String error, {int seconds = 10}) {
  final snackbar = SnackBar(
    showCloseIcon: true,
    duration: Duration(seconds: seconds),
    content: Text(error),
  );
  ScaffoldMessenger.of(context).showSnackBar(snackbar);
}

class VDivider extends StatelessWidget {
  const VDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const VerticalDivider(thickness: 1.5, endIndent: 0.0, width: 1.5);
  }
}

class HDivider extends StatelessWidget {
  const HDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Divider(thickness: 1.5, endIndent: 0.0, height: 1.5);
  }
}
