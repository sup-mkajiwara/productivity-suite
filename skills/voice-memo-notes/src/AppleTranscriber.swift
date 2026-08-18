// macOS 標準の音声認識（Speech framework）で音声ファイルを文字起こしする。
//
// 使い方:
//   AppleTranscriber <音声ファイル> <出力テキスト> [ロケール] [チャンク秒]
//
// 完了すると <出力テキスト>.done に終了コードを書く（呼び出し側はこれを待つ）。
//   0 = 成功 / 2 = 認識器を作れない / 3 = 音声認識が未許可 / 4 = 音声の読み込み失敗 / 5 = 認識結果が空
//
// 長い音声を一度に渡すと末尾しか返らないため、一定秒数ごとに分割して順に認識する。
// 分割は AVFoundation で行うので ffmpeg などの外部コマンドは不要。

import Foundation
import AVFoundation
import Speech

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("使い方: AppleTranscriber <音声> <出力txt> [ロケール] [チャンク秒]\n".data(using: .utf8)!)
    exit(64)
}

let audioURL = URL(fileURLWithPath: args[1])
let outPath = args[2]
let donePath = outPath + ".done"
let localeID = args.count >= 4 ? args[3] : "ja-JP"
let chunkSeconds = args.count >= 5 ? (Double(args[4]) ?? 45.0) : 45.0

// 進捗ログ。`open -n` で起動されると標準エラーがどこにも届かないため、
// 出力テキストの隣に .log として書き出す（呼び出し側がこれをログへ転記する）
let notePath = outPath + ".log"
func note(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    let line = message + "\n"
    if let fh = FileHandle(forWritingAtPath: notePath) {
        fh.seekToEndOfFile()
        fh.write(line.data(using: .utf8)!)
        fh.closeFile()
    } else {
        try? line.write(toFile: notePath, atomically: true, encoding: .utf8)
    }
}

func finish(_ text: String, _ code: Int32) -> Never {
    if !text.isEmpty {
        try? text.write(toFile: outPath, atomically: true, encoding: .utf8)
    }
    try? "\(code)".write(toFile: donePath, atomically: true, encoding: .utf8)
    exit(code)
}

// 一定秒数ごとに分割して一時ファイルへ書き出す
func splitAudio(_ url: URL, chunk: Double) throws -> (dir: URL, files: [URL]) {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let framesPerChunk = AVAudioFrameCount(max(chunk, 5.0) * format.sampleRate)

    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("apple-transcriber-\(ProcessInfo.processInfo.processIdentifier)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    var files: [URL] = []
    var index = 0
    while file.framePosition < file.length {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerChunk) else { break }
        try file.read(into: buffer, frameCount: framesPerChunk)
        if buffer.frameLength == 0 { break }
        let out = dir.appendingPathComponent(String(format: "chunk-%04d.caf", index))
        let outFile = try AVAudioFile(forWriting: out, settings: format.settings)
        try outFile.write(from: buffer)
        files.append(out)
        index += 1
    }
    return (dir, files)
}

// 1チャンクを認識する。コールバックは RunLoop 経由で配送されるため、
// セマフォで待つとデッドロックする点に注意（RunLoop を回して待つ）。
func recognize(_ recognizer: SFSpeechRecognizer, _ url: URL, timeout: TimeInterval) -> String? {
    let request = SFSpeechURLRecognitionRequest(url: url)
    request.requiresOnDeviceRecognition = true   // 音声を外部に送らない
    request.shouldReportPartialResults = false
    if #available(macOS 13, *) { request.addsPunctuation = true }

    var text: String? = nil
    var failed = false
    recognizer.recognitionTask(with: request) { result, error in
        if error != nil { failed = true; return }
        if let result = result, result.isFinal {
            text = result.bestTranscription.formattedString
        }
    }

    let deadline = Date().addingTimeInterval(timeout)
    while text == nil && !failed && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
    return failed ? nil : text
}

// --- 認証 ---
// CLI から直接起動すると許可主体が親プロセスになり許可が下りない。
// このバイナリは .app バンドルとして `open -n` 経由で起動される前提。
if SFSpeechRecognizer.authorizationStatus() != .authorized {
    var done = false
    SFSpeechRecognizer.requestAuthorization { _ in done = true }
    let deadline = Date().addingTimeInterval(90)
    while !done && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
    }
}
guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
    note("音声認識が許可されていません")
    finish("", 3)
}

guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)) else {
    note("ロケール \(localeID) の認識器を作れませんでした")
    finish("", 2)
}
if !recognizer.supportsOnDeviceRecognition {
    // オンデバイス非対応のロケールでは音声が外部に送られる恐れがあるため中断する
    note("ロケール \(localeID) はオンデバイス認識に対応していません")
    finish("", 2)
}

// --- 分割して順に認識 ---
let started = Date()
var chunkDir: URL? = nil
do {
    let (dir, chunks) = try splitAudio(audioURL, chunk: chunkSeconds)
    chunkDir = dir
    note("分割数: \(chunks.count)（\(Int(chunkSeconds))秒ごと）")

    var parts: [String] = []
    for (i, chunk) in chunks.enumerated() {
        // 認識が固まった場合に全体が止まらないよう、チャンク長に応じた上限を設ける
        guard let text = recognize(recognizer, chunk, timeout: max(120, chunkSeconds * 4)) else {
            note("チャンク \(i + 1)/\(chunks.count): 認識に失敗（この区間は飛ばします）")
            continue
        }
        note("チャンク \(i + 1)/\(chunks.count): \(text.count)文字")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append(trimmed) }
    }

    if let dir = chunkDir { try? FileManager.default.removeItem(at: dir) }

    let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
    note("処理時間: \(elapsed)秒")

    if parts.isEmpty {
        note("認識結果が空でした")
        finish("", 5)
    }
    finish(parts.joined(separator: "\n") + "\n", 0)
} catch {
    if let dir = chunkDir { try? FileManager.default.removeItem(at: dir) }
    note("音声の読み込み/分割に失敗しました: \(error.localizedDescription)")
    finish("", 4)
}
