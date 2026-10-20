import AppKit
import PDFKit

/// Carries out a wheel bubble on the dropped files. Work runs off the main thread; progress and results are toasts.
enum FileOperationRunner {
    static func run(_ operation: FileOperation, on urls: [URL]) {
        guard !urls.isEmpty else { return }
        if case .action(let action) = operation { return FileActions.perform(action, on: urls) }
        if case .tool(let tool) = operation, let handled = runOnMain(tool, urls) { return handled }

        Toast.show("\(operation.title)…", duration: 60)
        Task.detached(priority: .userInitiated) {
            do {
                let outputs = try await produce(operation, urls)
                await MainActor.run { report(outputs) }
            } catch {
                await MainActor.run { Toast.show(error.localizedDescription, duration: 3.5) }
            }
        }
    }

    /// Tools that open UI or only touch the clipboard; nil when the tool produces files.
    private static func runOnMain(_ tool: FileTool, _ urls: [URL]) -> Void? {
        switch tool {
        case .annotate:
            return CaptureCoordinator.shared.open(fileURL: urls[0])
        case .editVideo:
            return VideoEditorWindowController.open(url: urls[0], clicksURL: nil)
        case .copyText, .copyPDFText:
            Toast.show("Reading text…", duration: 30)
            DispatchQueue.global(qos: .userInitiated).async {
                let text = urls.map { url in
                    tool == .copyPDFText ? (PDFDocument(url: url)?.string ?? "") : ((try? ImageConversions.load(url)).map(TextRecognizer.recognize) ?? "")
                }.filter { !$0.isEmpty }.joined(separator: "\n\n")
                DispatchQueue.main.async {
                    if text.isEmpty { return Toast.show("No text found") }
                    Output.copy(text: text)
                    Toast.show("Copied text", detail: text)
                }
            }
            return ()
        default:
            return nil
        }
    }

    private static func produce(_ operation: FileOperation, _ urls: [URL]) async throws -> [URL] {
        switch operation {
        case .convert(let ext):
            var outputs: [URL] = []
            for url in urls {
                switch FileFamily.of(url) {
                case .image: outputs.append(try ImageConversions.convert(url, to: ext))
                case .video, .audio: outputs.append(try await MediaConversions.convert(url, to: ext))
                case .pdf: outputs.append(try DocumentConversions.convert(pdf: url, to: ext))
                case .document: outputs.append(try DocumentConversions.convert(document: url, to: ext))
                case .table: outputs.append(try DocumentConversions.convert(table: url, to: ext))
                default: break
                }
            }
            return outputs
        case .tool(let tool):
            switch tool {
            case .zip, .tarGz: return [try DocumentConversions.archive(urls, tarGz: tool == .tarGz)]
            case .extract: return try urls.map(DocumentConversions.extract)
            case .mergePDFs, .splitPDF, .rotatePDF, .compressPDF: return try DocumentConversions.run(tool, on: urls)
            case .compressVideo, .downscale720, .mute, .extractFrame:
                var outputs: [URL] = []
                for url in urls { outputs.append(try await MediaConversions.run(tool, on: url)) }
                return outputs
            default: return try ImageConversions.run(tool, on: urls)
            }
        case .action:
            return []
        }
    }

    private static func report(_ outputs: [URL]) {
        guard let first = outputs.first else { return Toast.show("Nothing to convert") }
        Toast.show(outputs.count == 1 ? "Saved \(first.lastPathComponent)" : "Saved \(outputs.count) files")
    }
}
