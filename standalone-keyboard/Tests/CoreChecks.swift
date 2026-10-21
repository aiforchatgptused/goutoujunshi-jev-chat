import Foundation

@main
struct CoreChecks {
    static var checks = 0
    static func check(_ name: String, _ condition: @autoclosure () throws -> Bool) throws {
        checks += 1
        if try !condition() { throw UserFailure("FAIL: " + name) }
    }
    static func rejects(_ name: String, _ operation: () throws -> Void) throws {
        do { try operation() } catch { checks += 1; return }
        throw UserFailure("FAIL: " + name)
    }
    static func main() throws {
        var config = KeyboardConfig(endpoint: "https://example.com/v1/", model: "test", apiKey: "test-key-not-real", style: "简短")
        try check("Preserve v1", config.completionURL().absoluteString == "https://example.com/v1/chat/completions")
        config.endpoint = "https://example.com/chat/completions"
        try check("Preserve complete URL", config.completionURL().absoluteString == config.endpoint)
        config.endpoint = "https://example.com"
        try check("Do not invent v1", config.completionURL().path == "/chat/completions")
        for endpoint in ["http://example.com", "https://user:secret@example.com", "https://example.com?a=key", "https://example.com/#key", "file:///tmp/key"] {
            var bad = config; bad.endpoint = endpoint
            try rejects("Reject unsafe endpoint") { _ = try bad.validated() }
        }
        var bad = config; bad.apiKey = ""
        try rejects("Missing key") { _ = try bad.validated() }
        bad.apiKey = "key\nvalue"
        try rejects("Header injection") { _ = try bad.validated() }
        bad = config; bad.version = 99
        try rejects("Unknown schema") { _ = try bad.validated() }
        try rejects("Oversize import") { _ = try KeyboardConfig.decode(Data(repeating: 65, count: 40001)) }
        let data = try JSONEncoder().encode(config)
        try check("Round trip config", KeyboardConfig.decode(data) == config)
        try rejects("Never send imported credentials as chat") { _ = try ReplyRules.messages(text: String(decoding: data, as: UTF8.self), style: "", test: false) }
        try rejects("Empty chat") { _ = try ReplyRules.messages(text: " ", style: "", test: false) }
        try check("Connection test excludes source and style", ReplyRules.messages(text: "PRIVATE CHAT", style: "PRIVATE STYLE", test: true) == [["role": "user", "content": "只回复：连接成功"]])
        let response = Data(#"{"choices":[{"message":{"content":"  好，晚点聊  "},"finish_reason":"stop"}]}"#.utf8)
        try check("Parse reply", ReplyRules.response(response) == "好，晚点聊")
        try rejects("Truncated response") { _ = try ReplyRules.response(Data(#"{"choices":[{"message":{"content":"hi"},"finish_reason":"length"}]}"#.utf8)) }
        try rejects("Malformed response") { _ = try ReplyRules.response(Data("{}".utf8)) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = ConfigStore(directory: dir)
        try check("Initially empty", first.load() == nil)
        try first.save(config)
        try check("Persists across new store", ConfigStore(directory: dir).load() == config)
        config.style = "更新后的风格"; try first.save(config)
        try check("Update replaces previous", ConfigStore(directory: dir).load()?.style == config.style)
        try first.delete()
        try check("Deletion persists", ConfigStore(directory: dir).load() == nil)
        print("PASS: \(checks) independent keyboard checks; no live API calls")
    }
}
