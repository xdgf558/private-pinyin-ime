import SwiftUI
import UIKit

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
                    Text("默认不开启完全访问，也不连接网络。学习只记录你选过的词、拼音、次数和更新时间。")
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
}

#Preview {
    ContentView()
}
