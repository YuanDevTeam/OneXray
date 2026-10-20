import 'package:onexray/pages/shared/page_cubit.dart';

class ManualOrderItem {
  const ManualOrderItem(this.id, this.name);
  final int id;
  final String name;
}

class ManualOrderParams {
  const ManualOrderParams({
    required this.title,
    required this.items,
    required this.save,
    required this.reload,
  });
  final String title;
  final List<ManualOrderItem> items;
  final Future<void> Function(List<int> expectedIds, List<int> orderedIds) save;
  final Future<List<ManualOrderItem>> Function() reload;
}

class ManualOrderState {
  ManualOrderState({
    required List<ManualOrderItem> items,
    this.busy = false,
    this.failure,
  }) : items = List.unmodifiable(items);
  final List<ManualOrderItem> items;
  final bool busy;
  final Object? failure;
}

/// A local draft; catalog probe/favorite streams do not replace its contents.
class ManualOrderController extends PageCubit<ManualOrderState> {
  ManualOrderController(this.params)
    : expectedIds = params.items.map((item) => item.id).toList(),
      super(ManualOrderState(items: params.items));
  final ManualOrderParams params;
  List<int> expectedIds;

  void reorder(int from, int to) {
    if (state.busy || from == to) return;
    final items = state.items.toList();
    items.insert(to, items.removeAt(from));
    emit(ManualOrderState(items: items));
  }

  Future<bool> save() async {
    if (state.busy) return false;
    emit(ManualOrderState(items: state.items, busy: true));
    try {
      await params.save(
        expectedIds.toList(),
        state.items.map((item) => item.id).toList(),
      );
      emit(ManualOrderState(items: state.items));
      return true;
    } catch (error) {
      emit(ManualOrderState(items: state.items, failure: error));
      return false;
    }
  }

  Future<void> reload() async {
    if (state.busy) return;
    emit(ManualOrderState(items: state.items, busy: true));
    try {
      final items = await params.reload();
      expectedIds = items.map((item) => item.id).toList();
      emit(ManualOrderState(items: items));
    } catch (error) {
      emit(ManualOrderState(items: state.items, failure: error));
    }
  }
}
