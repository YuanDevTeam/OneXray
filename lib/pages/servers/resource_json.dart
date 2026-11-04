import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:onexray/core/db/database/database.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/font.dart';
import 'package:onexray/service/servers/outbound/state_db.dart';
import 'package:onexray/service/shared/failure.dart';

/// A bounded view of this asset, independent of selection or compiled runtime.
class ServerResourceJsonPreview extends StatefulWidget {
  const ServerResourceJsonPreview({super.key, required this.row});
  final CoreConfigData row;

  @override
  State<ServerResourceJsonPreview> createState() =>
      _ServerResourceJsonPreviewState();
}

class _ServerResourceJsonPreviewState extends State<ServerResourceJsonPreview> {
  final scroll = ScrollController();
  String? text;
  Object? error;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(ServerResourceJsonPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.data != widget.row.data ||
        oldWidget.row.type != widget.row.type ||
        oldWidget.row.name != widget.row.name) {
      _read();
    }
  }

  void _read() {
    text = null;
    error = null;
    try {
      final row = widget.row;
      if (row.type == 'outbound') {
        text = const JsonEncoder.withIndent('  ')
            .convert(readOutboundFromDbData(row));
      } else {
        final data = row.data;
        if (data == null || data.isEmpty) {
          throw const FormatException('Configuration database data is empty');
        }
        final original = utf8.decode(base64Decode(data));
        if (jsonDecode(original) is! Map<String, dynamic>) {
          throw const FormatException(
            'Configuration root must be a JSON object',
          );
        }
        // Complete configurations remain verbatim; no compile/adapt projection.
        text = original;
      }
    } catch (failure) {
      error = failure;
    }
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxHeight: 320),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Scrollbar(
        key: const ValueKey('server-resource-json-scrollbar'),
        controller: scroll,
        child: SingleChildScrollView(
          controller: scroll,
          primary: false,
          child: SelectableText(
            error == null
                ? text!
                : appFailureMessage(AppLocalizations.of(context)!, error),
            key: const ValueKey('server-resource-json-text'),
            textDirection: TextDirection.ltr,
            style: AppTypography.supporting.copyWith(
              fontFamily: AppFontFamily.mono,
              color: error == null
                  ? ColorManager.primaryText(context)
                  : ColorManager.palette(context).destructive,
            ),
          ),
        ),
      ),
    ),
  );
}
