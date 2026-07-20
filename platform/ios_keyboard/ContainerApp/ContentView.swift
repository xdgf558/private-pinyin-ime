import SwiftUI
import UIKit
import UniformTypeIdentifiers

private enum StationTheme {
    static let background = Color(red: 0x13 / 255, green: 0x1A / 255, blue: 0x26 / 255)
    static let card = Color(red: 0x1B / 255, green: 0x24 / 255, blue: 0x34 / 255)
    static let border = Color(red: 0x2A / 255, green: 0x35 / 255, blue: 0x47 / 255)
    static let divider = Color(red: 0x23 / 255, green: 0x2E / 255, blue: 0x41 / 255)
    static let lamp = Color(red: 0xF0 / 255, green: 0xB2 / 255, blue: 0x4E / 255)
    static let onLamp = Color(red: 0x3A / 255, green: 0x26 / 255, blue: 0x05 / 255)
    static let badge = Color(red: 0x24 / 255, green: 0x1E / 255, blue: 0x12 / 255)
    static let textPrimary = Color(red: 0xF2 / 255, green: 0xED / 255, blue: 0xE3 / 255)
    static let textSecondary = Color(red: 0x93 / 255, green: 0xA0 / 255, blue: 0xB4 / 255)
    static let textFaint = Color(red: 0x5C / 255, green: 0x68 / 255, blue: 0x78 / 255)
}

struct ContentView: View {
    @State private var statusText = ""
    @State private var learningEnabled = false
    @State private var lexiconStatusText = ""
    @State private var lexiconOperationText = ""
    @State private var showingRimeImporter = false
    @State private var showingRimeIceConfirmation = false
    @State private var isImportingRimeIce = false

    var body: some View {
        ZStack {
            StationTheme.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    brandRow
                    welcomeSection
                    setupSection
                    privacySection
                    lexiconSection
                    footer
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            _ = IosSettingsStore.ensureSettingsFile()
            learningEnabled = IosSettingsStore.isLearningEnabled()
            lexiconStatusText = IosSettingsStore.importedLexiconSummaryText()
            lexiconOperationText = IosSettingsStore.rimeImportStatusText() ?? ""
        }
        .fileImporter(
            isPresented: $showingRimeImporter,
            allowedContentTypes: rimeDocumentTypes,
            allowsMultipleSelection: true,
            onCompletion: handleRimeImportSelection
        )
        .alert("导入雾凇拼音精选？", isPresented: $showingRimeIceConfirmation) {
            Button("取消", role: .cancel) {}
            Button("下载并导入") {
                importReviewedRimeIce()
            }
        } message: {
            Text(
                "将由容器 App 下载并校验雾凇拼音 2026.03.26 的已审核中文精选词典，不会开启键盘联网。词库依 GPL-3.0-only 许可使用。"
            )
        }
    }

    private var brandRow: some View {
        HStack(spacing: 12) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("猫栈拼音")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(StationTheme.textPrimary)
                Text("本地拼音输入法")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(StationTheme.textFaint)
            }

            Spacer(minLength: 12)

