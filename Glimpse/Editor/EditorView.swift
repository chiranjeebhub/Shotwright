import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @ObservedObject var model: EditorModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(model: model)
            Divider()
            canvasArea
            Divider()
            bottomBar
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 760, minHeight: 480)
        .background(hiddenShortcuts)
    }

    // MARK: Canvas

    private var canvasArea: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                AnnotationCanvas(model: model)
                    .padding(24)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }
            .background(Color(nsColor: .underPageBackgroundColor))
            .overlay(alignment: .top) {
                if model.tool == .crop, model.cropRect != nil {
                    cropBar.padding(.top, 12)
                }
            }
            .onAppear {
                let size = model.canvasSize
                let fit = min(1, (geometry.size.width - 48) / size.width, (geometry.size.height - 48) / size.height)
                model.zoom = max(0.1, fit)
            }
        }
    }

    private var cropBar: some View {
        HStack(spacing: 8) {
            Button("Cancel") { model.cancelCrop() }
            Button("Apply Crop") { model.applyCrop() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 4)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Text("\(model.image.width) × \(model.image.height) px")
            Text("·").foregroundStyle(.tertiary)
            HStack(spacing: 2) {
                Button { setZoom(model.zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                    .keyboardShortcut("-")
                    .help("Zoom Out")
                Text("Zoom \(Int((model.zoom * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(minWidth: 72)
                Button { setZoom(model.zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                    .keyboardShortcut("=")
                    .help("Zoom In")
                Button("Actual Size") { setZoom(1) }
                    .keyboardShortcut("0")
                    .labelsHidden()
                    .opacity(0)
                    .frame(width: 0)
                    .accessibilityHidden(true)
            }
            .buttonStyle(.borderless)

            Spacer()

            Button("Copy") { copy() }
                .keyboardShortcut("c")
                .disabled(model.editingText != nil)
            Button("Save As…") { saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Upload") { Toast.show("Cloud upload is coming in a later version") }
            Button("Save") { save() }
                .keyboardShortcut("s")
                .buttonStyle(.borderedProminent)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var hiddenShortcuts: some View {
        Group {
            Button("Delete") { model.deleteSelection() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(model.editingText != nil || model.selectedID == nil)
            Button("Escape") {
                if model.editingText != nil { model.commitText() }
                else if model.cropRect != nil { model.cancelCrop() }
                else { model.selectedID = nil }
            }
            .keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: Actions

    private func setZoom(_ value: CGFloat) {
        model.zoom = min(4, max(0.1, value))
    }

    private func copy() {
        guard model.applyToCapture() else { return }
        Clipboard.copy(model.capture)
        Toast.show("Copied to clipboard")
    }

    private func save() {
        guard model.applyToCapture() else { return }
        do {
            if let url = model.capture.savedURL {
                try ImageExporter.write(model.capture, to: url)
            } else {
                try ImageExporter.save(model.capture)
            }
            Toast.show("Saved")
            close()
        } catch {
            CaptureCoordinator.shared.present(error)
        }
    }

    private func saveAs() {
        guard model.applyToCapture() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.nameFieldStringValue = ImageExporter.filename(for: model.capture.date)
        panel.directoryURL = AppSettings.saveDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ImageExporter.write(model.capture, to: url)
            model.capture.savedURL = url
            Toast.show("Saved")
        } catch {
            CaptureCoordinator.shared.present(error)
        }
    }
}

// MARK: - Toolbar

private struct EditorToolbar: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                ToolButton(tool: .select, model: model)
                ToolButton(tool: .crop, model: model)
                Rectangle().fill(.separator).frame(width: 1, height: 18).padding(.horizontal, 4)
                ForEach(Tool.drawing) { ToolButton(tool: $0, model: model) }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))

            HStack(spacing: 6) {
                ForEach(EditorModel.palette, id: \.name) { swatch in
                    Button { model.color = swatch.color } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .padding(2)
                            .overlay(Circle().stroke(model.color == swatch.color ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .help(swatch.name)
                    .accessibilityLabel(swatch.name)
                }
            }

            HStack(spacing: 6) {
                Text("Size").font(.system(size: 12)).foregroundStyle(.secondary)
                Slider(value: $model.lineWidth, in: 1...12, step: 1)
                    .frame(width: 80)
                    .controlSize(.small)
            }

            Spacer()

            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .keyboardShortcut("z")
                .disabled(!model.canUndo)
                .help("Undo")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo)
                .help("Redo")
        }
        .buttonStyle(.borderless)
        .padding(.leading, 84) // clear the traffic lights
        .padding(.trailing, 14)
        .frame(height: 52)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ToolButton: View {
    let tool: Tool
    @ObservedObject var model: EditorModel

    var body: some View {
        let selected = model.tool == tool
        Button { model.tool = tool } label: {
            Image(systemName: tool.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .frame(width: 32, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? Color(nsColor: .controlBackgroundColor) : .clear)
                        .shadow(color: .black.opacity(selected ? 0.18 : 0), radius: 1, y: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tool.title)
        .accessibilityLabel(tool.title)
    }
}

// MARK: - Canvas

private struct AnnotationCanvas: View {
    @ObservedObject var model: EditorModel
    @FocusState private var textFocused: Bool

    var body: some View {
        let zoom = model.zoom
        let size = model.canvasSize
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                context.scaleBy(x: zoom, y: zoom)
                var shapes = model.annotations
                if let draft = model.draft { shapes.append(draft) }
                AnnotationRenderer.draw(in: &context, image: model.image, pixelated: model.pixelated,
                                        imageScale: model.scale, size: size, annotations: shapes)
                drawChrome(in: &context, size: size, zoom: zoom)
            }
            .frame(width: size.width * zoom, height: size.height * zoom)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        model.dragChanged(start: scaled(value.startLocation), location: scaled(value.location))
                    }
                    .onEnded { value in
                        model.dragEnded(start: scaled(value.startLocation), location: scaled(value.location))
                    }
            )
            .onContinuousHover { phase in
                if case .active = phase {
                    (model.tool == .select ? NSCursor.arrow : NSCursor.crosshair).set()
                }
            }

            if let editing = model.editingText {
                TextField("Text", text: Binding(
                    get: { model.editingText?.text ?? "" },
                    set: { model.editingText?.text = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: editing.fontSize * zoom, weight: .bold))
                .foregroundStyle(editing.color)
                .fixedSize()
                .frame(minWidth: 40, alignment: .leading)
                .offset(x: editing.start.x * zoom, y: editing.start.y * zoom)
                .focused($textFocused)
                .onSubmit { model.commitText() }
                .onAppear { textFocused = true }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    private func scaled(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / model.zoom, y: point.y / model.zoom)
    }

    /// Selection outline and crop shading. Not part of the exported image.
    private func drawChrome(in context: inout GraphicsContext, size: CGSize, zoom: CGFloat) {
        let hairline = 1 / zoom
        if let id = model.selectedID, let selected = model.annotations.first(where: { $0.id == id }) {
            context.stroke(Path(selected.bounds), with: .color(.accentColor),
                           style: StrokeStyle(lineWidth: hairline * 1.5, dash: [4 * hairline, 3 * hairline]))
        }
        if model.tool == .crop, let crop = model.cropRect {
            var shade = Path(CGRect(origin: .zero, size: size))
            shade.addRect(crop)
            context.fill(shade, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
            context.stroke(Path(crop), with: .color(.white), lineWidth: hairline)
        }
    }
}
