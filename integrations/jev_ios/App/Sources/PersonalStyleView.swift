import SwiftUI
import UniformTypeIdentifiers

struct PersonalStyleView: View {
    @EnvironmentObject var model: AppModel
    @State private var samples = ""
    @State private var style = ""
    @State private var enabled = false
    @State private var busy = false
    @State private var message = ""
    @State private var importing = false
    @State private var task: Task<Void, Never>?
    @State private var revision = 0

    var body: some View {
        Form {
            Section("我的表达样本") {
                Text("粘贴聊天片段，或导入 UTF-8 文本文件。每条本人消息以“我：”开头，至少 5 条。只提取并发送这些本人消息，不发送其他人的消息。")
                    .font(.footnote)
                TextEditor(text: $samples).frame(minHeight: 150)
                    .accessibilityIdentifier("styleSamples")
                Button("导入文本文件") { importing = true }.disabled(busy)
                Text("样本仅保留在当前页面；离开后清空。点下方按钮会发送本人消息到已配置的回复接口，并产生用量。")
                    .font(.caption).foregroundStyle(Palette.secondary)
                Button("用 AI 提炼我的风格") { learn() }.disabled(busy || samples.trimmed.isEmpty)
                if busy { HStack { ProgressView(); Button("取消") { cancel(); message = "已取消，未保存风格" } } }
            }
            Section("个人风格 Skill") {
                Toggle("生成回复时使用我的风格", isOn: $enabled)
                TextEditor(text: $style).frame(minHeight: 220)
                    .accessibilityIdentifier("personalStyleEditor")
                Text("先查看提炼结果，可直接修改。保存后用于候选生成、改写和排序；不改变军师的事实判断与策略。已有风格会在新结果保存前保留。")
                    .font(.caption).foregroundStyle(Palette.secondary)
                Button(model.store?.isShared == true ? "保存并应用到键盘" : "保存到主 App") { save() }.disabled(busy || model.store == nil)
                    .buttonStyle(BrandPrimaryButtonStyle())
                Button("清除已保存的风格", role: .destructive) {
                    style = ""; enabled = false; save()
                }.disabled(busy || model.store == nil)
            }
            Section { Text(message).font(.footnote).textSelection(.enabled) }
        }
        .scrollContentBackground(.hidden).background(Palette.cream)
        .onAppear {
            let config = model.store?.config() ?? model.config
            style = config.personalStyle ?? ""; enabled = config.personalStyleEnabled == true
        }
        .onDisappear { cancel(); samples = "" }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 120_000 else {
                    throw GoutouError.invalid("请导入 120 KB 以内的 UTF-8 文本文件")
                }
                let data = try Data(contentsOf: url)
                guard data.count <= 120_000, let text = String(data: data, encoding: .utf8), text.count <= 30_000 else {
                    throw GoutouError.invalid("请使用 30000 字以内的 UTF-8 文本")
                }
                samples = text; message = "已导入，请检查“我：”的身份标注"
            } catch { message = error.localizedDescription }
        }
    }
    private func cancel() { revision += 1; task?.cancel(); task = nil; busy = false }
    private func learn() {
        do {
            _ = try PersonalStyleLearning.samples(samples)
            let config = model.store?.config() ?? model.config
            let name = config.reply == .deepseek ? "deepseek" : "openrouter"
            let key = try CredentialVault.read(name)
            var secrets = ProviderSecrets()
            if config.reply == .deepseek { secrets.deepseek = key } else { secrets.openrouter = key }
            _ = try secrets.key(config.reply)
            let api = ModelAPI(transport: model.transport, config: config, secrets: secrets)
            cancel()
            let generation = revision, snapshot = samples
            busy = true; message = "正在提炼…使用配置页已保存的回复接口"
            task = Task { @MainActor in
                do {
                    let output = try await PersonalStyleLearning.distill(snapshot, api: api)
                    try Task.checkCancellation()
                    guard generation == revision else { return }
                    style = output; enabled = true
                    message = "提炼完成，请检查后保存"
                } catch {
                    guard generation == revision else { return }
                    message = error is CancellationError ? "已取消" : error.localizedDescription
                }
                busy = false
            }
        } catch { message = error.localizedDescription }
    }
    private func save() {
        do {
            guard let store = model.store else { throw GoutouError.invalid("共享配置未连接") }
            guard !enabled || !style.trimmed.isEmpty else { throw GoutouError.invalid("请先提炼或填写风格内容") }
            var config = store.config()
            config.personalStyle = style.trimmed; config.personalStyleEnabled = enabled
            try store.saveConfig(config); model.reload()
            message = enabled
                ? (store.isShared ? "已保存；键盘连接共享配置后将使用你的风格" : "已保存到主 App；键盘共享尚未连接")
                : "已保存；个人风格已关闭"
        } catch { message = error.localizedDescription }
    }
}
