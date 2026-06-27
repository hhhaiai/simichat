import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/memory/user_profile.dart';
import 'dreaming_provider.dart';
import 'key_point_memory_provider.dart';

const kUserProfileStorageKey = 'user_profile_v1';
const kUserProfileControlsStorageKey = 'user_profile_controls_v1';
const kUserProfileHistoryStorageKey = 'user_profile_history_v1';
const kUserProfileChangeProposalsStorageKey =
    'user_profile_change_proposals_v1';
const _kMaxUserProfileHistoryEntries = 20;
const _kMaxUserProfileChangeProposals = 10;

final userProfileBuilderProvider = Provider<UserProfileBuilder>(
  (ref) => const UserProfileBuilder(),
);

final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfile?>((ref) {
      return UserProfileNotifier();
    });

final userProfileControlsProvider =
    StateNotifierProvider<UserProfileControlsNotifier, UserProfileControls>((
      ref,
    ) {
      return UserProfileControlsNotifier();
    });

final userProfileHistoryProvider =
    StateNotifierProvider<
      UserProfileHistoryNotifier,
      List<UserProfileHistoryEntry>
    >((ref) {
      return UserProfileHistoryNotifier();
    });

final userProfileChangeProposalsProvider =
    StateNotifierProvider<
      UserProfileChangeProposalsNotifier,
      List<UserProfileChangeProposal>
    >((ref) {
      return UserProfileChangeProposalsNotifier();
    });

class UserProfileNotifier extends StateNotifier<UserProfile?> {
  UserProfileNotifier() : super(null) {
    ready = _load();
  }

  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = decodeUserProfile(prefs.getString(kUserProfileStorageKey));
  }

  Future<void> save(UserProfile profile) async {
    await ready;
    state = profile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kUserProfileStorageKey, jsonEncode(profile.toJson()));
  }

  Future<void> clear() async {
    await ready;
    state = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kUserProfileStorageKey);
  }
}

class UserProfileControlsNotifier extends StateNotifier<UserProfileControls> {
  UserProfileControlsNotifier() : super(const UserProfileControls()) {
    ready = _load();
  }

  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = decodeUserProfileControls(
      prefs.getString(kUserProfileControlsStorageKey),
    );
  }

  Future<bool> hideSignal(String signal) async {
    await ready;
    final next = state.hideSignal(signal);
    return _saveIfChanged(next);
  }

  Future<bool> editSignal(String original, String edited) async {
    await ready;
    if (!isSafeUserProfileSignal(edited)) return false;
    final next = state.editSignal(original, edited);
    return _saveIfChanged(next);
  }

  Future<void> clearControls() async {
    await ready;
    state = const UserProfileControls();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kUserProfileControlsStorageKey);
  }

  Future<bool> _saveIfChanged(UserProfileControls next) async {
    if (encodeUserProfileControls(next) == encodeUserProfileControls(state)) {
      return false;
    }
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kUserProfileControlsStorageKey,
      encodeUserProfileControls(state),
    );
    return true;
  }
}

class UserProfileChangeProposalsNotifier
    extends StateNotifier<List<UserProfileChangeProposal>> {
  UserProfileChangeProposalsNotifier() : super(const []) {
    ready = _load();
  }

  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = decodeUserProfileChangeProposals(
      prefs.getString(kUserProfileChangeProposalsStorageKey),
    );
  }

  Future<void> add(UserProfileChangeProposal proposal) async {
    await ready;
    if (!proposal.hasChanges || !proposal.candidateProfile.hasContent) return;
    final encodedCandidate = encodeUserProfile(proposal.candidateProfile);
    state = List.unmodifiable(
      [
        proposal,
        ...state.where(
          (item) =>
              encodeUserProfile(item.candidateProfile) != encodedCandidate,
        ),
      ].take(_kMaxUserProfileChangeProposals),
    );
    await _save();
  }

  Future<void> remove(String id) async {
    await ready;
    state = List.unmodifiable(state.where((item) => item.id != id));
    await _save();
  }

  Future<void> replace(UserProfileChangeProposal proposal) async {
    await ready;
    if (!proposal.hasChanges || !proposal.candidateProfile.hasContent) {
      state = List.unmodifiable(state.where((item) => item.id != proposal.id));
      await _save();
      return;
    }
    state = List.unmodifiable(
      [
        proposal,
        ...state.where((item) => item.id != proposal.id),
      ].take(_kMaxUserProfileChangeProposals),
    );
    await _save();
  }

  Future<void> clear() async {
    await ready;
    state = const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kUserProfileChangeProposalsStorageKey);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    if (state.isEmpty) {
      await prefs.remove(kUserProfileChangeProposalsStorageKey);
      return;
    }
    await prefs.setString(
      kUserProfileChangeProposalsStorageKey,
      encodeUserProfileChangeProposals(state),
    );
  }
}

