import UIKit

final class KeyboardController: UIInputViewController {
    private let stack = UIStackView()
    private let status = UILabel()
    private let source = UITextView()
    private let result = UITextView()
    private var config: KeyboardConfig?
    private var task: Task<Void, Never>?
    private var controls: [UIButton] = []
    private var output = ""
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.97, green: 0.95, blue: 0.92, alpha: 1)
        stack.axis = .vertical; stack.spacing = 6; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 6), stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6)])
        let height = view.heightAnchor.constraint(equalToConstant: 360); height.priority = .defaultHigh; height.isActive = true
        row([("下一键盘", #selector(nextKeyboard)), ("收起", #selector(hide)), ("取消", #selector(cancel))], locked: false)
        status.font = .systemFont(ofSize: 12); status.numberOfLines = 3
        stack.addArrangedSubview(status)
        row([("导入配置", #selector(importConfig)), ("测试连接", #selector(test)), ("删除配置", #selector(deleteConfig))])
        for textView in [source, result] {
            textView.isEditable = false; textView.isSelectable = false
            textView.font = .systemFont(ofSize: 15); textView.layer.cornerRadius = 9
            textView.backgroundColor = .secondarySystemBackground
            textView.heightAnchor.constraint(equalToConstant: 65).isActive = true
        }
        source.text = "先复制聊天文字，再点读取。原文只在本轮内存中暂存。"
        stack.addArrangedSubview(source)
        row([("读取聊天", #selector(readChat)), ("确认并生成", #selector(generate))])
        result.text = "生成的回复会显示在这里。"
        stack.addArrangedSubview(result)
        row([("插入回复", #selector(insert)), ("清空本轮", #selector(clear))])
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        do {
            config = try ConfigStore.keyboard().load()
            status.text = !hasFullAccess ? "请先在系统设置开启允许完全访问，供键盘联网。" : (config == nil ? "首次使用：从主 App 复制配置，再点导入配置。" : "本机配置已读取 · \(config!.model) · 0.1.0 (1)")
        } catch { config = nil; status.text = "配置读取失败：" + error.localizedDescription }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); stop(); clearRound()
    }
    private func row(_ items: [(String, Selector)], locked: Bool = true) {
        let row = UIStackView(); row.axis = .horizontal; row.distribution = .fillEqually; row.spacing = 5
        for (title, selector) in items {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal); button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            button.backgroundColor = .tertiarySystemBackground; button.layer.cornerRadius = 8
            button.addTarget(self, action: selector, for: .touchUpInside)
            button.heightAnchor.constraint(equalToConstant: 34).isActive = true
            row.addArrangedSubview(button); if locked { controls.append(button) }
        }
        stack.addArrangedSubview(row)
    }
    private var transcript = ""
    private func fullAccess() -> Bool {
        guard hasFullAccess else { status.text = "请开启随言键盘的允许完全访问，然后重新切换键盘。"; return false }; return true
    }
    @objc private func nextKeyboard() { advanceToNextInputMode() }
    @objc private func hide() { dismissKeyboard() }
    private func stop() { task?.cancel(); task = nil; controls.forEach { $0.isEnabled = true } }
    @objc private func cancel() { stop(); status.text = "已取消；已经发出的请求可能仍产生服务商用量。" }
    @objc private func importConfig() {
        guard fullAccess() else { return }
        do {
            let board = UIPasteboard.general
            let change = board.changeCount
            guard let text = board.string, let data = text.data(using: .utf8) else { throw UserFailure("剪贴板没有配置，请到主 App 重新复制") }
            let value = try KeyboardConfig.decode(data)
            let alert = UIAlertController(title: "导入配置", message: "接口：\(try value.completionURL().absoluteString)\n模型：\(value.model)\n将覆盖键盘原有配置。Key 不显示。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "保存到键盘", style: .default) { [weak self] _ in
                do {
                    let store = try ConfigStore.keyboard(); try store.save(value)
                    guard try store.load() == value else { throw UserFailure("配置回读校验失败") }
                    self?.config = value; self?.clearRound()
                    if board.changeCount == change { board.items = [] }
                    self?.status.text = "键盘独立保存并回读成功。请点测试连接。"
                } catch { self?.status.text = "保存失败：" + error.localizedDescription }
            })
            present(alert, animated: true)
        } catch { status.text = "导入失败：" + error.localizedDescription }
    }
    @objc private func deleteConfig() {
        let alert = UIAlertController(title: "删除键盘配置和 API Key？", message: "不会删除主 App。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            do { try ConfigStore.keyboard().delete(); self?.config = nil; self?.clearRound(); self?.status.text = "配置已删除" }
            catch { self?.status.text = error.localizedDescription }
        }); present(alert, animated: true)
    }
    @objc private func readChat() {
        guard fullAccess() else { return }
        guard let text = UIPasteboard.general.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status.text = "剪贴板没有文字"; return }
        guard !KeyboardConfig.isConfig(text) else { status.text = "剪贴板里是配置。请点导入配置，不会将 Key 发送给 AI。"; return }
        guard text.count <= 12000 else { status.text = "聊天文字最多 12000 字，请减少内容"; return }
        transcript = text; source.text = text; output = ""; result.text = "核对上方原文，再点确认并生成。"
        status.text = "原文已读取，尚未发送。生成时原文与风格会发送给已配置的 AI 服务。"
    }
    @objc private func test() { request(test: true) }
    @objc private func generate() { request(test: false) }
    private func request(test: Bool) {
        guard fullAccess(), task == nil else { return }
        guard let config else { status.text = "请先导入配置"; return }
        do { _ = try ReplyRules.messages(text: transcript, style: config.style, test: test) }
        catch { status.text = error.localizedDescription; return }
        let snapshot = transcript
        if !test { output = ""; result.text = "正在生成…" }
        status.text = test ? "正在发送最小文字测试…" : "正在生成回复…"
        controls.forEach { $0.isEnabled = false }
        task = Task { [weak self] in
            do {
                let response = try await ChatAPI.reply(config: config, text: snapshot, test: test)
                guard !Task.isCancelled, let self else { return }
                if test { self.status.text = "连接成功：" + String(response.prefix(80)) }
                else { self.output = response; self.result.text = response; self.status.text = "回复已生成。点插入后仍需你手动发送。" }
                self.task = nil; self.controls.forEach { $0.isEnabled = true }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.status.text = error.localizedDescription; self.task = nil; self.controls.forEach { $0.isEnabled = true }
            }
        }
    }
    @objc private func insert() {
        guard !output.isEmpty else { status.text = "请先生成回复"; return }
        textDocumentProxy.insertText(output); output = ""; result.text = "已插入，请在聊天输入框核对后发送。"
    }
    private func clearRound() { transcript = ""; output = ""; source.text = "请主动读取聊天文字。"; result.text = "尚未生成回复。" }
    @objc private func clear() { clearRound(); status.text = "本轮原文和回复已清空" }
}
