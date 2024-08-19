import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localized_locales/flutter_localized_locales.dart';

import 'package:nemesis_helper/l10n.dart';
import 'package:nemesis_helper/model/account.dart';
import 'package:nemesis_helper/model/json_data.dart';
import 'package:nemesis_helper/model/settings.dart';
import 'package:nemesis_helper/ui/ui_widget_authenticate.dart';
import 'package:nemesis_helper/ui/utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SettingsDialog extends StatelessWidget {
  const SettingsDialog(
      {super.key,
      required this.supportedLanguages,
      required this.loadedModules,
      required this.ui});

  final List<String>? supportedLanguages;
  final List<Module>? loadedModules;
  final UISettings ui;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settings)),
      body: ListView(
        children: [
          Consumer<Authentication>(builder: (context, _, __) {
            return _CardWithHeader(
              header: context.l10n.account,
              children: [
                if (Authentication.isSignedIn()) ...[
                  _AccountName(textTheme),
                  const HDivider(),
                  _FriendsList(textTheme),
                  const HDivider(),
                  _SignOutButton(textTheme),
                  const HDivider(),
                  _DeleteAccountButton(textTheme),
                ] else
                  const LoginOtpButton(),
              ],
            );
          }),
          _CardWithHeader(
              header: context.l10n.modules,
              child: _ModulesConfig(textTheme, loadedModules)),
          _CardWithHeader(
            header: context.l10n.interface,
            children: [
              _LanguageConfig(textTheme, supportedLanguages),
              const HDivider(),
              _ScaleConfig(textTheme),
            ],
          ),
          if (!kReleaseMode)
            _CardWithHeader(
                header: context.l10n.debugging,
                child: _OfflineModeConfig(textTheme)),
        ],
      ),
    );
  }
}

class _CardWithHeader extends StatelessWidget {
  const _CardWithHeader(
      {required this.header, this.children, this.child, super.key})
      : assert(children == null && child != null ||
            children != null && child == null);

  final String header;
  final List<Widget>? children;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      title: Card.outlined(
        shape: const RoundedRectangleBorder().copyWith(
            side: BorderSide(color: theme.colorScheme.outlineVariant)),
        margin: const EdgeInsets.symmetric(vertical: 2),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: double.infinity),
              padding: const EdgeInsets.all(4),
              color: theme.colorScheme.onPrimary,
              alignment: Alignment.center,
              child: Text(
                this.header,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  shadows: [Shadow(color: Colors.blue.shade400, blurRadius: 2)],
                ),
              ),
            ),
            const HDivider(),
            ...this.children ?? [],
            if (this.child != null) this.child!,
          ],
        ),
      ),
    );
  }
}

class _AccountName extends StatefulWidget {
  const _AccountName(this.textTheme, {super.key});

  final TextTheme textTheme;

  @override
  State<_AccountName> createState() => _AccountNameState();
}

class _AccountNameState extends State<_AccountName> {
  final TextEditingController _editController = TextEditingController();
  bool _editing = false;

