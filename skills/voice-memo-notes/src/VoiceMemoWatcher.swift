// launchd から起動される小さなラッパー。
//
// なぜ必要か:
//   ボイスメモの録音は ~/Library/Group Containers/... にあり、読むには
//   「フルディスクアクセス」が必要。この許可(TCC)はアプリバンドルに紐づくため、
//   launchd がシェルスクリプトを直接起動しても許可を与えられない。
//   このアプリに許可を与えると、ここから起動する子プロセス（文字起こしと要約の
//   スクリプト）も同じ権限で動くため、シェル全体に権限を広げずに済む。
//
// 使い方: launchd から `open -n -a VoiceMemoWatcher.app` で起動される。

import Foundation

let scriptPath = ("~/.claude/scripts/voice-memo-watch.sh" as NSString).expandingTildeInPath
let logPath = ("~/.claude/logs/voice-memo-notes.log" as NSString).expandingTildeInPath

func appendLog(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let line = "[\(stamp)] [watcher] \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
    } else {
        try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
    }
}

guard FileManager.default.isExecutableFile(atPath: scriptPath) else {
    appendLog("スクリプトが見つかりません: \(scriptPath)（install.sh を実行してください）")
    exit(1)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/zsh")
process.arguments = [scriptPath]
// 出力はスクリプト側が自分でログへ書くため、ここでは捨てる
process.standardOutput = FileHandle.nullDevice
process.standardError = FileHandle.nullDevice

do {
    try process.run()
} catch {
    appendLog("起動に失敗しました: \(error.localizedDescription)")
    exit(1)
}

process.waitUntilExit()
exit(process.terminationStatus)
