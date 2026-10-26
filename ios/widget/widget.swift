import SwiftUI
import WidgetKit
import AppIntents

private let connectionURL = URL(string: "onexray://widget/connect")!

private var connectionWidgetFamilies: [WidgetFamily] {
    if #available(iOS 16.0, *) {
        return [.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular]
    }
    return [.systemSmall, .systemMedium]
}

struct ConnectionWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: AppleWidgetSnapshot?
    let languageCode: String

    var status: AppleWidgetStatus { snapshot?.displayedStatus(at: date) ?? .unknown }
}

struct ConnectionWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ConnectionWidgetEntry {
        ConnectionWidgetEntry(date: Date(), snapshot: nil, languageCode: "en")
    }

    func getSnapshot(in context: Context, completion: @escaping (ConnectionWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ConnectionWidgetEntry>) -> Void) {
        let current = entry()
        var entries = [current]
        if let snapshot = current.snapshot, snapshot.isCurrent(at: current.date) {
            // Expire the observation if a process exits without a final callback.
            entries.append(ConnectionWidgetEntry(
                date: snapshot.observedAt.addingTimeInterval(AppleWidgetSnapshot.maximumAge),
                snapshot: snapshot, languageCode: current.languageCode
            ))
        }
        completion(Timeline(entries: entries, policy: .never))
    }

    private func entry() -> ConnectionWidgetEntry {
        let store = AppleWidgetStore.shared
        return ConnectionWidgetEntry(date: Date(), snapshot: store?.snapshot(), languageCode: store?.languageCode() ?? "en")
    }
}

struct ConnectionWidget: Widget {
    var body: some WidgetConfiguration {
        let language = AppleWidgetStore.shared?.languageCode() ?? "en"
        return StaticConfiguration(kind: AppleWidgetStore.kind, provider: ConnectionWidgetProvider()) { entry in
            ConnectionWidgetView(entry: entry)
                .environment(\.locale, Locale(identifier: entry.languageCode))
                .environment(\.layoutDirection, entry.languageCode == "fa" ? .rightToLeft : .leftToRight)
                .widgetURL(connectionURL)
        }
        .configurationDisplayName(Text(verbatim: widgetText("Connection", language)))
        .description(Text(verbatim: widgetText("VPN status and actions that open OneXray.", language)))
        .supportedFamilies(connectionWidgetFamilies)
    }
}