  String? _nameCheckError;

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Consumer<Authentication>(builder: (context, auth, _) {
        return FutureBuilder(
          future: auth.account.name,
          builder: (context, snapshot) {
            final name = snapshot.data;

            if (name == null) {
              return Row(
                children: [
                  Text(context.l10n.accountName,
                      style: widget.textTheme.bodyMedium),
                  const Center(child: CircularProgressIndicator()),
                ],
              );
            }

            if (!_editing) {
              _editController.text = name;
              return Row(
                children: [
                  Text(context.l10n.accountName,
                      style: widget.textTheme.bodyMedium),
                  Expanded(
                    child: Text(name, style: widget.textTheme.bodyMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () {
                      setState(() => _editing = true);
                    },
                  ),
                ],
              );
            }

            return Row(
              children: [
                Text(context.l10n.accountName,
                    style: widget.textTheme.bodyMedium),
                Expanded(
                  child: TextFormField(
                    autofocus: true,
                    keyboardType: TextInputType.name,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.singleLineFormatter
                    ],
                    maxLines: 1,
                    controller: this._editController,
                    onFieldSubmitted: (String newName) async {
                      await _updateName(context, newName, auth.account);
                    },
                    autovalidateMode: AutovalidateMode.always,
                    validator: (_) {
                      final nameCheckError = this._nameCheckError;
                      return nameCheckError == null
                          ? null
                          : context.l10n.nameTaken(nameCheckError);
                    },
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        onPressed: () async {
                          await _updateName(
                              context, _editController.text, auth.account);
                        },
                        icon: const Icon(Icons.check),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      }),
    );
  }

  Future<void> _updateName(
      BuildContext context, String newName, Account account) async {
    try {
      await account.updateName(newName);
    } catch (e) {
      if (context.mounted) {
        // 23505: unique constraint violation, name already taken
        if (e is PostgrestException && e.code == '23505') {
          setState(() {
            this._nameCheckError = newName;
          });
        } else {
          showSnackBarError(context, e.toString());
        }
      }
    }

    if (newName != this._nameCheckError) {
      setState(() {
        this._nameCheckError = null;
        _editing = false;
      });
    }
  }
}

class _FriendsList extends StatelessWidget {
  const _FriendsList(this.textTheme, {super.key});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Consumer<Authentication>(builder: (context, auth, _) {
      return FutureBuilder(
        future: auth.account.name,
        builder: (context, snapshotName) {
          return FutureBuilder(
            future: auth.account.friends,
            builder: (context, snapshotFriends) {
              final name = snapshotName.data;
              final friends = snapshotFriends.data;

              if (name == null || friends == null) {
                return ListTile(
                  title: Row(
                    children: [
                      Text(context.l10n.friends, style: textTheme.bodyMedium),
                      const Center(child: CircularProgressIndicator()),
                    ],
                  ),
                );
              }

              return ExpansionTile(
                title: Text(context.l10n.nFriends(friends.length),
                    style: textTheme.bodyMedium),
                initiallyExpanded: friends.isEmpty,
                children: [
                  ...friends.map((friend) => _EditFriendTile(name, friend)),
                  ListTile(
                    title: TextButton.icon(
                      icon: const Icon(Icons.search),
                      label: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(context.l10n.findAddFriends,
                            style: textTheme.bodyMedium),
                      ),
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (context) =>
                              _FindFriendsDialog(textTheme, accountName: name),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    });
  }
}

class _FindFriendsDialog extends StatefulWidget {
  const _FindFriendsDialog(this.textTheme,
      {required this.accountName, super.key});

  final TextTheme textTheme;
  final String accountName;

  @override
  State<_FindFriendsDialog> createState() => _FindFriendsDialogState();
}

class _FindFriendsDialogState extends State<_FindFriendsDialog> {
  final _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<String> _visibleFriends = [];

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setState) {
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: Text(context.l10n.findFriends),
            ),
            body: Column(
              children: [
                // Friends search field
                ListTile(
                  title: TextField(
                    controller: this._searchController,
                    focusNode: this._focusNode,
                    textAlignVertical: TextAlignVertical.center,
                    textInputAction: TextInputAction.search,
                    keyboardType: TextInputType.name,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                    ),
                    onSubmitted: (value) async {
                      if (value.isEmpty) return;
                      final found = await Account.findFriendsByPrefix(value);
                      this._focusNode.requestFocus();
                      setState(() => this._visibleFriends = found);
                    },
                  ),
                ),
                // Friends search results
                Expanded(
                  child: ListView.builder(
                    itemCount: this._visibleFriends.length,
                    itemBuilder: (context, index) {
                      if (index > this._visibleFriends.length) {
                        return null;
                      }

                      return _EditFriendTile(
                          widget.accountName, this._visibleFriends[index]);
                    },
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EditFriendTile extends StatefulWidget {
  const _EditFriendTile(this.accountName, this.friend, {super.key});

  final String accountName;
  final String friend;

  @override
  State<_EditFriendTile> createState() => _EditFriendTileState();
}

class _EditFriendTileState extends State<_EditFriendTile> {
  bool _updating = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      title: Text(widget.friend, style: textTheme.bodyMedium),
      trailing: Consumer<Authentication>(builder: (context, auth, _) {
        final account = auth.account;

        return FutureBuilder(
            future: account.friends,
            builder: (context, snapshot) {
              final friends = snapshot.data;

              if (widget.friend == widget.accountName || friends == null) {
                return const SizedBox.shrink();
              }

              // We have not scheduled friendship update yet  or it is in progress
              if (this._updating ||
                  snapshot.connectionState != ConnectionState.done) {
                return const AspectRatio(
                    aspectRatio: 1, child: CircularProgressIndicator());
              }

              // Add or remove friend
              if (friends.contains(widget.friend)) {
                return IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    setState(() => this._updating = true);
                    await account.removeFriend(widget.friend);
                    setState(() => this._updating = false);
                  },
                );
              } else {
                return IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () async {
                    setState(() => this._updating = true);
                    await account.addFriend(widget.friend);
                    setState(() => this._updating = false);
                  },
                );
              }
            });
      }),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  const _SignOutButton(this.textTheme, {super.key});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Consumer<Authentication>(builder: (context, auth, _) {
        return TextButton.icon(
          icon: const Icon(Icons.logout),
          label: Align(
            alignment: Alignment.centerLeft,
            child: Text(context.l10n.signOut, style: textTheme.bodyMedium),
          ),
          onPressed: () async {
            try {
              await auth.signOut();
            } catch (e) {
              if (context.mounted) showSnackBarError(context, e.toString());
            }
          },
        );
      }),
    );
  }
}

class _DeleteAccountButton extends StatelessWidget {
  const _DeleteAccountButton(this.textTheme, {super.key});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: TextButton.icon(
        icon: const Icon(Icons.delete),
        label: Align(
          alignment: Alignment.centerLeft,
          child: Text(context.l10n.deleteAccount, style: textTheme.bodyMedium),
        ),
        onPressed: () {
          showDialog<void>(
            context: context,
            builder: (context) => _DeleteAccountDialog(textTheme),
          );
        },
      ),
    );
  }
}

class _ModulesConfig extends StatelessWidget {
  const _ModulesConfig(
    this.textTheme,
    this.loadedModules, {
    super.key,
  });

  final TextTheme textTheme;
  final List<Module>? loadedModules;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Consumer<UISettings>(builder: (context, ui, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: (loadedModules ?? [])
              .map((module) => CheckboxListTile.adaptive(
                  contentPadding: const EdgeInsets.all(0),
                  title: Text(module.description, style: textTheme.bodyMedium),
                  value:
                      ui.selectedModules?.any((m) => m == module.name) ?? false,
                  onChanged: (bool? value) {
                    if (value == true) {
                      ui.selectedModulesAdd(module.name);
                    } else {
                      ui.selectedModulesRemove(module.name);
                    }
                  }))
              .toList(),
        );
      }),
    );
  }
}

class _LanguageConfig extends StatelessWidget {
  const _LanguageConfig(this.textTheme, this.supportedLanguages, {super.key});

  final TextTheme textTheme;
  final List<String>? supportedLanguages;

  @override
  Widget build(BuildContext context) {
    return Consumer<UISettings>(
      builder: (context, ui, _) {
        // When language environment changes we must not crash
        final locales = <Locale?>[
          null,
          ...this.supportedLanguages?.map((ln) => Locale(ln)) ??
              WidgetsBinding.instance.platformDispatcher.locales
        ];
        if (!locales.contains(ui.locale)) {
          ui.locale = null;
        }

        return ListTile(
          title: Row(
            children: [
              Text(context.l10n.language, style: textTheme.bodyMedium),
              Flexible(
                fit: FlexFit.loose,
                child: IntrinsicWidth(
                  child: DropdownButton(
                    isExpanded: true,
                    underline: const Underline(),
                    value: ui.locale,
                    onChanged: (Locale? v) => ui.locale = v,
                    items: locales
                        .map((Locale? locale) => DropdownMenuItem<Locale>(
                            value: locale,
                            child: Align(
                              alignment: Alignment.center,
                              child: Text(
                                LocaleNames.of(context)
                                        ?.nameOf(locale.toString()) ??
                                    context.l10n.languageSystem,
                                overflow: TextOverflow.ellipsis,
                              ),
                            )))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ScaleConfig extends StatelessWidget {
  const _ScaleConfig(this.textTheme, {super.key});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Consumer<UISettings>(builder: (context, ui, _) {
      return ListTile(
        title: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(context.l10n.scale, style: textTheme.bodyMedium),
            DropdownButton(
              underline: const Underline(),
              value: (ui.scale * 10).round(),
              onChanged: (int? v) {
                if (v != null) {
                  ui.scale = v.toDouble() / 10;
                }
              },
              items: <int>[
                for (int i = (UISettings.scaleMin * 10).round();
                    i <= (UISettings.scaleMax * 10).round();
                    i++)
                  i
              ]
                  .map((int scale) => DropdownMenuItem<int>(
                      value: scale,
                      child: Text((scale.toDouble() / 10).toString())))
                  .toList(),
            ),
          ],
        ),
        subtitle:
            Text(context.l10n.scaleDescription, style: textTheme.labelMedium),
      );
    });
  }
}

class _OfflineModeConfig extends StatelessWidget {
  const _OfflineModeConfig(this.textTheme, {super.key});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Consumer<UISettings>(builder: (context, ui, _) {
      return ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.offlineMode,
                style: textTheme.bodyMedium,
              ),
            ),
            Switch.adaptive(
                value: ui.offline,
                onChanged: (value) {
                  ui.offline = value;
                }),
          ],
        ),
      );
    });
  }
}

class Underline extends StatelessWidget {
  const Underline({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1.0,
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFBDBDBD), width: 1.5),
        ),
      ),
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog(this.textTheme, {super.key});

  final TextTheme textTheme;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final codeController = TextEditingController();
  late int code;

  @override
  void initState() {
    code = Random().nextInt(10000);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<Authentication>(builder: (context, auth, _) {
      return StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          title: Text(context.l10n.deleteAccountConfirmation(code),
              style: widget.textTheme.bodyMedium),
          content: TextFormField(
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 4,
            maxLines: 1,
            controller: this.codeController,
            // Make sure 'OK' visibility is updated
            onChanged: (String value) => setState(() {}),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: !_validCode(this.codeController.text)
                  ? null
                  : () async {
                      try {
                        await auth.deleteUserAndSignOut();
                      } catch (e) {
                        if (context.mounted) {
                          showSnackBarError(context, e.toString());
                        }
                      }
                      if (context.mounted) Navigator.of(context).pop();
                    },
              child: Text(context.l10n.deleteAccount, textAlign: TextAlign.end),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.cancel, textAlign: TextAlign.end),
            ),
          ],
        );
      });
    });
  }

  bool _validCode(String code) {
    return code.length == 4 && int.tryParse(code) == this.code;
  }
}
