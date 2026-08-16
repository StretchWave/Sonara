import 'dart:async';

/// Runs [tasks] concurrently and completes with the first non-null value,
/// or null when every task completes with null or an error.
///
/// Used to race multiple resolver instances: the first instance that
/// answers wins, while slower/failing ones are ignored.
Future<T?> raceFirstNotNull<T>(List<Future<T?>> tasks) {
  final completer = Completer<T?>();
  var pending = tasks.length;
  if (pending == 0) {
    completer.complete(null);
    return completer.future;
  }
  for (final task in tasks) {
    task.then((value) {
      if (value != null && !completer.isCompleted) {
        completer.complete(value);
        return;
      }
      pending -= 1;
      if (pending == 0 && !completer.isCompleted) completer.complete(null);
    }, onError: (Object _) {
      pending -= 1;
      if (pending == 0 && !completer.isCompleted) completer.complete(null);
    });
  }
  return completer.future;
}
