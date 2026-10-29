/// Integrity states reported by `wren doctor`.
enum DoctorIntegrityStatus {
  /// The cheap checks shared with `wren list` and SDK prelaunch passed.
  basicChecksPassed,

  /// All locally available full integrity checks passed.
  fullyVerified,

  /// At least one check confirmed damage.
  needsRepair,

  /// No damage was confirmed, but some evidence was unavailable.
  incomplete,
}

/// Outcome of one named full integrity check.
enum DoctorCheckStatus {
  /// The check completed and found no problem.
  passed,

  /// The check confirmed damage in Wren-managed state.
  confirmedDamage,

  /// The check could not establish health or damage.
  incomplete,
}

/// Whether all registered releases and their requested checks were covered.
enum DoctorScanCompletion {
  /// Every registered release completed its requested checks.
  complete,

  /// At least one check or part of the release registry was unavailable.
  incomplete,
}

/// A named full integrity check and its result.
class DoctorIntegrityCheck {
  /// Creates a check result.
  const new({
    required this.id,
    required this.status,
    required this.detail,
    this.nextStep,
  });

  /// Stable machine-readable check identifier.
  final String id;

  /// Whether the check passed, confirmed damage, or could not complete.
  final DoctorCheckStatus status;

  /// Human-readable explanation of this check's result.
  final String detail;

  /// Optional next step for the user.
  final String? nextStep;
}

/// Full integrity result for one registered Flutter release.
class DoctorReleaseIntegrity {
  /// Creates a release integrity result.
  new({
    required this.channel,
    required this.version,
    required this.host,
    required this.dartVersion,
    required List<DoctorIntegrityCheck> checks,
  }) : checks = List.unmodifiable(checks);

  /// Release channel, such as `stable` or `beta`.
  final String channel;

  /// Flutter release version, or the registered directory name if unknown.
  final String version;

  /// Host associated with this installation, or `unknown`.
  final String host;

  /// Canonical bundled Dart version when recorded.
  final String? dartVersion;

  /// Check results in scan order.
  final List<DoctorIntegrityCheck> checks;

  /// Confirmed damage remains visible even if another check was incomplete.
  DoctorIntegrityStatus get integrity {
    if (hasConfirmedDamage) return DoctorIntegrityStatus.needsRepair;
    if (isIncomplete) return DoctorIntegrityStatus.incomplete;
    return DoctorIntegrityStatus.fullyVerified;
  }

  /// Whether any check confirmed damage.
  bool get hasConfirmedDamage =>
      checks.any((check) => check.status == DoctorCheckStatus.confirmedDamage);

  /// Whether any check could not complete.
  bool get isIncomplete =>
      checks.any((check) => check.status == DoctorCheckStatus.incomplete);

  /// First actionable repair reason, if damage was confirmed.
  String? get repairReason {
    for (final check in checks) {
      if (check.status == DoctorCheckStatus.confirmedDamage) {
        return check.detail;
      }
    }
    return null;
  }
}

/// Results for a full scan of all registered releases.
class DoctorFullIntegrityReport {
  /// Creates a full scan report.
  new(
    List<DoctorReleaseIntegrity> releases, {
    List<DoctorIntegrityCheck> checks = const [],
  }) : releases = List.unmodifiable(releases),
       checks = List.unmodifiable(checks);

  /// Per-release results in deterministic order.
  final List<DoctorReleaseIntegrity> releases;

  /// Scan-wide checks, such as release registry enumeration.
  final List<DoctorIntegrityCheck> checks;

  /// Whether any release check was incomplete.
  bool get isIncomplete =>
      checks.any((check) => check.status == DoctorCheckStatus.incomplete) ||
      releases.any((release) => release.isIncomplete);

  /// Overall scan completion, independent of confirmed integrity damage.
  DoctorScanCompletion get completion => isIncomplete
      ? DoctorScanCompletion.incomplete
      : DoctorScanCompletion.complete;

  /// Whether any release has confirmed damage.
  bool get hasConfirmedDamage =>
      releases.any((release) => release.hasConfirmedDamage) ||
      checks.any((check) => check.status == DoctorCheckStatus.confirmedDamage);
}
