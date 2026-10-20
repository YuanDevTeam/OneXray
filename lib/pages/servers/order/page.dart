import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:onexray/l10n/localizations/app_localizations.dart';
import 'package:onexray/pages/servers/order/controller.dart';
import 'package:onexray/pages/shared/alert.dart';
import 'package:onexray/pages/shared/widgets/button_progress.dart';
import 'package:onexray/pages/shared/widgets/page_action_bar.dart';
import 'package:onexray/pages/shared/widgets/page_app_bar.dart';
import 'package:onexray/pages/shared/widgets/responsive_content.dart';
import 'package:onexray/pages/theme/color.dart';
import 'package:onexray/pages/theme/layout.dart';
import 'package:onexray/service/shared/failure.dart';

class ManualOrderPage extends StatelessWidget {
  const ManualOrderPage({super.key, required this.params});
  final ManualOrderParams params;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => ManualOrderController(params),
    child: BlocBuilder<ManualOrderController, ManualOrderState>(
      builder: (context, state) {
        final controller = context.read<ManualOrderController>();
        final l = AppLocalizations.of(context)!;
        final mobile =
            MediaQuery.sizeOf(context).width <= AppLayout.mobileBreakpoint;
        return PopScope(
          canPop: !state.busy,
          child: Scaffold(
            appBar: PageAppBar(
              title: Text(
                params.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            body: SafeArea(
              child: ResponsiveContent(
                child: Column(
                  children: [
                    if (state.failure != null)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              state.failure is FormatException
                                  ? l.manualOrderChanged
                                  : appFailureMessage(l, state.failure),
                              style: TextStyle(
                                color: ColorManager.palette(context)
                                    .destructive,
                              ),
                            ),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton(
                                onPressed: state.busy
                                    ? null
                                    : controller.reload,
                                child: Text(l.manualOrderReload),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ReorderableListView.builder(
                        key: const PageStorageKey('manual-order'),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        buildDefaultDragHandles: false,
                        onReorderItem: controller.reorder,
                        itemCount: state.items.length,
                        itemBuilder: (context, index) {
                          final item = state.items[index];
                          final handle = Tooltip(
                            message: l.manualOrderDrag,
                            // A tooltip long press would compete with the drag handle.
                            triggerMode: TooltipTriggerMode.manual,
                            child: Container(
                              width: 40,
                              height: 48,
                              alignment: Alignment.center,
                              color: Colors.transparent,
                              child: Icon(
                                LucideIcons.gripVertical,
                                size: 20,
                                color: ColorManager.palette(context)
                                    .mutedForeground,
                              ),
                            ),
                          );
                          return Material(
                            key: ValueKey(item.id),
                            color: ColorManager.palette(context).card,
                            child: ListTile(
                              leading: mobile
                                  ? ReorderableDelayedDragStartListener(
                                      index: index,
                                      enabled: !state.busy,
                                      child: handle,
                                    )
                                  : ReorderableDragStartListener(
                                      index: index,
                                      enabled: !state.busy,
                                      child: handle,
                                    ),
                              title: Text(
                                item.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    key: ValueKey('move-up-${item.id}'),
                                    tooltip: l.manualOrderMoveUp,
                                    onPressed: state.busy || index == 0
                                        ? null
                                        : () => controller.reorder(
                                            index,
                                            index - 1,
                                          ),
                                    icon: const Icon(
                                      LucideIcons.arrowUp,
                                      size: 18,
                                    ),
                                  ),
                                  IconButton(
                                    key: ValueKey('move-down-${item.id}'),
                                    tooltip: l.manualOrderMoveDown,
                                    onPressed:
                                        state.busy ||
                                            index == state.items.length - 1
                                        ? null
                                        : () => controller.reorder(
                                            index,
                                            index + 1,
                                          ),
                                    icon: const Icon(
                                      LucideIcons.arrowDown,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            bottomNavigationBar: PageActionBar(
              children: [
                OutlinedButton(
                  onPressed: state.busy
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: Text(l.prototypeCancel),
                ),
                FilledButton(
                  onPressed: state.busy
                      ? null
                      : () async {
                          final saved = await controller.save();
                          if (saved && context.mounted) {
                            ContextAlert.settingsSaved(context);
                            Navigator.of(context).pop(true);
                          }
                        },
                  child: state.busy
                      ? const ButtonProgressIndicator()
                      : Text(l.prototypeSave),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
