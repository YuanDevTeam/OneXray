import SwiftUI
import WidgetKit
import AppIntents

private let connectionURL = URL(string: "onexray://widget/connect")!

private let connectionWidgetFamilies: [WidgetFamily] = [
    .systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular,
]

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
        .description(Text(verbatim: widgetText(
            AppleWidgetExecutionPolicy.usesBackgroundActions
                ? "VPN status and background actions using the last prepared configuration."
                : "VPN status and actions that open OneXray.",
            language
        )))
        .supportedFamilies(connectionWidgetFamilies)
    }
}

@available(iOS 18.0, *)
private struct VpnControlValue {
    let status: AppleWidgetStatus
    let languageCode: String
}

@available(iOS 18.0, *)
private struct VpnControlValueProvider: ControlValueProvider {
    var previewValue: VpnControlValue {
        VpnControlValue(status: .unknown, languageCode: AppleWidgetStore.shared?.languageCode() ?? "en")
    }

    func currentValue() async throws -> VpnControlValue {
        let store = AppleWidgetStore.shared
        // Providers stay in the Widget extension. Re-evaluate expiry whenever
        // the system requests a value; this is not a live NetworkExtension read.
        return VpnControlValue(
            status: store?.snapshot()?.displayedStatus(at: Date()) ?? .unknown,
            languageCode: store?.languageCode() ?? "en"
        )
    }
}

@available(iOS 18.0, *)
struct VpnControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        let language = AppleWidgetStore.shared?.languageCode() ?? "en"
        return StaticControlConfiguration(kind: AppleWidgetStore.controlKind, provider: VpnControlValueProvider()) { value in
            ControlWidgetButton(action: ToggleVpnWidgetIntent()) {
                Label {
                    Text("VPN")
                } icon: {
                    Image(systemName: controlSymbol(value.status))
                }
                .environment(\.locale, Locale(identifier: value.languageCode))
                .environment(\.layoutDirection, value.languageCode == "fa" ? .rightToLeft : .leftToRight)
                .controlWidgetStatus(Text(verbatim: widgetText(controlStatusKey(value.status), value.languageCode)))
                .controlWidgetActionHint(Text(verbatim: widgetText("Start or stop VPN", value.languageCode)))
                .accessibilityLabel(Text(verbatim: "VPN, \(widgetText(controlStatusKey(value.status), value.languageCode))"))
            }
            // A button remains actionable for unknown and expired observations.
            // The intent decides from current native state, never this snapshot.
            .tint(value.status == .connected ? Color("WidgetSuccess") : nil)
        }
        .displayName(LocalizedStringResource("VPN", table: "Widget", locale: Locale(identifier: language)))
        .description(controlDescription(language: language))
    }

    private func controlDescription(language: String) -> LocalizedStringResource {
        if AppleWidgetExecutionPolicy.usesBackgroundActions {
            return LocalizedStringResource(
                "Start or stop VPN in the background using the last prepared configuration.",
                table: "Widget", locale: Locale(identifier: language)
            )
        }
        return LocalizedStringResource(
            "Open OneXray to perform this action.", table: "Widget", locale: Locale(identifier: language)
        )
    }

    private func controlStatusKey(_ status: AppleWidgetStatus) -> String {
        switch status {
        case .unknown: "Status pending"
        case .disconnected: "Disconnected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .disconnecting: "Disconnecting"
        }
    }

    private func controlSymbol(_ status: AppleWidgetStatus) -> String {
        switch status {
        case .unknown: "questionmark.circle"
        case .disconnected: "shield"
        case .connecting, .disconnecting: "arrow.triangle.2.circlepath"
        case .connected: "checkmark.shield"
        }
    }
}