            Text("iOS")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(StationTheme.lamp)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(StationTheme.badge)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(StationTheme.border, lineWidth: 1)
                }
        }
    }

    private var welcomeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("把猫栈拼音\n带进每一次输入。")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(StationTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("只差最后一步。添加键盘后，就能在备忘录、浏览器和常用应用里使用。")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(StationTheme.textSecondary)
                .lineSpacing(4)
        }
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("开始使用", icon: "keyboard")

            VStack(spacing: 0) {
                setupStep(number: "1", title: "点下方按钮打开系统设置")
                divider
                setupStep(number: "2", title: "进入「通用 > 键盘 > 键盘」")
                divider
                setupStep(number: "3", title: "点「添加新键盘」，选择猫栈拼音")
            }
            .background(StationTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(StationTheme.border, lineWidth: 1)
            }

            Button(action: openKeyboardSettings) {
                HStack(spacing: 9) {
                    Image(systemName: "gearshape.fill")
                    Text("打开系统设置")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 15))
                .foregroundStyle(StationTheme.onLamp)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(StationTheme.lamp)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)

            Text("添加后，在输入界面点按地球键即可切换到猫栈拼音。")
                .font(.system(size: 12))
                .foregroundStyle(StationTheme.textFaint)
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("隐私与学习", icon: "lock.fill")

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("学习数据只留在本机")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(StationTheme.textPrimary)
                    Text("键盘扩展默认不开启完全访问，也不连网。只有你在容器 App 中主动下载词库时才会访问固定来源。")
                        .font(.system(size: 13))
                        .foregroundStyle(StationTheme.textSecondary)
                        .lineSpacing(3)
                }
                .padding(16)

                divider

                Toggle("记住我常选的词", isOn: Binding(
                    get: { learningEnabled },
                    set: { setLearningEnabled($0) }
                ))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(StationTheme.textPrimary)
                .tint(StationTheme.lamp)
                .disabled(!IosSettingsStore.usesAppGroupStorage)
                .padding(16)

                divider

                Button(action: clearLocalLexicon) {
                    Label("清除本机学习记录", systemImage: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(StationTheme.lamp)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .buttonStyle(.plain)

                if !statusText.isEmpty {
                    divider
                    Text(statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(StationTheme.textSecondary)
                        .padding(16)
                }
            }
            .background(StationTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(StationTheme.border, lineWidth: 1)
            }
        }
    }

    private var lexiconSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("本地导入词库", icon: "books.vertical.fill")

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("导入 Rime 词典")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(StationTheme.textPrimary)
                    Text("支持带明确拼音列的 YAML 词典。导入层单独保存在本机，升级不会覆盖。")
                        .font(.system(size: 13))
                        .foregroundStyle(StationTheme.textSecondary)
                        .lineSpacing(3)
                }
                .padding(16)

                divider

                HStack(spacing: 12) {
                    Button(action: { showingRimeImporter = true }) {
                        Label("选择文件", systemImage: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(StationTheme.onLamp)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(StationTheme.lamp)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!IosSettingsStore.usesAppGroupStorage)

                    Button(action: clearImportedLexicon) {
                        Label("清空导入", systemImage: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(StationTheme.lamp)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(StationTheme.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)

                divider

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("雾凇拼音精选")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(StationTheme.textPrimary)
                            Text("固定已审核版本 2026.03.26，默认不下载；只有点击后才会连接 GitHub 官方源。")
                                .font(.system(size: 12))
                                .foregroundStyle(StationTheme.textSecondary)
                                .lineSpacing(3)
                        }
                        Spacer(minLength: 8)
                        Link(
                            destination: IosLexiconImportBridge.reviewedRimeIceSourceURL
                        ) {
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(StationTheme.lamp)
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("查看雾凇拼音来源与许可")
                    }

                    Button(action: { showingRimeIceConfirmation = true }) {
                        HStack(spacing: 8) {
                            if isImportingRimeIce {
                                ProgressView()
                                    .tint(StationTheme.onLamp)
                            } else {
                                Image(systemName: "icloud.and.arrow.down")
                            }
                            Text(isImportingRimeIce ? "正在下载并导入…" : "一键导入雾凇精选")
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(StationTheme.onLamp)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(StationTheme.lamp)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isImportingRimeIce || !IosSettingsStore.usesAppGroupStorage)
                }
                .padding(16)

                if !lexiconStatusText.isEmpty {
                    divider
                    Text(lexiconStatusText)
                        .font(.system(size: 12))
                        .foregroundStyle(StationTheme.textSecondary)
                        .padding(16)
                }

                if !lexiconOperationText.isEmpty {
                    divider
                    Text(lexiconOperationText)
                        .font(.system(size: 12))
                        .foregroundStyle(StationTheme.textFaint)
                        .padding(16)
                }
            }
            .background(StationTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(StationTheme.border, lineWidth: 1)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("小小驿站，夜里也亮着灯")
            Spacer()
            Text(versionText)
        }
        .font(.system(size: 11))
        .foregroundStyle(StationTheme.textFaint)
    }

    private var divider: some View {
        Rectangle()
            .fill(StationTheme.divider)
            .frame(height: 1)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "版本 \(version)（\(build)）"
    }

    private var rimeDocumentTypes: [UTType] {
        let types = ["yaml", "yml", "dict"].compactMap { extensionName in
            UTType(filenameExtension: extensionName)
        }
        return types.isEmpty ? [.data] : types
    }

    private func sectionTitle(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(StationTheme.textSecondary)
    }

    private func setupStep(number: String, title: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(StationTheme.onLamp)
                .frame(width: 25, height: 25)
                .background(StationTheme.lamp)
                .clipShape(Circle())
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(StationTheme.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private func openKeyboardSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            statusText = "无法打开系统设置，请手动前往「设置 > 通用 > 键盘 > 键盘」。"
            return
        }

        UIApplication.shared.open(settingsURL, options: [:]) { opened in
            guard !opened else {
                return
            }
            DispatchQueue.main.async {
                statusText = "无法打开系统设置，请手动前往「设置 > 通用 > 键盘 > 键盘」。"
            }
        }
    }

    private func setLearningEnabled(_ enabled: Bool) {
        if IosSettingsStore.setLearningEnabled(enabled) {
            learningEnabled = enabled
            statusText = enabled ? "用户学习已开启。" : "用户学习已关闭。"
        } else {
            learningEnabled = IosSettingsStore.isLearningEnabled()
            statusText = "无法更新学习设置。"
        }
    }

    private func clearLocalLexicon() {
        do {
            let removed = try IosSettingsStore.clearLocalLexiconArtifacts()
            statusText = removed == 0 ? "没有发现本机学习记录。" : "本机学习记录已清除。"
        } catch {
            statusText = "无法清除本机学习记录。"
        }
    }

    private func handleRimeImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let accessed = urls.filter { $0.startAccessingSecurityScopedResource() }
            guard accessed.count == urls.count else {
                for url in accessed {
                    url.stopAccessingSecurityScopedResource()
                }
                lexiconOperationText = "无法获得所选词库文件的读取权限，请重新选择后再试。"
                return
            }
            lexiconOperationText = "正在读取并导入所选词库…"
            DispatchQueue.global(qos: .userInitiated).async {
                defer {
                    for url in accessed {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let outcome: (message: String, refreshStatus: Bool)
                do {
                    let count = try IosLexiconImportBridge.importRimeLexicons(from: accessed)
                    outcome = (
                        count == 0
                            ? "没有选择可导入的词库文件。"
                            : "已在本机导入 \(count) 条词库记录。重新切换到猫栈拼音后生效。",
                        count > 0
                    )
                } catch IosLexiconImportError.sharedStorageUnavailable {
                    outcome = ("App Group 暂不可用，无法保存导入词库。", false)
                } catch IosLexiconImportError.tooManyFiles {
                    outcome = ("一次最多选择 8 个词库文件，请分批导入。", false)
                } catch IosLexiconImportError.sourceTooLarge {
                    outcome = ("单个词库文件不能超过 16 MiB。", false)
                } catch IosLexiconImportError.partialImport(let acceptedRows) {
                    outcome = (
                        "已导入 \(acceptedRows) 条记录，但后续文件导入失败。请检查剩余文件。",
                        true
                    )
                } catch {
                    outcome = ("导入失败，请确认词库包含明确的拼音列。", false)
                }

                DispatchQueue.main.async {
                    lexiconOperationText = outcome.message
                    if outcome.refreshStatus {
                        lexiconStatusText = IosSettingsStore.importedLexiconSummaryText()
                    }
                }
            }
        case .failure:
            lexiconOperationText = "未能打开所选词库文件。"
        }
    }

    private func importReviewedRimeIce() {
        guard !isImportingRimeIce else {
            return
        }
        isImportingRimeIce = true
        lexiconOperationText = "正在下载并校验雾凇拼音精选…"
        IosLexiconImportBridge.importReviewedRimeIce { result in
            isImportingRimeIce = false
            switch result {
            case .success(let count):
                lexiconStatusText = IosSettingsStore.importedLexiconSummaryText()
                lexiconOperationText = "已导入 \(count) 条雾凇精选记录。重新切换到猫栈拼音后生效。"
            case .failure(IosLexiconImportError.integrityCheckFailed):
                lexiconOperationText = "下载文件未通过完整性校验，已拒绝导入。"
            case .failure(IosLexiconImportError.downloadFailed):
                lexiconOperationText = "无法连接 GitHub 官方源；如你所在网络无法访问 GitHub，可改用「选择文件」导入本地词典。"
            case .failure(IosLexiconImportError.partialImport(let acceptedRows)):
                lexiconStatusText = IosSettingsStore.importedLexiconSummaryText()
                lexiconOperationText = "已导入 \(acceptedRows) 条记录，但完整导入未完成。"
            case .failure:
                lexiconOperationText = "雾凇拼音精选导入失败，本机原有词库不受影响。"
            }
        }
    }

    private func clearImportedLexicon() {
        do {
            let removed = try IosSettingsStore.clearImportedLexiconArtifacts()
            lexiconOperationText = removed == 0
                ? "没有发现手动导入的词库。"
                : "导入词库已清空，重新切换键盘后生效。"
            lexiconStatusText = IosSettingsStore.importedLexiconSummaryText()
        } catch {
            lexiconOperationText = "无法清空导入词库。"
        }
    }
}

#Preview {
    ContentView()
}
