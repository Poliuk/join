import SwiftUI
import JoinCore

/// What the Settings preview draws behind the alert, standing in for the user's screen.
enum AppearancePreviewBackdrop: String, CaseIterable, Identifiable {
    case wallpaper
    case lightApp
    case darkApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wallpaper: return "Wallpaper"
        case .lightApp: return "Light app"
        case .darkApp: return "Dark app"
        }
    }
}

/// The real alert content, zoomed in, over a sample screen. A window can't blur what's behind it
/// inside itself, so the sample screen is drawn already blurred and the material is a plain layer.
@MainActor
struct AppearancePreview: View {
    let appearance: AlertAppearance
    let backdrop: AppearancePreviewBackdrop
    let snoozeDurations: [TimeInterval]

    private static let scale: CGFloat = 0.52

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                AppearancePreviewScreen(backdrop: backdrop)
                if let material = appearance.palette.material {
                    Color(material)
                }
                AlertTintAndScrim(appearance: appearance, scrimSize: CGSize(width: 560, height: 340))
                AlertContentView(session: session, now: Self.sampleNow, isInteractive: false)
                    .frame(width: size.width / Self.scale, height: size.height / Self.scale)
                    .scaleEffect(Self.scale)
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(height: 320)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live preview of the alert")
    }

    private var session: AlertSession {
        AlertSession(
            meetings: [Self.sampleMeeting],
            appearance: appearance,
            snoozeDurations: snoozeDurations,
            actions: AlertActions(dismiss: {}, snooze: { _ in }, snoozeUntilEvent: {}, join: { _ in })
        )
    }

    private static var sampleStart: Date {
        Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date()) ?? Date()
    }

    /// Frozen at "Starts in 2:59".
    private static var sampleNow: Date { sampleStart.addingTimeInterval(-179) }

    private static var sampleMeeting: Meeting {
        Meeting(
            id: "preview",
            title: "Hello, I’m a demo event",
            start: sampleStart,
            end: sampleStart.addingTimeInterval(3600),
            calendarTitle: "Work",
            calendarColor: RGBA(rgb: 0x1A9FC0),
            location: "Conference Room A",
            joinURL: URL(string: "https://meet.google.com/abc-defg-hij")
        )
    }
}

/// Sample screens drawn in a 680 × 320 space and scaled to fill the preview.
private struct AppearancePreviewScreen: View {
    let backdrop: AppearancePreviewBackdrop

    private static let canvas = CGSize(width: 680, height: 320)

    var body: some View {
        GeometryReader { proxy in
            let scale = max(proxy.size.width / Self.canvas.width, proxy.size.height / Self.canvas.height)
            drawing
                .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
                .scaleEffect(scale)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(base)
        .clipped()
    }

    private var base: Color {
        switch backdrop {
        case .wallpaper: return Color(RGBA(rgb: 0x2A1640))
        case .lightApp: return Color(RGBA(rgb: 0xECECF0))
        case .darkApp: return Color(RGBA(rgb: 0x17181C))
        }
    }

    @ViewBuilder
    private var drawing: some View {
        switch backdrop {
        case .wallpaper:
            ZStack(alignment: .topLeading) {
                blob(0, 0, 420, 320, 0x7C3AED)
                blob(420, 20, 380, 300, 0xEA580C)
                blob(240, 220, 360, 220, 0xBE123C)
                blob(460, 240, 300, 220, 0x15803D)
            }
            .frame(width: 800, height: 440, alignment: .topLeading)
            .offset(x: -60, y: -60)
            .blur(radius: 44)
        case .lightApp:
            ZStack(alignment: .topLeading) {
                block(50, 26, 580, 290, 0xFFFFFF, radius: 10)
                    .shadow(color: .black.opacity(0.15), radius: 15, y: 8)
                block(80, 60, 260, 14, 0x1D1D1F)
                block(80, 96, 500, 8, 0xC9C9CF)
                block(80, 116, 460, 8, 0xC9C9CF)
                block(80, 150, 220, 130, 0xF2B36F, radius: 8)
                block(320, 150, 260, 8, 0xC9C9CF)
                block(320, 170, 200, 8, 0xC9C9CF)
                block(320, 200, 120, 24, 0x2F7CF6, radius: 6)
            }
            .blur(radius: 12)
        case .darkApp:
            ZStack(alignment: .topLeading) {
                block(40, 20, 600, 300, 0x282C34, radius: 10)
                block(70, 50, 180, 8, 0xC678DD)
                block(90, 74, 300, 8, 0x61AFEF)
                block(90, 98, 240, 8, 0x98C379)
                block(110, 122, 360, 8, 0xABB2BF)
                block(110, 146, 200, 8, 0xE5C07B)
                block(90, 170, 280, 8, 0x61AFEF)
                block(70, 194, 120, 8, 0xC678DD)
            }
            .blur(radius: 10)
        }
    }

    private func blob(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ rgb: UInt32) -> some View {
        Ellipse()
            .fill(Color(RGBA(rgb: rgb)))
            .frame(width: width, height: height)
            .offset(x: x, y: y)
    }

    private func block(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ rgb: UInt32, radius: CGFloat = 4) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color(RGBA(rgb: rgb)))
            .frame(width: width, height: height)
            .offset(x: x, y: y)
    }
}
