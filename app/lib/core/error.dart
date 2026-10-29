/// Typed failures surfaced to the UI (spec §5: never crash, always explain).
sealed class AppFailure {
  const AppFailure(this.messageKey, [this.detail]);

  /// l10n key rendered by the UI.
  final String messageKey;
  final String? detail;

  @override
  String toString() =>
      '$runtimeType($messageKey${detail == null ? '' : ': $detail'})';
}

class FileUnreadable extends AppFailure {
  const FileUnreadable([String? detail]) : super('failure.fileUnreadable', detail);
}

class UnsupportedFormat extends AppFailure {
  const UnsupportedFormat([String? detail])
      : super('failure.unsupportedFormat', detail);
}

class InvalidDesign extends AppFailure {
  const InvalidDesign([String? detail]) : super('failure.invalidDesign', detail);
}

class DatabaseFailure extends AppFailure {
  const DatabaseFailure([String? detail]) : super('failure.database', detail);
}

class ExportFailure extends AppFailure {
  const ExportFailure([String? detail]) : super('failure.export', detail);
}

class PermissionDenied extends AppFailure {
  const PermissionDenied([String? detail])
      : super('failure.permissionDenied', detail);
}

class CancelledByUser extends AppFailure {
  const CancelledByUser() : super('failure.cancelled');
}