class UserProfileHistoryNotifier
    extends StateNotifier<List<UserProfileHistoryEntry>> {
  UserProfileHistoryNotifier() : super(const []) {
    ready = _load();
  }

  late final Future<void> ready;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = decodeUserProfileHistory(
      prefs.getString(kUserProfileHistoryStorageKey),
    );
  }

  Future<void> record(UserProfile profile, {String reason = 'rebuild'}) async {
    await ready;
    final now = DateTime.now();
    final entry = UserProfileHistoryEntry(
      id: '${now.microsecondsSinceEpoch}-$reason',
      createdAt: now,
      reason: reason,
      profile: profile,
    );
    final encodedProfile = encodeUserProfile(profile);
    state = List.unmodifiable(
      [
        entry,
        ...state.where(
          (item) => encodeUserProfile(item.profile) != encodedProfile,
        ),
      ].take(_kMaxUserProfileHistoryEntries),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kUserProfileHistoryStorageKey,
      encodeUserProfileHistory(state),
    );
  }

  Future<void> clearHistory() async {
    await ready;
    state = const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kUserProfileHistoryStorageKey);
  }
}

Future<UserProfile> buildCurrentUserProfileCandidate(
  WidgetRef ref, {
  DateTime? now,
}) async {
  final memoryNotifier = ref.read(keyPointMemoryProvider.notifier);
  final digestNotifier = ref.read(dreamingDigestProvider.notifier);
  final controlsNotifier = ref.read(userProfileControlsProvider.notifier);
  await memoryNotifier.ready;
  await digestNotifier.ready;
  await controlsNotifier.ready;

  return ref
      .read(userProfileBuilderProvider)
      .build(
        keyPoints: ref.read(keyPointMemoryProvider),
        digest: ref.read(dreamingDigestProvider),
        controls: ref.read(userProfileControlsProvider),
        now: now,
      );
}

Future<UserProfile> rebuildUserProfile(
  WidgetRef ref, {
  DateTime? now,
  String reason = 'rebuild',
}) async {
  final profileNotifier = ref.read(userProfileProvider.notifier);
  final historyNotifier = ref.read(userProfileHistoryProvider.notifier);
  await profileNotifier.ready;
  await historyNotifier.ready;

  final profile = await buildCurrentUserProfileCandidate(ref, now: now);
  await profileNotifier.save(profile);
  await historyNotifier.record(profile, reason: reason);
  return profile;
}

Future<UserProfileChangeProposal?> proposeUserProfileChanges(
  WidgetRef ref, {
  DateTime? now,
  String reason = 'profile_proposal',
}) async {
  final profileNotifier = ref.read(userProfileProvider.notifier);
  final proposalNotifier = ref.read(
    userProfileChangeProposalsProvider.notifier,
  );
  await profileNotifier.ready;
  await proposalNotifier.ready;

  final current = ref.read(userProfileProvider);
  final candidate = await buildCurrentUserProfileCandidate(ref, now: now);
  final proposal = UserProfileChangeProposal(
    id: '${(now ?? DateTime.now()).microsecondsSinceEpoch}-$reason',
    createdAt: now ?? DateTime.now(),
    reason: reason,
    baseProfile: current,
    candidateProfile: candidate,
  );
  if (!proposal.hasChanges || !candidate.hasContent) return null;
  await proposalNotifier.add(proposal);
  return proposal;
}

Future<UserProfile?> acceptUserProfileProposal(
  WidgetRef ref,
  String proposalId, {
  DateTime? now,
}) async {
  final profileNotifier = ref.read(userProfileProvider.notifier);
  final historyNotifier = ref.read(userProfileHistoryProvider.notifier);
  final proposalNotifier = ref.read(
    userProfileChangeProposalsProvider.notifier,
  );
  await profileNotifier.ready;
  await historyNotifier.ready;
  await proposalNotifier.ready;

  UserProfileChangeProposal? proposal;
  for (final item in ref.read(userProfileChangeProposalsProvider)) {
    if (item.id == proposalId) {
      proposal = item;
      break;
    }
  }
  if (proposal == null) return null;

  final accepted = proposal.candidateProfile.copyWith(
    updatedAt: now ?? DateTime.now(),
  );
  await profileNotifier.save(accepted);
  await historyNotifier.record(accepted, reason: 'accept_proposal');
  await proposalNotifier.remove(proposalId);
  return accepted;
}

