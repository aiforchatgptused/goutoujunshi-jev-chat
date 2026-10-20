import SwiftUI

struct ProviderView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = AppConfig()
    @State private var deepseekKey = ""
    @State private var openrouterKey = ""
    @State private var jevKey = ""
    @State private var savedKeys = Set<String>()
    @State private var message = ""
    @State private var testing = false
    @State private var testTask: Task<Void, Never>?
    @State private var testRevision = 0

    var body: some View {
        Form {
            Section("策略判断与回复生成") {
                Picker("策略判断", selection: $draft.judge) { ForEach(JudgeProvider.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Picker("回复生成", selection: $draft.reply) { ForEach(ReplyProvider.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Button("判断＋回复均使用 DeepSeek") { draft.judge = .deepseek; draft.reply = .deepseek }
                Text("只用 DeepSeek 时只需配置 DeepSeek Key。策略先整理证据，再检查首 token 权重；缺失或不稳定时标注不可用。")
                    .font(.caption).foregroundStyle(Palette.secondary)
            }
            Section("DeepSeek / 兼容服务") {
                modelField("Base URL", value: Binding(get: { draft.deepseekEndpoint }, set: { draft.deepseekBaseURL = $0 }))
                modelField("模型 ID", value: $draft.deepseekModel)
                keyField("deepseek", value: $deepseekKey)
                testButton("测试 DeepSeek", provider: .deepseek)
            }
            Section("OpenRouter / 自定义兼容接口") {
                modelField("Base URL（保留服务商要求的 /v1）", value: Binding(get: { draft.openrouterEndpoint }, set: { draft.openrouterBaseURL = $0 }))
                modelField("回复模型 ID", value: $draft.openrouterModel)
                modelField("识图模型 ID（独立配置）", value: $draft.visionModel)
                keyField("openrouter", value: $openrouterKey)
                testButton("测试 OpenRouter 回复", provider: .openrouter)
                Text("识图模型须支持图片输入。模型 ID 可从服务商模型页复制；免费模型的可用性和限额由服务商决定。")
                    .font(.caption).foregroundStyle(Palette.secondary)
            }
            Section("TypeSafe Jev（选用）") {
                modelField("模型 ID", value: $draft.jevModel)
                keyField("jev", value: $jevKey)
                Button("测试 Jev 判断") { testJev() }.disabled(testing)
            }
            Section("接口兼容性") {
                Toggle("请求 JSON 模式（服务商支持时开启）", isOn: Binding(get: { draft.requestJSONMode == true }, set: { draft.requestJSONMode = $0 }))
                Button("判断和回复使用自定义接口") { draft.reply = .openrouter; draft.judge = .reply }
                Text("兼容 OpenAI Chat Completions 协议。可填 Base URL 或完整 /chat/completions 地址；不会擅自添加 /v1。测试只检查文字回复，不要求 JSON 模式或策略 token 权重。")
                    .font(.caption).foregroundStyle(Palette.secondary)
            }
            Section("截图识别") {
                Picker("识别方式", selection: $draft.ocr) { ForEach(OCRProvider.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                Text("Apple Vision 在手机本地识别。云端识图会发送你选的截图，使用对应服务的 Key 并产生用量；键盘自身不截屏，日常拼音和英文输入在本机完成。")
                    .font(.caption).foregroundStyle(Palette.secondary)
            }
            Section("回复偏好") {
                Picker("口吻", selection: $draft.tone) { ForEach(["稳健", "会撩", "直接"], id: \.self) { Text($0).tag($0) } }
                Picker("长度", selection: $draft.length) { ForEach(["简短", "适中", "详细"], id: \.self) { Text($0).tag($0) } }
                Stepper("最多 \(draft.count) 条候选", value: $draft.count, in: 1...3)
            }
            Section {
                Button("保存并应用配置") { save() }.buttonStyle(BrandPrimaryButtonStyle())
                    .disabled(testing || model.store == nil).accessibilityIdentifier("saveConfigButton")
                if testing { HStack { ProgressView(); Button("取消测试") { cancelTest(); message = "已取消" } } }
                Text(message).font(.footnote).foregroundStyle(Palette.secondary).textSelection(.enabled)
            } footer: {
                Text(CredentialVault.storageStatus + "。已存 Key 不回显；空白表示保留。兼容模式的文件不是钥匙串，受 iOS 文件保护并排除备份。聊天仅在你确认分析时发送。")
            }
            Section("本地数据") {
                Button("清除键盘暂存与等待取用的内容") {
                    model.store?.clearHandoff(); model.store?.captureMailbox.clear(); model.store?.clearKeyboardSession()
                    message = "已清除键盘本轮暂存、临时交接与截屏内容"
                }
                Button("清空本轮原文与结果") { model.transcript = ""; model.invalidate(clear: true); message = "已清空本轮" }
            }
        }
        .scrollContentBackground(.hidden).background(Palette.cream)
        .onAppear { draft = model.config; refreshKeys() }
        .onDisappear { cancelTest(); deepseekKey = ""; openrouterKey = ""; jevKey = "" }
    }

    private func cancelTest() {
        testRevision += 1; testTask?.cancel(); testTask = nil; testing = false
    }
    private func modelField(_ title: String, value: Binding<String>) -> some View {
        TextField(title, text: value).textInputAutocapitalization(.never).autocorrectionDisabled()
    }
    private func keyField(_ name: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField(savedKeys.contains(name) ? "已配置，填写新 Key 可替换" : "填写 API Key", text: value)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier(name + "KeyField")
            if savedKeys.contains(name) {
                Button("删除此服务的 Key", role: .destructive) {
                    do { try CredentialVault.delete(name); value.wrappedValue = ""; refreshKeys(); model.cancel(); message = "已删除此服务的 Key" }
                    catch { message = error.localizedDescription }
                }.font(.caption)
            }
        }
    }
    private func refreshKeys() {
        do {
            savedKeys = []
            for name in CredentialVault.services where !(try CredentialVault.read(name)).isEmpty { savedKeys.insert(name) }
        } catch { message = error.localizedDescription }
    }
    private func secrets(for provider: ReplyProvider? = nil, jevOnly: Bool = false) throws -> ProviderSecrets {
        // Resolve only the tested service and prefer the unsaved field. A broken
        // shared-keychain entry must never block a valid freshly entered test key.
        var result = ProviderSecrets()
        func key(_ typed: String, _ name: String) throws -> String {
            typed.trimmed.isEmpty ? try CredentialVault.read(name) : typed.trimmed
        }
        if jevOnly { result.jev = try key(jevKey, "jev") }
        else if provider == .deepseek { result.deepseek = try key(deepseekKey, "deepseek") }
        else if provider == .openrouter { result.openrouter = try key(openrouterKey, "openrouter") }
        return result
    }
    private func save() {
        do {
            try draft.validate()
            _ = try ModelAPI.chatURL(draft.deepseekEndpoint)
            _ = try ModelAPI.chatURL(draft.openrouterEndpoint)
            guard let store = model.store else { throw GoutouError.invalid("App Group 未连接") }
            for (name, value) in [("deepseek", deepseekKey), ("openrouter", openrouterKey), ("jev", jevKey)] where !value.trimmed.isEmpty {
                try CredentialVault.write(value, name: name)
            }
            try store.saveConfig(draft)
            deepseekKey = ""; openrouterKey = ""; jevKey = ""
            refreshKeys(); model.reload(); message = "已保存，下一次键盘分析使用新配置。"
        } catch { message = error.localizedDescription }
    }
    private func testButton(_ title: String, provider: ReplyProvider) -> some View {
        Button(title) {
            do {
                let api = ModelAPI(transport: model.transport, config: draft, secrets: try secrets(for: provider))
                cancelTest()
                let generation = testRevision
                testing = true; message = "连接测试中，会产生少量接口用量…"
                testTask = Task {
                    do {
                        try await api.test(provider); try Task.checkCancellation()
                        guard testRevision == generation else { return }
                        message = "文字生成测试成功。请点“保存并应用配置”；策略分析、识图和键盘需分别验证。"
                    } catch {
                        guard testRevision == generation else { return }
                        message = error is CancellationError ? "已取消" : error.localizedDescription
                    }
                    testing = false
                }
            } catch { message = error.localizedDescription }
        }.disabled(testing)
    }
    private func testJev() {
        do {
            let api = ModelAPI(transport: model.transport, config: draft, secrets: try secrets(jevOnly: true))
            cancelTest()
            let generation = testRevision
            testing = true; message = "测试 Jev 判断中，会产生接口用量…"
            testTask = Task {
                do {
                    _ = try await GoutouPipeline(api: api).jevDecision("连接测试。对方说今天工作忙，用户希望自然接话。")
                    try Task.checkCancellation()
                    guard testRevision == generation else { return }
                    message = "Jev 策略接口连接成功。"
                } catch {
                    guard testRevision == generation else { return }
                    message = error is CancellationError ? "已取消" : error.localizedDescription
                }
                testing = false
            }
        } catch { message = error.localizedDescription }
    }
}

struct RelationshipView: View {
    @EnvironmentObject var model: AppModel
    @State private var draft = Relationship(id: "current")
    @State private var archive = false
    @State private var profiles = [Relationship]()
    @State private var message = ""
    @State private var deleteAll = false

    var body: some View {
        Form {
            Section {
                TextField("称呼或代号", text: $draft.label)
                Picker("关系阶段", selection: $draft.stage) { ForEach(Relationship.stages, id: \.self) { Text($0).tag($0) } }
                Picker("本轮目标", selection: $draft.goal) { ForEach(Relationship.goals, id: \.self) { Text($0).tag($0) } }
                TextField("最近发生了什么（最多 200 字）", text: $draft.background, axis: .vertical).lineLimit(3...6)
                TextField("需要遵守的边界或备注（最多 200 字）", text: $draft.notes, axis: .vertical).lineLimit(2...4)
                Toggle("同时保存为可切换的对象档案", isOn: $archive)
                Button("保存当前对象与目标") {
                    do {
                        guard let store = model.store else { throw GoutouError.invalid("共享配置未连接") }
                        try store.saveRelationship(draft, archive: archive); model.reload(); profiles = store.archived()
                        message = "已保存；下次分析前请核对聊天对象。"
                    } catch { message = error.localizedDescription }
                }.buttonStyle(BrandPrimaryButtonStyle())
                Text(message).font(.footnote).foregroundStyle(Palette.secondary)
            } header: {
                Text("当前对象")
            } footer: {
                Text("只保存你主动填写的对象资料，不保存整份聊天。分析时会把当前对象的阶段、目标、背景与本轮原文交给所选模型。键盘无法自动识别聊天对象，换会话后请手动选择。")
            }
            Section("已保存的对象") {
                Button("新建对象") { draft = Relationship(); archive = true }
                ForEach(profiles) { profile in
                    Button { draft = profile; archive = true; message = "已载入，点保存后应用到键盘。" } label: {
                        VStack(alignment: .leading) { Text(profile.label); Text(profile.stage + " · " + profile.goal).font(.caption).foregroundStyle(Palette.secondary) }
                    }
                }.onDelete { indices in
                    do {
                        guard let store = model.store else { return }
                        for index in indices { try store.deleteProfile(profiles[index].id) }
                        profiles = store.archived(); model.reload(); draft = model.relationship
                    } catch { message = error.localizedDescription }
                }
                Button("删除所有对象资料", role: .destructive) { deleteAll = true }
            }
        }.scrollContentBackground(.hidden).background(Palette.cream)
            .onAppear { draft = model.relationship; profiles = model.store?.archived() ?? [] }
            .confirmationDialog("删除所有本机对象资料？", isPresented: $deleteAll, titleVisibility: .visible) {
                Button("删除所有资料", role: .destructive) { model.store?.clearProfiles(); model.reload(); draft = model.relationship; profiles = [] }
            }
    }
}