private struct ConnectionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var statusLineHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .caption) private var brandLineHeight: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2) private var observationLineHeight: CGFloat = 12
    let entry: ConnectionWidgetEntry

    private let palette = ConnectionWidgetPalette()
    private var largeText: Bool { dynamicTypeSize >= .xxxLarge }

    private var toggleAction: ConnectionWidgetAction {
        switch entry.status {
        case .connected, .connecting: .stop
        case .disconnected: .start
        case .unknown, .disconnecting: .toggle
        }
    }

    private var toggleLabelKey: String {
        entry.status == .disconnecting ? "Disconnecting" : toggleAction.labelKey
    }

    private var isAccessory: Bool {
        family == .accessoryCircular || family == .accessoryRectangular
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
        if family == .accessoryCircular {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: statusIcon).font(.title2)
            }
            .privacySensitive()
            .accessibilityLabel("OneXray, \(statusText)")
        } else if family == .accessoryRectangular {
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
            let showBrand = !largeText && geometry.size.height >= 44 + statusLineHeight + brandLineHeight + 12
            let showObservation = !largeText && entry.snapshot != nil
                && geometry.size.height >= 56 + statusLineHeight + brandLineHeight + observationLineHeight + 14
            let reservedHeight = statusLineHeight + 10
                + (showBrand ? brandLineHeight + 4 : 0)
                + (showObservation ? observationLineHeight + 3 : 0)
            let diameter = min(64, max(44, geometry.size.height - reservedHeight))

            VStack(spacing: 0) {
                if showBrand { brand }
                Spacer(minLength: 4)
                powerControl(diameter: diameter)
                Spacer(minLength: 6)
                VStack(spacing: 3) {
                    statusLabel(lines: 1)
                    if showObservation { observation(showPrefix: false) }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var mediumContent: some View {
        GeometryReader { geometry in
            let actionWidth: CGFloat = geometry.size.width < 300 ? 88 : 104
            let diameter = min(72, max(44, geometry.size.height - (largeText ? 0 : 36)))
            HStack(spacing: 16) {
                Link(destination: connectionURL) {
                    VStack(alignment: .leading, spacing: 10) {
                        if !largeText { brand }
                        HStack(spacing: 8) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                                .privacySensitive()
                                .accessibilityHidden(true)
                            statusLabel(font: .title2.weight(.semibold), lines: 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !largeText && entry.snapshot != nil && geometry.size.height >= 100 {
                            observation(showPrefix: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(text("Open app"))

                VStack(spacing: 8) {
                    powerControl(diameter: diameter)
                    if !largeText {
                        Text(text(powerCaptionKey))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.75)
                            .accessibilityHidden(true)
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

    private func statusLabel(font: Font = .headline, lines: Int) -> some View {
        Text(statusText)
            .font(font)
            .foregroundStyle(entry.status == .connected ? palette.success : palette.foreground)
            .lineLimit(lines)
            .minimumScaleFactor(largeText ? 0.4 : 0.75)
            .privacySensitive()
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

    @ViewBuilder private func powerControl(diameter: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            // Snapshot state only changes presentation. Native execution reads
            // current status, and disconnecting never queues a new connection.
            Button(intent: ToggleVpnWidgetIntent()) {
                powerSymbol(diameter: diameter)
            }
            .buttonStyle(ConnectionWidgetPowerButtonStyle(palette: palette, action: toggleAction, diameter: diameter))
            .accessibilityLabel(text(toggleLabelKey))
            .accessibilityValue(statusText)
        } else {
            Link(destination: connectionURL) { powerSymbol(diameter: diameter) }
                .buttonStyle(ConnectionWidgetPowerButtonStyle(palette: palette, action: .open, diameter: diameter))
                .accessibilityLabel(text("Open app"))
        }
    }

    private func powerSymbol(diameter: CGFloat) -> some View {
        Image(systemName: "power")
            .font(.system(size: diameter * 0.4, weight: .medium))
            .accessibilityHidden(true)
    }

    private var powerCaptionKey: String {
        if #available(iOS 17.0, *) {
            return entry.status == .disconnecting ? "Disconnecting" : toggleAction.compactKey
        }
        return "Open app"
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
    case start, stop, toggle, open

    var labelKey: String {
        switch self {
        case .start: "Start VPN"
        case .stop: "Stop VPN"
        case .toggle: "Start or stop VPN"
        case .open: "Open app"
        }
    }

    var compactKey: String {
        switch self {
        case .start: "Start"
        case .stop: "Stop"
        case .toggle: "Start or stop VPN"
        case .open: "Open app"
        }
    }
}

private struct ConnectionWidgetPowerButtonStyle: ButtonStyle {
    let palette: ConnectionWidgetPalette
    let action: ConnectionWidgetAction
    let diameter: CGFloat

    private var foreground: Color {
        switch action {
        case .stop: palette.destructive
        case .toggle: palette.secondary
        case .start, .open: palette.primaryText
        }
    }

    private var tint: Color {
        switch action {
        case .stop: palette.destructiveSolid
        case .toggle: palette.secondary
        case .start, .open: palette.primarySolid
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .frame(width: diameter, height: diameter)
            .background {
                Circle().fill(tint.opacity(0.12)).widgetAccentable()
            }
            .overlay {
                Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1)
            }
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
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
    AppleWidgetLocalization.text(key, languageCode: language)
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