Future<UserProfile?> acceptUserProfileProposalItem(
  WidgetRef ref, {
  required String proposalId,
  required UserProfileChangeItem item,
  DateTime? now,
}) async {
  final profileNotifier = ref.read(userProfileProvider.notifier);
  final historyNotifier = ref.read(userProfileHistoryProvider.notifier);
  final proposalNotifier = ref.read(
    userProfileChangeProposalsProvider.notifier,
  );
  await profileNotifier.ready;
  await historyNotifier.ready;
  await proposalNotifier.ready;

  UserProfileChangeProposal? proposal;
  for (final candidate in ref.read(userProfileChangeProposalsProvider)) {
    if (candidate.id == proposalId) {
      proposal = candidate;
      break;
    }
  }
  if (proposal == null) return null;

  final current =
      ref.read(userProfileProvider) ??
      proposal.baseProfile ??
      UserProfile.empty(updatedAt: now);
  final applied = applyUserProfileChangeItem(current, item).copyWith(
    updatedAt: now ?? DateTime.now(),
    sourceCount: current.sourceCount > proposal.candidateProfile.sourceCount
        ? current.sourceCount
        : proposal.candidateProfile.sourceCount,
    digestDayKey:
        proposal.candidateProfile.digestDayKey ?? current.digestDayKey,
  );
  await profileNotifier.save(applied);
  await historyNotifier.record(applied, reason: 'accept_proposal_item');
  await proposalNotifier.replace(proposal.copyWith(baseProfile: applied));
  return applied;
}

Future<bool> rejectUserProfileProposal(WidgetRef ref, String proposalId) async {
  final proposalNotifier = ref.read(
    userProfileChangeProposalsProvider.notifier,
  );
  await proposalNotifier.ready;
  final existed = ref
      .read(userProfileChangeProposalsProvider)
      .any((item) => item.id == proposalId);
  if (!existed) return false;
  await proposalNotifier.remove(proposalId);
  return true;
}

Future<bool> rejectUserProfileProposalItem(
  WidgetRef ref, {
  required String proposalId,
  required UserProfileChangeItem item,
}) async {
  final proposalNotifier = ref.read(
    userProfileChangeProposalsProvider.notifier,
  );
  await proposalNotifier.ready;
  UserProfileChangeProposal? proposal;
  for (final candidate in ref.read(userProfileChangeProposalsProvider)) {
    if (candidate.id == proposalId) {
      proposal = candidate;
      break;
    }
  }
  if (proposal == null) return false;

  final current = ref.read(userProfileProvider) ?? proposal.baseProfile;
  final candidate = discardUserProfileChangeItem(
    proposal.candidateProfile,
    item,
  );
  await proposalNotifier.replace(
    proposal.copyWith(baseProfile: current, candidateProfile: candidate),
  );
  return true;
}

Future<UserProfile> hideUserProfileSignal(
  WidgetRef ref,
  String signal, {
  DateTime? now,
}) async {
  await ref.read(userProfileControlsProvider.notifier).hideSignal(signal);
  return rebuildUserProfile(ref, now: now, reason: 'hide_signal');
}

Future<UserProfile?> editUserProfileSignal(
  WidgetRef ref, {
  required String original,
  required String edited,
  DateTime? now,
}) async {
  final changed = await ref
      .read(userProfileControlsProvider.notifier)
      .editSignal(original, edited);
  if (!changed) return null;
  return rebuildUserProfile(ref, now: now, reason: 'edit_signal');
}

Future<UserProfile?> restoreUserProfileFromHistory(
  WidgetRef ref,
  String historyEntryId, {
  DateTime? now,
}) async {
  final profileNotifier = ref.read(userProfileProvider.notifier);
  final historyNotifier = ref.read(userProfileHistoryProvider.notifier);
  await profileNotifier.ready;
  await historyNotifier.ready;

  UserProfileHistoryEntry? entry;
  for (final item in ref.read(userProfileHistoryProvider)) {
    if (item.id == historyEntryId) {
      entry = item;
      break;
    }
  }
  if (entry == null) return null;

  final restored = entry.profile.copyWith(updatedAt: now ?? DateTime.now());
  await profileNotifier.save(restored);
  await historyNotifier.record(restored, reason: 'restore_history');
  return restored;
}
