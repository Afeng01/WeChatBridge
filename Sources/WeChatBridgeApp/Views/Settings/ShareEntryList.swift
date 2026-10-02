import WeChatBridgeCore
import SwiftUI

/// The Share-menu entries, one switch each.
///
/// Lives on its own because two places need exactly this list: the 入口 pane and
/// step 1 of the first-run guide. A second copy would be a second answer to
/// "what does this switch do", and they would drift the first time one of them
/// was touched.
struct ShareEntryList: View {
    @ObservedObject var probe: ShareEntryProbe
    /// Tighter in the first-run guide, where the rows and a footer have to fit
    /// one unscrollable screen.
    var spacing: CGFloat = Space.l
    /// The settings pane reads as one control surface; the guide keeps the
    /// lighter list because it has a fixed height and no page around it.
    var carded = true
    /// Settings uses terse state; onboarding keeps the explanatory copy.
    var compactDetails = false
    var obsidianVaultPath: String?
    /// Where 「沉淀到文件夹」 lands its notes; unlike the vault it always has a
    /// value, so the row can name the folder straight away.
    var folderPath = ""
    var customTargetCount = 0
    var configure: ((ShareAction) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if carded {
                VStack(spacing: 0) {
                    ForEach(ShareAction.allCases, id: \.self) { action in
                        row(action)
                        if action != ShareAction.allCases.last {
                            Rectangle()
                                .fill(Theme.stroke)
                                .frame(height: Stroke.hairline)
                                .padding(.leading, 50)
                        }
                    }
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: Stroke.hairline)
                )
            } else {
                ForEach(ShareAction.allCases, id: \.self) { row($0) }
            }

            if probe.hasUnregisteredEntry {
                Notice(L10n.text("WeChatBridge 需要安装在「应用程序」文件夹里，系统才会登记这些入口。"))
            }
        }
    }

    private func row(_ action: ShareAction) -> some View {
        HStack(alignment: .center, spacing: Space.m) {
            entryIcon(action)

            VStack(alignment: .leading, spacing: 3) {
                Text(action.entryTitle)
                    .font(Typo.rowTitle)
                    .foregroundStyle(Theme.ink)
                Text(detail(for: action))
                    .font(Typo.paneCaption)
                    .foregroundStyle(detailIsWarning(for: action) ? Theme.warning : Theme.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: Space.m)

            HStack(spacing: Space.s) {
                if compactDetails,
                   let configure,
                   action == .obsidian || action == .folder || action == .custom {
                    Button(action == .custom ? L10n.text("管理…") : L10n.text("设置…")) {
                        configure(action)
                    }
                    .buttonStyle(SettingsActionButtonStyle())
                }
                control(for: action)
            }
        }
        .padding(.horizontal, carded ? Space.m : 0)
        .frame(minHeight: carded ? 42 : nil)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func entryIcon(_ action: ShareAction) -> some View {
        if let bundleIdentifier = action.targetBundleIdentifier,
           InstalledApp.lookup(bundleIdentifier).isInstalled {
            Image(nsImage: InstalledApp.lookup(bundleIdentifier).icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
                .frame(width: 28)
                .accessibilityHidden(true)
        } else if let logo = Self.bundledLogo(for: action) {
            Image(nsImage: logo)
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
                .frame(width: 28)
                .accessibilityHidden(true)
        } else {
            Image(systemName: Self.symbol(for: action))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    /// Until the first read lands there is nothing honest to draw, so the row
    /// shows a spinner in the switch's place. Once it has, the switch stays on
    /// screen for good: a click moves it at once, the election is read back
    /// behind it — a second click meanwhile is ignored by the probe, and there
    /// is no spinner for those few milliseconds, the user asked for none —
    /// and a refusal moves it back, animated.
    @ViewBuilder
    private func control(for action: ShareAction) -> some View {
        if probe.state(of: action) == nil {
            ProgressView()
                .controlSize(.small)
                // The width of the switch it stands in for, so the row does not
                // reflow when the answer arrives.
                .frame(width: Self.switchWidth)
        } else if probe.state(of: action) == .unregistered {
            HStack(spacing: Space.s) {
                StatusPill(text: L10n.text("未注册"), tone: .neutral)
                entrySwitch(action)
                    .disabled(true)
            }
        } else {
            entrySwitch(action)
        }
    }

    private func entrySwitch(_ action: ShareAction) -> some View {
        Toggle(isOn: Binding(
            get: { probe.isOn(action) },
            set: { probe.setEnabled($0, for: action) }
        )) {
            // Hidden on screen, read aloud by VoiceOver: without it the switch
            // announces itself as an unnamed control four times over.
            Text(action.entryTitle)
        }
        .toggleStyle(SwitchToggleStyle())
        .labelsHidden()
        .frame(width: Self.switchWidth)
    }

    private static let switchWidth = SwitchToggleStyle.width

    private static func bundledLogo(for action: ShareAction) -> NSImage? {
        let file: String
        switch action {
        case .codex: file = "04-chatgpt.png"
        case .claude: file = "03-claude.png"
        case .doubao: file = "01-doubao.png"
        case .qwen: file = "02-qwen.png"
        case .workBuddy: file = "06-workbuddy.png"
        case .weSight: file = "07-wesight.png"
        case .obsidian: file = "05-obsidian.png"
        case .folder: return L10n.text("把聊天记录转成 Markdown 和附件，写入选定的文件夹。")
