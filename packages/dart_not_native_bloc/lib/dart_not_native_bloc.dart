/// `flutter_bloc`'s widgets for dart_not_native's widget layer.
///
/// `flutter_bloc` is two things: the `bloc` library, which is pure Dart, and
/// a set of widgets that put a bloc in a Flutter tree. The widgets extend
/// Flutter's, so an app on `package:dart_not_native/widgets.dart` cannot use
/// them. These are the same widgets - the same names, the same signatures -
/// over this framework's own, so an app that used `flutter_bloc` changes one
/// import:
///
/// ```dart
/// import 'package:dart_not_native/widgets.dart';
/// import 'package:dart_not_native_bloc/dart_not_native_bloc.dart';
///
/// BlocProvider(
///   create: (context) => GuestsBloc(context.read<GuestRepository>()),
///   child: BlocBuilder<GuestsBloc, GuestsState>(
///     builder: (context, state) => Text('${state.guests.length} guests'),
///   ),
/// )
/// ```
///
/// `package:bloc` is re-exported, as `flutter_bloc` re-exports it, so `Bloc`,
/// `Cubit` and `Emitter` come with the same import.
///
/// One thing is different underneath, and it follows from how this
/// framework draws: a change rebuilds the tree from the root and patches what
/// moved, so `buildWhen` decides which state a builder is *given*, not
/// whether its function runs. See [BlocBuilder].
library;

export 'package:bloc/bloc.dart';

export 'src/bloc_widgets.dart';
export 'src/provider.dart';