private struct ConnectionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let entry: ConnectionWidgetEntry

    private let palette = ConnectionWidgetPalette()
    private var largeText: Bool { dynamicTypeSize >= .xxxLarge }
    private var emphasizeStop: Bool { entry.status == .connected || entry.status == .connecting }

    private var isAccessory: Bool {
        if #available(iOS 16.0, *) {
            return family == .accessoryCircular || family == .accessoryRectangular
        }
        return false
    }

    var body: some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                if !isAccessory { surface }
            }
        } else if isAccessory {
            content
        } else {
            content.padding(16).background { surface }
        }
    }

    private var surface: some View {
        ContainerRelativeShape()
            .fill(palette.surface)
            .overlay { ContainerRelativeShape().strokeBorder(palette.border, lineWidth: 1) }
    }

    @ViewBuilder private var content: some View {
        if #available(iOS 16.0, *), family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: statusIcon).font(.title2)
            }
            .privacySensitive()
            .accessibilityLabel("OneXray, \(statusText)")
        } else if #available(iOS 16.0, *), family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 3) {
                Text("OneXray").font(.headline)
                Label(statusText, systemImage: statusIcon).font(.caption).privacySensitive()
                Text(text("Open app")).font(.caption2)
            }
        } else if family == .systemMedium {
            mediumContent
        } else {
            smallContent
        }
    }

    private var smallContent: some View {
        GeometryReader { geometry in
            let compactHeight = geometry.size.height < 124
            VStack(alignment: .leading, spacing: 0) {
                if !largeText && !compactHeight { brand }
                Spacer(minLength: 3)
                VStack(spacing: 2) {
                    if !largeText { statusSymbol(size: geometry.size.height >= 136 ? 24 : 20) }
                    statusLabel(lines: 1)
                    observation(showPrefix: !largeText)
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 6)
                if #available(iOS 17.0, *) {
                    actions(compact: true, iconsOnly: compactHeight && dynamicTypeSize >= .xxLarge)
                } else {
                    openApp(compact: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var mediumContent: some View {
        GeometryReader { geometry in
            let actionWidth = largeText ? 64 : geometry.size.width * 0.44
            HStack(spacing: 16) {
                Link(destination: connectionURL) {
                    VStack(alignment: .leading, spacing: 12) {
                        if !largeText { brand }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                if !largeText { statusSymbol(size: geometry.size.width < 310 ? 24 : 32) }
                                statusLabel(lines: 1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            observation(showPrefix: !largeText)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(text("Open app"))
                Group {
                    if #available(iOS 17.0, *) {
                        actions(compact: false)
                    } else {
                        openApp(compact: false)
                    }
                }
                .frame(width: actionWidth)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var brand: some View {
        Text("OneXray")
            .font(.caption)
            .foregroundStyle(palette.secondary)
            .lineLimit(1)
    }

    private func statusLabel(lines: Int) -> some View {
        Text(statusText)
            .font(.headline)
            .foregroundStyle(palette.foreground)
            .lineLimit(lines)
            .minimumScaleFactor(largeText ? 0.4 : 0.75)
            .privacySensitive()
    }

    private func statusSymbol(size: CGFloat) -> some View {
        Image(systemName: statusIcon)
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(statusColor)
            .privacySensitive()
            .accessibilityHidden(true)
    }

    private func observation(showPrefix: Bool) -> some View {
        Group {
            if let snapshot = entry.snapshot {
                HStack(spacing: 3) {
                    if showPrefix { Text(text("Observed")).lineLimit(1) }
                    Text(snapshot.observedAt, style: .time)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint(showPrefix ? "" : text("Observed"))
            } else {
                Text(text("Open app to refresh"))
                    .lineLimit(1)
            }
        }
        .font(.caption2)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .foregroundStyle(palette.secondary)
        .privacySensitive()
    }

    private func openApp(compact: Bool) -> some View {
        Link(destination: connectionURL) {
            actionLabel(.open, compact: compact)
        }
        .buttonStyle(ConnectionWidgetButtonStyle(palette: palette, action: .open, prominent: true))
        .accessibilityLabel(text("Open app"))
    }

    @available(iOS 17.0, *)
    @ViewBuilder private func actions(compact: Bool, iconsOnly: Bool = false) -> some View {
        if compact {
            HStack(spacing: 8) {
                startButton(compact: true, iconsOnly: iconsOnly)
                stopButton(compact: true, iconsOnly: iconsOnly)
            }
        } else {
            VStack(spacing: 8) {
                startButton(compact: false, iconsOnly: iconsOnly)
                stopButton(compact: false, iconsOnly: iconsOnly)
            }
        }
    }

    @available(iOS 17.0, *)
    private func startButton(compact: Bool, iconsOnly: Bool) -> some View {
        Button(intent: StartVpnWidgetIntent()) { actionLabel(.start, compact: compact, iconsOnly: iconsOnly) }
            .buttonStyle(ConnectionWidgetButtonStyle(palette: palette, action: .start, prominent: !emphasizeStop))
            .accessibilityLabel(text("Start VPN"))
    }

    @available(iOS 17.0, *)
    private func stopButton(compact: Bool, iconsOnly: Bool) -> some View {
        Button(intent: StopVpnWidgetIntent()) { actionLabel(.stop, compact: compact, iconsOnly: iconsOnly) }
            .buttonStyle(ConnectionWidgetButtonStyle(palette: palette, action: .stop, prominent: emphasizeStop))
            .accessibilityLabel(text("Stop VPN"))
    }

    private func actionLabel(_ action: ConnectionWidgetAction, compact: Bool, iconsOnly: Bool = false) -> some View {
        HStack(spacing: compact ? 3 : 4) {
            Image(systemName: action.symbol)
                .font(.system(size: largeText || iconsOnly ? 18 : 12, weight: .semibold))
            if !largeText && !iconsOnly {
                Text(text(compact ? action.compactKey : action.labelKey))
                    .lineLimit(compact && action != .open ? 1 : 2)
                    .minimumScaleFactor(0.92)
            }
        }
        .padding(.horizontal, compact ? 2 : 8)
    }

    private var statusText: String {
        let key = switch entry.status {
        case .unknown: "Unknown"
        case .disconnected: "Disconnected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .disconnecting: "Disconnecting"
        }
        return text(key)
    }

    private var statusIcon: String {
        switch entry.status {
        case .connected: "checkmark.shield"
        case .connecting, .disconnecting: "arrow.triangle.2.circlepath"
        case .disconnected: "shield"
        case .unknown: "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .connected: palette.success
        case .connecting, .disconnecting: palette.warning
        case .disconnected, .unknown: palette.secondary
        }
    }

    private func text(_ key: String) -> String { widgetText(key, entry.languageCode) }
}

private enum ConnectionWidgetAction {
    case start, stop, open

    var symbol: String {
        switch self {
        case .start: "play.fill"
        case .stop: "stop.fill"
        case .open: "arrow.up.forward"
        }
    }

    var labelKey: String {
        switch self {
        case .start: "Start VPN"
        case .stop: "Stop VPN"
        case .open: "Open app"
        }
    }

    var compactKey: String {
        switch self {
        case .start: "Start"
        case .stop: "Stop"
        case .open: "Open app"
        }
    }
}

private struct ConnectionWidgetButtonStyle: ButtonStyle {
    let palette: ConnectionWidgetPalette
    let action: ConnectionWidgetAction
    let prominent: Bool

    private var foreground: Color {
        prominent ? .white : (action == .stop ? palette.destructive : palette.primaryText)
    }

    private var fill: Color {
        if prominent { return action == .stop ? palette.destructiveSolid : palette.primarySolid }
        return action == .stop ? .clear : palette.accent
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if #available(iOS 16.0, *) {
                    RoundedRectangle(cornerRadius: 8).fill(fill).widgetAccentable()
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(fill)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(prominent ? .clear : palette.border, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Named colors adapt to appearance in Assets.xcassets and mirror the App palette.
private struct ConnectionWidgetPalette {
    let surface = Color("WidgetBackground")
    let foreground = Color("WidgetForeground")
    let secondary = Color("WidgetSecondaryText")
    let border = Color("WidgetBorder")
    let primaryText = Color("WidgetPrimaryText")
    let primarySolid = Color("WidgetPrimarySolid")
    let destructive = Color("WidgetDestructiveText")
    let destructiveSolid = Color("WidgetDestructiveSolid")
    let accent = Color("WidgetAccentSurface")
    let success = Color("WidgetSuccess")
    let warning = Color("WidgetWarning")
}

private func widgetText(_ key: String, _ language: String) -> String {
    let path = Bundle.main.path(forResource: AppleWidgetLanguage.normalized(language), ofType: "lproj")
    let bundle = path.flatMap(Bundle.init(path:)) ?? Bundle.main
    return bundle.localizedString(forKey: key, value: key, table: "Widget")
}

struct ConnectionWidgetPreviews: PreviewProvider {
    static var previews: some View {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            ForEach([AppleWidgetStatus.disconnected, .connected], id: \.rawValue) { status in
                ForEach(connectionWidgetFamilies, id: \.self) { family in
                    ConnectionWidgetView(entry: ConnectionWidgetEntry(
                        date: Date(), snapshot: AppleWidgetSnapshot(status: status), languageCode: "en"
                    ))
                    .environment(\.colorScheme, scheme)
                    .environment(\.locale, Locale(identifier: "en"))
                    .previewContext(WidgetPreviewContext(family: family))
                    .previewDisplayName("\(family) · \(status.rawValue) · \(scheme)")
                }
            }
        }
    }
}
