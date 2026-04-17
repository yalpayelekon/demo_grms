/// Shared merge policy for providers that consume three concurrent state feeds:
/// 1. local optimistic updates (user action, immediate UI feedback)
/// 2. websocket events (server push)
/// 3. polling snapshots (periodic full refresh)
///
/// Precedence is deterministic and global:
/// local optimistic > websocket event > polling snapshot.
///
/// Recency fields are still honored before source precedence whenever available:
/// - Higher [version] always wins.
/// - If versions are equal/missing, newer [eventTimestamp] wins.
/// - If event timestamps are equal/missing, newer [observedAt] wins.
/// - Only then source precedence is used as final tiebreaker.
///
/// This avoids flicker where an older snapshot briefly overrides a newer push,
/// or a reconnect replay re-applies stale websocket payloads.
enum MergeSource {
  localOptimistic,
  websocketEvent,
  pollingSnapshot,
}

class MergeMetadata {
  const MergeMetadata({
    required this.source,
    required this.observedAt,
    this.eventTimestamp,
    this.version,
    this.isReplay = false,
  });

  final MergeSource source;
  final DateTime observedAt;
  final DateTime? eventTimestamp;
  final int? version;

  /// Marks websocket messages replayed after reconnect/resubscribe.
  final bool isReplay;
}

class MergeDecision {
  const MergeDecision.accept(this.reason) : acceptIncoming = true;
  const MergeDecision.reject(this.reason) : acceptIncoming = false;

  final bool acceptIncoming;
  final String reason;
}

class StateMergePolicy {
  const StateMergePolicy();

  static const Map<MergeSource, int> _priority = {
    MergeSource.pollingSnapshot: 0,
    MergeSource.websocketEvent: 1,
    MergeSource.localOptimistic: 2,
  };

  MergeDecision decide({
    required MergeMetadata? current,
    required MergeMetadata incoming,
  }) {
    if (current == null) {
      return const MergeDecision.accept('no-current-state');
    }

    final int? currentVersion = current.version;
    final int? incomingVersion = incoming.version;
    if (currentVersion != null && incomingVersion != null) {
      if (incomingVersion > currentVersion) {
        return const MergeDecision.accept('higher-version');
      }
      if (incomingVersion < currentVersion) {
        return const MergeDecision.reject('stale-version');
      }
    }

    final DateTime? currentEventAt = current.eventTimestamp;
    final DateTime? incomingEventAt = incoming.eventTimestamp;
    if (currentEventAt != null && incomingEventAt != null) {
      if (incomingEventAt.isAfter(currentEventAt)) {
        return const MergeDecision.accept('newer-event-timestamp');
      }
      if (incomingEventAt.isBefore(currentEventAt)) {
        return const MergeDecision.reject('stale-event-timestamp');
      }
    }

    if (incoming.observedAt.isAfter(current.observedAt)) {
      return const MergeDecision.accept('newer-observed-at');
    }
    if (incoming.observedAt.isBefore(current.observedAt)) {
      return const MergeDecision.reject('stale-observed-at');
    }

    final int incomingPriority = _priority[incoming.source] ?? -1;
    final int currentPriority = _priority[current.source] ?? -1;
    if (incomingPriority > currentPriority) {
      return const MergeDecision.accept('higher-source-priority');
    }
    if (incomingPriority < currentPriority) {
      return const MergeDecision.reject('lower-source-priority');
    }

    if (incoming.isReplay && !current.isReplay) {
      return const MergeDecision.reject('reconnect-replay-duplicate');
    }

    return const MergeDecision.accept('same-priority-idempotent-refresh');
  }

  T mergeEntity<T>({
    required T? current,
    required T incoming,
    required MergeMetadata Function(T value) metadataOf,
    void Function(MergeDecision decision)? onDecision,
  }) {
    final decision = decide(
      current: current == null ? null : metadataOf(current),
      incoming: metadataOf(incoming),
    );
    onDecision?.call(decision);
    if (decision.acceptIncoming || current == null) {
      return incoming;
    }
    return current;
  }
}
