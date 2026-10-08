import SwiftUI
import AppKit

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            PedalSettings(model: model)
                .tabItem { Label("Pedal", systemImage: "rectangle.bottomthird.inset.filled") }
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "command") }
        }
        .frame(width: 520)
    }
}

private struct PedalSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Enable direct USB input", isOn: Binding(get: { model.settings.pedalEnabled }, set: model.setPedalEnabled))
                LabeledContent("Status", value: model.pedalStatus)
                HStack(spacing: 8) {
                    pedal(0, "Left", "Scroll back", symbol: "arrow.up")
                    pedal(1, "Centre", "Play / pause", symbol: "playpause.fill")
                    pedal(2, "Right", "Scroll forward", symbol: "arrow.down")
                }
                .padding(.vertical, 2)
            } header: {
                Text("Stream Deck Pedal")
            } footer: {
                Text("Works while you use other apps. Press a pedal to test it.")
            }
            Section {
                Picker("Scroll mode", selection: $model.settings.mode) {
                    ForEach(ScrollMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                SliderRow("Hold-to-scroll speed", value: $model.settings.pedalSpeed, in: 10...400) { "\(Int($0)) pt/s" }
            } footer: {
                Text("Hold a side pedal for precise movement. Play starts constant scrolling; the centre pedal toggles play and pause.")
            }
            Section {
                LabeledContent("Not responding?") {
                    HStack {
                        Button("Reconnect") { model.setPedalEnabled(true) }
                        Button("Input Monitoring…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                        }
                    }
                }
            } footer: {
                Text("Use an empty pedal profile in Stream Deck so its assigned actions don’t also run. Cue doesn’t change your Stream Deck settings.")
            }
        }
        .formStyle(.grouped)
        .frame(height: 580)
    }

    private func pedal(_ index: Int, _ title: String, _ action: String, symbol: String) -> some View {
        let pressed = model.pedalKeys[index]
        return VStack(spacing: 6) {
            Image(systemName: symbol).font(.title3)
            Text(title).font(.caption.weight(.semibold))
            Text(action).font(.caption2).foregroundStyle(pressed ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .foregroundStyle(pressed ? Color.white : .primary)
        .background(pressed ? Color.accentColor : Color.secondary.opacity(0.12), in: .rect(cornerRadius: 8))
        .animation(.easeOut(duration: 0.1), value: pressed)
        .accessibilityElement(children: .combine)
        .accessibilityValue(pressed ? "Pressed" : "Released")
    }
}

private struct ShortcutSettings: View {
    var body: some View {
        Form {
            Section {
                shortcut("Play / pause", "⌃⌥⌘Space")
                shortcut("Project / stop projection", "⌃⌥⌘P")
                shortcut("Blackout / show script", "⌃⌥⌘B")
                shortcut("Back to start", "⌃⌥⌘R")
                shortcut("Stop projection (pointer on output)", "Esc")
            } footer: {
                Text("These control Cue without switching away from your current app.")
            }
        }
        .formStyle(.grouped)
        .frame(height: 280)
    }

    private func shortcut(_ title: String, _ keys: String) -> some View {
        LabeledContent(title) { Text(keys).monospaced() }
    }
}
