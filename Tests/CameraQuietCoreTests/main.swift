import Foundation
// Standalone runner also works with Command Line Tools, without XCTest/Xcode.
let tests: [(String, () throws -> Void)] = [
    ("testDurableIntentBeforeMuteAndRestoreAfterLastCamera", MuteSessionTests().testDurableIntentBeforeMuteAndRestoreAfterLastCamera),
    ("testUserOverrideIsNotOverwrittenOrRemutedUntilIdle", MuteSessionTests().testUserOverrideIsNotOverwrittenOrRemutedUntilIdle),
    ("testInitiallySilentStaysSilentAndDoesNotClaimUserChange", MuteSessionTests().testInitiallySilentStaysSilentAndDoesNotClaimUserChange),
    ("testCrashRecoveryAndIdempotency", MuteSessionTests().testCrashRecoveryAndIdempotency),
    ("testCrashRecoveryPreservesUserChange", MuteSessionTests().testCrashRecoveryPreservesUserChange),
    ("testCannotMuteWithoutSavingRecovery", MuteSessionTests().testCannotMuteWithoutSavingRecovery),
    ("testFailedRestoreRetainsJournalForRetry", MuteSessionTests().testFailedRestoreRetainsJournalForRetry),
    ("testPauseRestoresAndExplicitOverrideLastsUntilIdle", MuteSessionTests().testPauseRestoresAndExplicitOverrideLastsUntilIdle),
    ("testFileJournalRoundTripAndCorruptionDoesNotOverwrite", MuteSessionTests().testFileJournalRoundTripAndCorruptionDoesNotOverwrite),
    ("testConcurrentCamerasAndIdleDebounce", CameraPolicyTests().testConcurrentCamerasAndIdleDebounce),
    ("testUnknownIsNotIdleAndEventuallyFails", CameraPolicyTests().testUnknownIsNotIdleAndEventuallyFails),
    ("testKnownActiveCameraWinsOverAnotherUnreadableCamera", CameraPolicyTests().testKnownActiveCameraWinsOverAnotherUnreadableCamera),
    ("testRejectsSymlinkStateDirectory", SecureStateTests().testRejectsSymlinkStateDirectory),
    ("testRejectsPublicStateDirectoryWithoutChangingItsPermissions", SecureStateTests().testRejectsPublicStateDirectoryWithoutChangingItsPermissions),
    ("testRejectsJournalSymlinkWithoutReadingOrChangingTarget", SecureStateTests().testRejectsJournalSymlinkWithoutReadingOrChangingTarget),
    ("testRejectsFifoWithoutBlocking", SecureStateTests().testRejectsFifoWithoutBlocking),
    ("testRejectsHardLinkedJournal", SecureStateTests().testRejectsHardLinkedJournal),
    ("testOversizedJournalCannotCauseRecoveryMutation", SecureStateTests().testOversizedJournalCannotCauseRecoveryMutation),
    ("testStateOperationsStayAnchoredWhenPathIsReplaced", SecureStateTests().testStateOperationsStayAnchoredWhenPathIsReplaced),
    ("testNewJournalIsPrivateAndAtomicReplacementLeavesNoTemporaryFiles", SecureStateTests().testNewJournalIsPrivateAndAtomicReplacementLeavesNoTemporaryFiles),
    ("testIdleAndUnknownDeadlinesUseElapsedTime", CameraPolicyTests().testIdleAndUnknownDeadlinesUseElapsedTime),
    ("testPrivateFileHelperRejectsUnsafeLockFilesAndNames", SecureStateTests().testPrivateFileHelperRejectsUnsafeLockFilesAndNames),
    ("testPartialMuteFailureRetainsBaselineAndRecovers", MuteSessionFaultTests().testPartialMuteFailureRetainsBaselineAndRecovers),
    ("testPostMuteReadFailureKeepsRecordForRecovery", MuteSessionFaultTests().testPostMuteReadFailureKeepsRecordForRecovery),
    ("testRecoveryAudioReadFailureDoesNotDiscardJournalOrOwnership", MuteSessionFaultTests().testRecoveryAudioReadFailureDoesNotDiscardJournalOrOwnership),
    ("testJournalLoadFailureDoesNotWriteAudioOrForgetOwnership", MuteSessionFaultTests().testJournalLoadFailureDoesNotWriteAudioOrForgetOwnership),
    ("testFailedJournalRemovalAfterRestoreCanRetryWithoutRepeatedAudioWrite", MuteSessionFaultTests().testFailedJournalRemovalAfterRestoreCanRetryWithoutRepeatedAudioWrite),
    ("testObservedUserOverrideSurvivesJournalRemovalFailure", MuteSessionFaultTests().testObservedUserOverrideSurvivesJournalRemovalFailure),
    ("testInvalidRecoveryRecordVersionAndRangeNeverWriteAudio", MuteSessionFaultTests().testInvalidRecoveryRecordVersionAndRangeNeverWriteAudio),
]
do {
    for (name, run) in tests {
        try run()
        print("PASS \(name)")
    }
    print("\(tests.count) tests passed")
} catch {
    fputs("FAIL: \(error)\n", stderr); exit(1)
}
