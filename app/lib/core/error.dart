/// Typed failures surfaced to the UI (spec §5: never crash, always explain).
sealed class AppFailure {
  const AppFailure(this.messageKey, [this.detail]);

  /// l10n key rendered by the UI.
  final String messageKey;
  final String? detail;

  @override
  String toString() => '$runtimeType($messageKey${detail == null ? '' : ': $detail'})';
}

class FileUnreadable extends AppFailure {
  const FileUnreadable([super.detail]) : super('failure.fileUnreadable');
}

class UnsupportedFormat extends AppFailure {
  const UnsupportedFormat([super.detail]) : super('failure.unsupportedFormat');
}

class InvalidDesign extends AppFailure {
  const InvalidDesign([super.detail]) : super('failure.invalidDesign');
}

class DatabaseFailure extends AppFailure {
  const DatabaseFailure([super.detail]) : super('failure.database');
}

class ExportFailure extends AppFailure {
  const ExportFailure([super.detail]) : super('failure.export');
}

class PermissionDenied extends AppFailure {
  const PermissionDenied([super.detail]) : super('failure.permissionDenied');
}

class CancelledByUser extends AppFailure {
  const CancelledByUser() : super('failure.cancelled');
}
