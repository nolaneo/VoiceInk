import SwiftUI

struct NotchRecorderView<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @EnvironmentObject var windowManager: NotchWindowManager
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    @State private var activePopover: ActivePopoverState = .none

    // MARK: - Display State

    private enum DisplayState: Equatable {
        case collapsed
        case active
        case liveText
    }

    private var displayState: DisplayState {
        switch stateProvider.recordingState {
        case .recording:
            return stateProvider.partialTranscript.isEmpty ? .active : .liveText
        case .transcribing, .enhancing:
            return .active
        default:
            return .collapsed
        }
    }

    // MARK: - Screen Geometry

    private var notchWidth: CGFloat {
        guard let screen = NSScreen.main else { return 180 }
        if let left = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width {
            return screen.frame.width - left - right
        }
        return 180
    }

    private var notchHeight: CGFloat {
        guard let screen = NSScreen.main else { return 37 }
        if screen.safeAreaInsets.top > 0 { return screen.safeAreaInsets.top }
        return NSApplication.shared.mainMenu?.menuBarHeight ?? NSStatusBar.system.thickness
    }

    // MARK: - Layout Constants

    private let activePillWidth: CGFloat = 85
    private let activePillHeight: CGFloat = 25
    private let transcriptSideExpansion: CGFloat = 110
    private let transcriptPanelHeight: CGFloat = 57

    private var mainRowHeight: CGFloat {
        displayState == .liveText ? notchHeight + 6 : activePillHeight
    }

    // MARK: - Pill Dimensions

    private var pillWidth: CGFloat {
        switch displayState {
        case .collapsed: return notchWidth
        case .active:    return activePillWidth
        case .liveText:  return notchWidth + transcriptSideExpansion * 2
        }
    }

    private var pillHeight: CGFloat {
        switch displayState {
        case .collapsed: return 0
        case .active:    return activePillHeight
        case .liveText:  return mainRowHeight + transcriptPanelHeight
        }
    }

    // MARK: - Animation

    private let expandAnimation = Animation.spring(response: 0.42, dampingFraction: 0.80)
    private let collapseAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0)

    private var pillAnimation: Animation {
        displayState == .collapsed ? collapseAnimation : expandAnimation
    }

    // MARK: - Body

    var body: some View {
        if windowManager.isVisible {
            GeometryReader { geo in
                pill.position(x: geo.size.width / 2, y: pillHeight / 2)
            }
            .animation(pillAnimation, value: displayState)
        }
    }

    // MARK: - Pill

    private var pill: some View {
        VStack(spacing: 0) {
            mainRow
            liveTextPanel
        }
        .frame(width: pillWidth, height: pillHeight)
        .background(Color.black)
        .clipShape(
            NotchShape(
                topCornerRadius: displayState == .liveText ? 12 : 8,
                bottomCornerRadius: displayState == .liveText ? 22 : 16
            )
        )
    }

    // MARK: - Main Row

    private var mainRow: some View {
        ZStack {
            Color.clear

            if displayState == .liveText {
                // Show buttons only in live text mode where there's more room
                HStack(spacing: 10) {
                    RecorderPromptButton(activePopover: $activePopover, buttonSize: 20, padding: EdgeInsets())
                    RecorderPowerModeButton(activePopover: $activePopover, buttonSize: 20, padding: EdgeInsets())
                    Spacer(minLength: 0)
                }
                .padding(.leading, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(expandAnimation.delay(0.09), value: displayState)
            }

            // Centered waveform / status display
            RecorderStatusDisplay(
                currentState: stateProvider.recordingState,
                audioMeter: recorder.audioMeter,
                menuBarHeight: notchHeight
            )
            .opacity(displayState != .collapsed ? 1 : 0)
            .animation(
                displayState != .collapsed ? expandAnimation.delay(0.09) : collapseAnimation,
                value: displayState
            )
        }
        .frame(height: mainRowHeight)
    }

    // MARK: - Live Text Panel

    private var liveTextPanel: some View {
        VStack(spacing: 0) {
            if displayState == .liveText {
                Divider().background(Color.white.opacity(0.15))
                LiveTranscriptView(text: stateProvider.partialTranscript)
                    .padding(.horizontal, 8)
            }
        }
        .frame(height: displayState == .liveText ? transcriptPanelHeight : 0)
        .clipped()
    }
}
