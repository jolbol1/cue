import SwiftUI
import AppKit

struct StageView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let url = model.selectedURL {
                preview.navigationDocument(url)
            } else {
                ContentUnavailableView {
                    Label("No Script Open", systemImage: "text.viewfinder")
                } description: {
                    Text("Choose a script in the sidebar, or open any Markdown file.")
                } actions: {
                    Button("Open Script…", action: model.chooseFile)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            TransportBar(model: model)
        }
    }

    private var preview: some View {
        VStack(spacing: 12) {
            PrompterPreview(model: model)
                .aspectRatio(model.canvasSize.width / max(1, model.canvasSize.height), contentMode: .fit)
                .clipShape(.rect(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary) }
                .overlay { previewMessage }
                .overlay(alignment: .topLeading) {
                    if model.isProjecting {
                        Text("LIVE")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.red, in: .capsule)
                            .padding(12)
                            .help("Showing on \(model.selectedScreen?.localizedName ?? "the output display")")
                    }
                }
                .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 6) {
                Image(systemName: "display")
                Text(verbatim: "\(model.selectedScreen?.localizedName ?? "No display") · \(Int(model.canvasSize.width)) × \(Int(model.canvasSize.height))")
                Text("—")
                Text("Drag in the preview to place the camera marker")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    @ViewBuilder private var previewMessage: some View {
        if model.blanked {
            Label("Output blacked out", systemImage: "eye.slash").foregroundStyle(.secondary)
        } else if model.blocks.isEmpty {
            Text("Nothing to read yet. Cue updates when you save the file.").foregroundStyle(.secondary)
        }
    }
}

private struct TransportBar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            Scrubber(model: model)
            HStack(spacing: 16) {
                HStack(spacing: 12) {
                    Button(action: model.rewind) { Label("Back to Start", systemImage: "backward.end.fill") }
                        .help("Back to start (⌃⌥⌘R)")
                    Button { model.nudge(-model.settings.fontSize * 3) } label: { Label("Back", systemImage: "gobackward") }
                        .help("Back three lines")
                    Button(action: model.togglePlayback) {
                        Label(playTitle, systemImage: playSymbol).labelStyle(.titleAndIcon).frame(minWidth: 70)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .help("Play or pause (⌃⌥⌘Space or the centre pedal)")
                    Button { model.nudge(model.settings.fontSize * 3) } label: { Label("Forward", systemImage: "goforward") }
                        .help("Forward three lines")
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .imageScale(.large)
                .disabled(model.blocks.isEmpty)
                .fixedSize()
                Spacer(minLength: 0)
                speedControl
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .overlay(alignment: .top) { Divider() }
    }

    private var playTitle: String { model.countdownRemaining > 0 ? "Cancel" : model.isPlaying ? "Pause" : "Play" }
    private var playSymbol: String { model.countdownRemaining > 0 ? "xmark" : model.isPlaying ? "pause.fill" : "play.fill" }

    // Collapses in narrow windows. A rigid minimum width here makes the split view's
    // column constraints unsatisfiable alongside the inspector, which crashes AppKit.
    private var speedControl: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                Image(systemName: "tortoise").foregroundStyle(.secondary)
                speedSlider.frame(width: 130)
                Image(systemName: "hare").foregroundStyle(.secondary)
                speedValue
                optionsMenu
            }
            HStack(spacing: 6) {
                speedSlider.frame(width: 80)
                speedValue
                optionsMenu
            }
            compactMenu
        }
    }

    private var speedSlider: some View {
        Slider(value: $model.settings.speed, in: 5...200).help("Constant playback speed")
    }

    private var speedValue: some View {
        Text(verbatim: "\(Int(model.settings.speed)) pt/s")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 58, alignment: .leading)
    }

    @ViewBuilder private var playbackOptions: some View {
        Picker("Count-In", selection: $model.settings.countdown) {
            Text("No Count-In").tag(0)
            Text("3-Second Count-In").tag(3)
            Text("5-Second Count-In").tag(5)
        }
        .pickerStyle(.inline)
        Divider()
        Toggle("Loop at End", isOn: $model.settings.loop)
    }

    private var optionsMenu: some View {
        Menu {
            playbackOptions
        } label: {
            Label("Playback Options", systemImage: "ellipsis.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .labelStyle(.iconOnly)
        .fixedSize()
        .help("Count-in and looping")
    }

    /// Fallback for the narrowest windows, so speed stays adjustable without the slider.
    private var compactMenu: some View {
        let presets = Set([15.0, 25, 35, 45, 60, 80, 100, 130, 160, 200, model.settings.speed]).sorted()
        return Menu {
            Picker("Speed", selection: $model.settings.speed) {
                ForEach(presets, id: \.self) { Text(verbatim: "\(Int($0)) pt/s").tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            playbackOptions
        } label: {
            Text(verbatim: "\(Int(model.settings.speed)) pt/s").font(.callout.monospacedDigit())
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .help("Playback speed, count-in and looping")
    }
}

/// Isolated so only this row re-renders as progress updates during playback.
private struct Scrubber: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            Text(model.progress, format: .percent.precision(.fractionLength(0)))
                .frame(width: 38, alignment: .leading)
            Slider(value: Binding(get: { model.progress }, set: { model.seek($0) }), in: 0...1)
                .controlSize(.small)
                .disabled(model.blocks.isEmpty)
            Text("−" + Duration.seconds(model.remainingSeconds.rounded()).formatted(.time(pattern: .minuteSecond)))
                .frame(width: 46, alignment: .trailing)
                .help("Time remaining at \(Int(model.settings.speed)) pt/s")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}
