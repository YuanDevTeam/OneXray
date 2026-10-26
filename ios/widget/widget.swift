import SwiftUI
import WidgetKit
import AppIntents

private let connectionURL = URL(string: "onexray://widget/connect")!

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
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

private struct ConnectionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ConnectionWidgetEntry

    var body: some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(.fill.tertiary, for: .widget)
        } else {
            content.padding().background(Color(.systemBackground))
        }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: statusIcon).font(.title2)
            }
            .privacySensitive()
            .accessibilityLabel("OneXray, \(statusText)")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                Text("OneXray").font(.headline)
                Label(statusText, systemImage: statusIcon).font(.caption).privacySensitive()
                Text(text("Open app")).font(.caption2)
            }
        case .systemMedium:
            HStack(spacing: 16) {
                Link(destination: connectionURL) {
                    summary
                }
                .buttonStyle(.plain)
                .accessibilityLabel("OneXray, \(statusText), \(text("Open app"))")
                Spacer(minLength: 0)
                if #available(iOS 17.0, *) {
                    actions(compact: false)
                } else {
                    Label(text("Open app"), systemImage: "arrow.up.forward.app").font(.callout)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                summary
                if #available(iOS 17.0, *) {
                    actions(compact: true)
                } else {
                    Label(text("Open app"), systemImage: "arrow.up.forward.app").font(.caption)
                }
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OneXray").font(.caption).foregroundStyle(.secondary)
            Label(statusText, systemImage: statusIcon)
                .font(.headline)
                .foregroundStyle(entry.status == .connected ? Color.green : Color.primary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .privacySensitive()
            if let snapshot = entry.snapshot {
                HStack(spacing: 3) {
                    Text(text("Observed"))
                    Text(snapshot.observedAt, style: .time)
                }
                .font(.caption2).foregroundStyle(.secondary).privacySensitive()
            } else {
                Text(text("Open app to refresh")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @available(iOS 17.0, *)
    @ViewBuilder private func actions(compact: Bool) -> some View {
        if compact {
            HStack(spacing: 8) {
                Button(intent: StartVpnWidgetIntent()) {
                    Image(systemName: "play.fill").frame(maxWidth: .infinity, minHeight: 44)
                        .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }.accessibilityLabel(text("Start VPN"))
                Button(intent: StopVpnWidgetIntent()) {
                    Image(systemName: "stop.fill").frame(maxWidth: .infinity, minHeight: 44)
                        .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }.accessibilityLabel(text("Stop VPN"))
            }
            .buttonStyle(.plain)
        } else {
            VStack(spacing: 8) {
                Button(intent: StartVpnWidgetIntent()) {
                    Label(text("Start VPN"), systemImage: "play.fill")
                        .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 44)
                        .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }
                Button(intent: StopVpnWidgetIntent()) {
                    Label(text("Stop VPN"), systemImage: "stop.fill")
                        .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 44)
                        .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .font(.caption).buttonStyle(.plain)
        }
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
        case .connected: "checkmark.shield.fill"
        case .connecting, .disconnecting: "arrow.triangle.2.circlepath"
        case .disconnected: "shield"
        case .unknown: "questionmark.circle"
        }
    }

    private func text(_ key: String) -> String { widgetText(key, entry.languageCode) }
}

private func widgetText(_ key: String, _ language: String) -> String {
    let path = Bundle.main.path(forResource: AppleWidgetLanguage.normalized(language), ofType: "lproj")
    let bundle = path.flatMap(Bundle.init(path:)) ?? Bundle.main
    return bundle.localizedString(forKey: key, value: key, table: "Widget")
}

struct ConnectionWidgetPreviews: PreviewProvider {
    static var previews: some View {
        ForEach([WidgetFamily.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular], id: \.self) { family in
            ConnectionWidgetView(entry: ConnectionWidgetEntry(
                date: Date(), snapshot: AppleWidgetSnapshot(status: .connected), languageCode: "en"
            ))
            .previewContext(WidgetPreviewContext(family: family))
        }
    }
}
