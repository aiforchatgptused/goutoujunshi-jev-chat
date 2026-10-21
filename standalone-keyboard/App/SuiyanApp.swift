import SwiftUI
import UIKit

@main
struct SuiyanApp: App {
    var body: some Scene { WindowGroup { SetupView() } }
}
struct SetupView: View {
    @State private var endpoint = "https://api.deepseek.com"
    @State private var model = ""
    @State private var key = ""
    @State private var style = "简短、口语化，按我的表达习惯回复，不用客服腔。"
    @State private var testText = ""
    @State private var status = ""
    @State private var confirm = false
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section("独立键盘验证版 · 0.1.0 (1)") {
                    Text("配置由键盘独立保存，键盘直接调用 AI。无需 App Group、共享钥匙串或服务器。")
                    Text("这是 AI 回复面板，日常打字请切换系统键盘。")
                }
                Section("1 · 启用键盘") {
                    Text("iPhone 设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → 随言键盘，再开启允许完全访问。")
                }
                Section("2 · 准备配置") {
                    TextField("HTTPS Base URL 或完整 chat/completions", text: $endpoint).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused)
                    TextField("服务商实际提供的模型名称", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused)
                    SecureField("API Key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled().focused($focused)
                    Text("请按服务商填写；地址不会自动补 /v1。")
                    TextField("你的说话风格", text: $style, axis: .vertical).lineLimit(3...8).focused($focused)
                    Button("复制配置给键盘") { confirm = true }
                    Text("复制内容含 API Key，仅保留在本机剪贴板 90 秒。键盘确认导入后清除；App 不保存 Key。")
                }
                Section("3 · 在这里切换到随言键盘") {
                    TextField("点这里，再长按地球键切换键盘", text: $testText, axis: .vertical).lineLimit(3...6)
                    Text("首次点键盘内的“导入配置”，确认接口后保存，再点“测试连接”。以后修改配置时重复导入。")
                }
                Section("日常使用") {
                    Text("复制聊天文字 → 切换随言键盘 → 读取聊天 → 确认并生成 → 插入回复。不会自动读取或发送剪贴板，也不会自动发消息。")
                    Text("NAS 同步、截图识别和自动提炼风格尚未加入；本版先验证签名、持久保存、联网和插入回复。")
                }
                if !status.isEmpty { Section { Text(status) } }
            }
            .navigationTitle("随言键盘")
            .confirmationDialog("配置含 API Key，复制到本机剪贴板供键盘导入？", isPresented: $confirm, titleVisibility: .visible) {
                Button("复制，90 秒后过期") { copy() }
                Button("取消", role: .cancel) {}
            }
        }
    }
    private func copy() {
        do {
            let config = try KeyboardConfig(endpoint: endpoint, model: model.trimmingCharacters(in: .whitespacesAndNewlines), apiKey: key.trimmingCharacters(in: .whitespacesAndNewlines), style: style).validated()
            let data = try JSONEncoder().encode(config)
            guard let string = String(data: data, encoding: .utf8) else { throw UserFailure("无法编码配置") }
            UIPasteboard.general.setItems([["public.utf8-plain-text": string]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(90)])
            key = ""; focused = false
            status = "已复制。请立即切换到随言键盘，点导入配置。"
        } catch { status = error.localizedDescription }
    }
}
