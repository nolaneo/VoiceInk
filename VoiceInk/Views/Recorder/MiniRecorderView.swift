import SwiftUI

struct MiniRecorderView<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: MiniWindowManager
    @EnvironmentObject private var enhancementService: AIEnhancementService

    // MARK: - Layout Constants

    private let controlBarHeight: CGFloat = 40
    private let compactWidth: CGFloat = 184
    private let compactCornerRadius: CGFloat = 20

    private var controlBar: some View {
        RecorderStatusDisplay(
            currentState: stateProvider.recordingState,
            audioMeter: recorder.audioMeter
        )
        .frame(maxWidth: .infinity)
        .frame(height: controlBarHeight)
    }

    var body: some View {
        if windowManager.isVisible {
            controlBar
                .frame(width: compactWidth)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: compactCornerRadius, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}
