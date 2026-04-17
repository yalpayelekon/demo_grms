import 'backend_error.dart';

sealed class ApiResult<T> {
  const ApiResult();

  const factory ApiResult.success(T value) = Success<T>;
  const factory ApiResult.failure(BackendError error) = Failure<T>;
}

class Success<T> extends ApiResult<T> {
  final T value;
  const Success(this.value);
}

class Failure<T> extends ApiResult<T> {
  final BackendError error;
  const Failure(this.error);
}
