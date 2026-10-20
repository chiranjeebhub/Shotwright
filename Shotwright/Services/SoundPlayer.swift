import AppKit

enum SoundPlayer {
    private static let shutter: NSSound? = {
        let systemShutter = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        return NSSound(contentsOfFile: systemShutter, byReference: true) ?? NSSound(named: "Pop")
    }()

    static func playShutter() {
        shutter?.stop()
        shutter?.play()
    }
}
