import AppKit
import CoreGraphics
import CryptoKit
import ScreenCaptureKit
import Vision
import Darwin

struct WindowInfo: Codable {
    let app: String
    let bundleId: String
    let title: String
    let windowId: UInt32
    let pid: Int32
}

func json(_ object: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) { print(text) }
}

func activeWindow() -> WindowInfo? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let pid = app.processIdentifier
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
    let candidates = list.filter {
        ($0[kCGWindowOwnerPID as String] as? Int32) == pid &&
        ($0[kCGWindowLayer as String] as? Int) == 0 &&
        (($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0) != 0
    }
    guard let first = candidates.first,
          let number = (first[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { return nil }
    return WindowInfo(app: app.localizedName ?? "Unknown", bundleId: app.bundleIdentifier ?? "", title: first[kCGWindowName as String] as? String ?? "", windowId: number, pid: pid)
}

@available(macOS 14.0, *)
func captureWindow(_ info: WindowInfo, path: String) async throws -> [String: Any] {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let window = content.windows.first(where: { $0.windowID == info.windowId && $0.owningApplication?.processID == info.pid }) else {
        throw NSError(domain: "LocalMindCapture", code: 2, userInfo: [NSLocalizedDescriptionKey: "前台窗口当前不可见，已跳过截图"])
    }
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let config = SCStreamConfiguration()
    config.width = max(1, Int(window.frame.width))
    config.height = max(1, Int(window.frame.height))
    config.showsCursor = false
    config.captureResolution = .best
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    let rep = NSBitmapImageRep(cgImage: image)
    guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.58]) else {
        throw NSError(domain: "LocalMindCapture", code: 3, userInfo: [NSLocalizedDescriptionKey: "JPEG 压缩失败"])
    }
    try jpeg.write(to: URL(fileURLWithPath: path), options: .atomic)

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    try VNImageRequestHandler(cgImage: image).perform([request])
    let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    let text = lines.joined(separator: "\n")
    let digest = SHA256.hash(data: jpeg).map { String(format: "%02x", $0) }.joined()
    return ["app": info.app, "bundleId": info.bundleId, "title": info.title, "windowId": Int(info.windowId), "pid": Int(info.pid), "path": path, "ocrText": text, "sha256": digest, "bytes": jpeg.count]
}

func run() async {
    let args = CommandLine.arguments
    guard args.count >= 2 else { json(["error": "usage: localmind-capture status | capture <jpg-path>"]); return }
    guard let window = activeWindow() else { json(["error": "无法识别当前前台窗口"]); return }
    if args[1] == "status" {
        json(["app": window.app, "bundleId": window.bundleId, "title": window.title, "windowId": Int(window.windowId), "pid": Int(window.pid)])
        return
    }
    guard args[1] == "capture", args.count >= 3 else { json(["error": "missing output path"]); return }
    guard #available(macOS 14.0, *) else { json(["error": "屏幕采集需要 macOS 14 或更新版本"]); return }
    do { json(try await captureWindow(window, path: args[2])) }
    catch { json(["error": "窗口截图或 Vision OCR 失败：\(error.localizedDescription)；请检查屏幕录制权限"]); exit(EXIT_FAILURE) }
}

@main struct CaptureApp {
    static func main() async { await run() }
}
