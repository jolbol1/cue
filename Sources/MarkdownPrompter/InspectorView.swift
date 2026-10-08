import SwiftUI
import PrompterCore

enum InspectorTab: String, CaseIterable { case text = "Text", output = "Output" }

struct InspectorView: View {
    @Bindable var model: AppModel
    @AppStorage("Cue.InspectorTab") private var tab = InspectorTab.text

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $tab) {
                ForEach(InspectorTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 10)
            Form {
                switch tab {
                case .text: typography; readingArea
                case .output: display; marker
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder private var typography: some View {
        Section("Typography") {
            Picker("Font", selection: $model.settings.fontName) {
                ForEach(FontCatalog.recommended, id: \.self) { Text($0).tag($0) }
                Divider()
                ForEach(FontCatalog.otherFamilies, id: \.self) { Text($0).tag($0) }
                if !FontCatalog.recommended.contains(model.settings.fontName),
                   !FontCatalog.otherFamilies.contains(model.settings.fontName) {
                    Divider()
                    Text("\(model.settings.fontName) (unavailable)").tag(model.settings.fontName)
                }
            }
            SliderRow("Size", value: $model.settings.fontSize, in: 20...110, format: SliderRow.points)
            SliderRow("Line spacing", value: $model.settings.lineSpacing, in: 1...2, format: SliderRow.percent)
            SliderRow("Side margins", value: $model.settings.margin, in: 0.02...0.4, format: SliderRow.percent)
            ColorPicker("Text", selection: colorBinding(\.foreground), supportsOpacity: false)
            ColorPicker("Background", selection: colorBinding(\.background), supportsOpacity: false)
            Toggle("Include fenced code blocks", isOn: $model.settings.includeCode)
        }
    }

    @ViewBuilder private var readingArea: some View {
        Section {
            Toggle("Highlight reading area", isOn: $model.settings.highlight)
            SliderRow("Vertical centre", value: Binding(
                get: { ReadingBand.position(alignedTo: model.settings.readingPosition, rotated: model.settings.upsideDown) },
                set: { model.settings.readingPosition = ReadingBand.position(alignedTo: $0, rotated: model.settings.upsideDown) }
            ), in: 0...1, format: SliderRow.percent)
            SliderRow("Height", value: $model.settings.readingLines, in: 1...5) { String(format: "%.1f lines", $0) }
            SliderRow("Surrounding dimming", value: $model.settings.readingDimOpacity, in: 0...1, format: SliderRow.percent)
                .disabled(!model.settings.highlight)
            Button("Align Centre to Camera Marker", action: alignToMarker)
        } header: {
            Text("Reading Area")
        } footer: {
            Text("Dims the surrounding text so you stay on the lines you’re reading.")
        }
    }

    @ViewBuilder private var display: some View {
        Section {
            Picker("Display", selection: $model.settings.displayID) {
                ForEach(model.screens, id: \.displayID) { Text($0.localizedName).tag($0.displayID) }
            }
            Toggle("Mirror horizontally", isOn: $model.settings.mirror)
            Toggle("Rotate 180°", isOn: $model.settings.upsideDown)
            SliderRow("Brightness", value: $model.settings.dimming, in: 0.1...1, format: SliderRow.percent)
        } header: {
            Text("Output")
        } footer: {
            Text(model.screens.isEmpty
                 ? "No displays available. Relaunch Cue from Finder."
                 : "Brightness dims Cue’s output. It doesn’t change the display hardware.")
        }
    }

    @ViewBuilder private var marker: some View {
        Section {
            Toggle("Show marker", isOn: $model.settings.markerEnabled)
            Group {
                Picker("Style", selection: $model.settings.markerStyle) {
                    ForEach(MarkerStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                ColorPicker("Color & opacity", selection: colorBinding(\.markerColor))
                SliderRow("Size", value: $model.settings.markerSize, in: 10...100, format: SliderRow.points)
                SliderRow("Horizontal position", value: $model.settings.markerX, in: 0...1, format: SliderRow.percent)
                SliderRow("Vertical position", value: $model.settings.markerY, in: 0...1, format: SliderRow.percent)
            }
            .disabled(!model.settings.markerEnabled)
            Button("Align Reading Area to Marker", action: alignToMarker)
                .help("Centre the highlighted reading area vertically on the camera marker")
        } header: {
            Text("Camera Marker")
        } footer: {
            Text("Drag in the preview to place the marker over your camera lens.")
        }
    }

    private func alignToMarker() {
        model.settings.readingPosition = ReadingBand.position(alignedTo: model.settings.markerY, rotated: model.settings.upsideDown)
    }
    private func colorBinding(_ key: WritableKeyPath<Settings, RGBA>) -> Binding<Color> {
        Binding(get: { model.settings[keyPath: key].color }, set: { model.settings[keyPath: key] = RGBA($0) })
    }
}

/// A labelled slider with its current value, sized for narrow inspector and settings forms.
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: @escaping (Double) -> String) {
        self.title = title; _value = value; self.range = range; self.format = format
    }

    static let percent: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }
    static let points: (Double) -> String = { "\(Int($0)) pt" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(title) { Text(format(value)).monospacedDigit() }
            Slider(value: $value, in: range).labelsHidden()
        }
    }
}
