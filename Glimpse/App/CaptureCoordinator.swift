import AppKit
import ScreenCaptureKit

/// Entry point for every capture action, whether it comes from the menu or a hotkey.
@MainActor
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    enum Purpose { case screenshot, ocr }

    private var selection: SelectionController?
    private var isPreparingSelection = false
    private var previousArea: (rect: CGRect, screen: NSScreen)?

    func captureArea() { startSelection(mode: .area, purpose: .screenshot) }
    func captureWindow() { startSelection(mode: .window, purpose: .screenshot) }
    func captureText() { startSelection(mode: .area, purpose: .ocr) }

    func captureFullscreen() {
        guard PermissionManager.ensureScreenCapture() else { return }
        Task {
            do {
                let capture = try await CaptureService.captureScreen(.underMouse)
                handle(capture, purpose: .screenshot)
            } catch {
                present(error)
            }
        }
    }

    func capturePreviousArea() {
        guard let previousArea, NSScreen.screens.contains(previousArea.screen) else {
            captureArea()
            return
        }
        guard PermissionManager.ensureScreenCapture() else { return }
        Task {
            do {
                let capture = try await CaptureService.captureArea(previousArea.rect, on: previousArea.screen)
                handle(capture, purpose: .screenshot)
            } catch {
                present(error)
            }
        }
    }

    private func startSelection(mode: SelectionController.Mode, purpose: Purpose) {
        guard selection == nil, !isPreparingSelection, PermissionManager.ensureScreenCapture() else { return }
        isPreparingSelection = true
        Task {
            defer { isPreparingSelection = false }
            let windows = (try? await CaptureService.selectableWindows()) ?? []
            // Freeze every screen first: the overlay shows these, the loupe magnifies
            // them, and area selections are cropped from them.
            var frozen: [CGDirectDisplayID: Capture] = [:]
            for screen in NSScreen.screens {
                do {
                    frozen[screen.displayID] = try await CaptureService.captureScreen(screen)
                } catch {
                    present(error)
                    return
                }
            }
            let controller = SelectionController(mode: mode, windows: windows, frozen: frozen) { [weak self] result in
                guard let self else { return }
                self.selection = nil
                guard let result else { return }
                Task { await self.performCapture(result, purpose: purpose) }
            }
            selection = controller
            controller.begin()
        }
    }

    private func performCapture(_ result: SelectionResult, purpose: Purpose) async {
        do {
            let capture: Capture
            switch result {
            case let .area(rect, screen, frozen):
                if purpose == .screenshot { previousArea = (rect, screen) }
                capture = try frozen.cropped(to: rect, screenHeight: screen.frame.height)
            case let .window(window):
                capture = try await CaptureService.captureWindow(window)
            }
            handle(capture, purpose: purpose)
        } catch {
            present(error)
        }
    }

    private func handle(_ capture: Capture, purpose: Purpose) {
        switch purpose {
        case .ocr:
            Task {
                do {
                    let text = try await TextRecognizer.recognize(capture.image)
                    if text.isEmpty {
                        Toast.show("No text found")
                    } else {
                        Clipboard.copy(text)
                        Toast.show("Text copied to clipboard")
                    }
                } catch {
                    present(error)
                }
            }
        case .screenshot:
            CaptureHistory.shared.add(capture)
            if AppSettings.playSound { SoundPlayer.playShutter() }
            if AppSettings.copyToClipboard { Clipboard.copy(capture) }
            if AppSettings.autoSave {
                do { capture.savedURL = try ImageExporter.save(capture) } catch { present(error) }
            }
            if AppSettings.showQuickAccess {
                QuickAccessManager.shared.show(capture)
            }
        }
    }

    func present(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        NSAlert(error: error).runModal()
    }
}
