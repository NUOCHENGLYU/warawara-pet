import AppKit
import CoreVideo
import Darwin
import SwiftUI

/// One rendered meteor frame: head pose + dynamic trail segments in
/// PANEL-local coordinates (y-down).
struct MeteorTrailSegment: Equatable, Identifiable {
    let id: Int
    var points: [CGPoint]
    var opacity: CGFloat
    var width: CGFloat
    var colorIndex: Int
}

struct MeteorSparkle: Equatable, Identifiable {
    let id: Int
    var position: CGPoint
    var opacity: CGFloat
    var size: CGFloat
}

struct MeteorSceneFrame: Equatable {
    var headRotation: CGFloat = 0
    var headAlpha: CGFloat = 1
    var trailSegments: [MeteorTrailSegment] = []
    var sparkles: [MeteorSparkle] = []
}

final class MeteorSceneState: ObservableObject {
    @Published var frame = MeteorSceneFrame()
}

/// Production realization of the meteor event:
/// - ONE pooled, click-through, transparent panel that follows the
///   FIXED world-space trajectory (never attached to the pet window);
/// - ONE movement authority: the display-synced render loop drives
///   position, trail and gaze from the controller's single monotonic
///   timebase (the 4 Hz scheduler only manages phases);
/// - the tail is DYNAMIC: a short world-space history of the head,
///   drawn as warm-gold strands and sparse deterministic sparkles that
///   fade by age — no rigid baked tail sprite;
/// - exact cleanup: alpha zero, parked off-screen, history cleared.
final class MeteorEventPresenter: MeteorEventPresenting {
    private weak var windowController: PetWindowController?
    private weak var controller: MeteorEventController?
    private let store: GiftAssetStore

    private var panel: BirthdayPropPanel?
    private var displayLink: CVDisplayLink?
    private var timer: Timer?
    private var sampler: MeteorTrajectorySampler?
    private var attentionDirection: CGVector?
    private var cleanupDone = false
    private var lastFrameLog = Date(timeIntervalSince1970: 0)
    private let sceneState = MeteorSceneState()

    /// World-space history of the head: (uptime, position). The trail is
    /// derived from this — never accumulated incrementally.
    private struct HistoryPoint {
        var uptime: TimeInterval
        var position: CGPoint
    }
    private var history: [HistoryPoint] = []

    // Trail tuning (visual constants only).
    private let trailMaxAge: TimeInterval = 0.9
    private let historyCapacity = 60
    private let strandCount = 5
    private let sparkleCount = 8
    private var sparklePhase: [CGFloat] = []

    /// Accepted apparent star size (points) and the head crop's painted
    /// star width (source px, from the asset manifest).
    private let headStarTargetPt: CGFloat = 36
    private let headStarSourcePx: CGFloat = 125
    private let headCropPx: CGFloat = 408

    /// Panel fits the head plus the full trail length behind it.
    private let panelSize = CGSize(width: 360, height: 360)

    /// Test access to the production panel.
    var debugPanel: BirthdayPropPanel? { panel }
    /// Test access to the trail history.
    var debugHistoryCount: Int { history.count }
    /// Test access to the current scene frame.
    var debugSceneFrame: MeteorSceneFrame { sceneState.frame }

    init(
        windowController: PetWindowController,
        controller: MeteorEventController,
        store: GiftAssetStore = .shared
    ) {
        self.windowController = windowController
        self.controller = controller
        self.store = store
        // Deterministic per-sparkle phase offsets (never re-rolled).
        sparklePhase = (0..<sparkleCount).map { index in
            CGFloat((index * 37 % 100)) / 100.0
        }
    }

    var activeVisibleFrame: CGRect {
        ScreenGeometry.visibleFrame(for: windowController?.currentFrame ?? .zero)
    }

    // MARK: - MeteorEventPresenting

    func noticeScene() {
        cleanupDone = false
        guard let petFrame = windowController?.currentFrame, petFrame != .zero else { return }
        let body = BirthdayPropLayout.petBodyRect(petFrame: petFrame)
        let direction = EventAttentionMath.direction(
            from: CGPoint(x: body.midX, y: body.midY),
            to: CGPoint(x: petFrame.minX - 120, y: activeVisibleFrame.maxY * 0.78)
        )
        if direction != .zero {
            attentionDirection = direction
            windowController?.setEventAttention(direction)
        }
    }

    func flightDidBegin(trajectory: MeteorTrajectory) {
        sampler = MeteorTrajectorySampler(trajectory: trajectory)
        history.removeAll()
        let visible = activeVisibleFrame
        EventDiagnostics.emit(String(
            format: "METEOR_PATH_RESOLVED entry=%.0f,%.0f exit=%.0f,%.0f visible=%.0fx%.0f",
            trajectory.entry.x, trajectory.entry.y,
            trajectory.exit.x, trajectory.exit.y,
            visible.width, visible.height
        ))
        ensurePanel()
        startRenderLoop()
    }

    func meteorDeparted() {
        // The meteor is fully beyond the display: hold the gaze toward
        // the exit direction for the departed beat.
        if let sampler {
            let exit = sampler.position(atArcLength: 1)
            let direction = EventAttentionMath.direction(from: petBodyCenter, to: exit)
            if direction != .zero {
                attentionDirection = direction
                windowController?.setEventAttention(direction)
            }
        }
        panel?.alphaValue = 0
        EventDiagnostics.emit("METEOR_ALPHA alpha=0")
    }

    func wishingDidBegin() {
        attentionDirection = nil
        windowController?.setEventAttention(nil)
        windowController?.setWishing(true)
    }

    func celebrationDidBegin() {
        windowController?.setWishing(false)
        windowController?.performCelebrationHop()
    }

    func cleanup() {
        guard !cleanupDone else { return }
        cleanupDone = true
        stopRenderLoop()
        panel?.alphaValue = 0
        if let panel {
            let visible = activeVisibleFrame
            panel.setFrameOrigin(CGPoint(
                x: visible.minX + 40,
                y: visible.minY - panel.frame.height - 80
            ))
            EventDiagnostics.emit(String(
                format: "METEOR_CLEANED_UP frame=%.0f,%.0f alpha=%.2f",
                panel.frame.minX, panel.frame.minY, panel.alphaValue
            ))
        }
        history.removeAll()
        sceneState.frame = MeteorSceneFrame()
        sampler = nil
        attentionDirection = nil
        windowController?.setEventAttention(nil)
        windowController?.setWishing(false)
    }

    private var petBodyCenter: CGPoint {
        guard let petFrame = windowController?.currentFrame else { return .zero }
        let body = BirthdayPropLayout.petBodyRect(petFrame: petFrame)
        return CGPoint(x: body.midX, y: body.midY)
    }

    // MARK: - Display-synced render loop (the sole movement authority)

    private var timebaseInfo = mach_timebase_info_data_t()

    private func startRenderLoop() {
        stopRenderLoop()
        mach_timebase_info(&timebaseInfo)
        var link: CVDisplayLink?
        let result = CVDisplayLinkCreateWithActiveCGDisplays(&link)
        if let link, result == kCVReturnSuccess {
            CVDisplayLinkSetOutputHandler(link) { [weak self] _, inNow, _, _, _ in
                guard let self else { return kCVReturnSuccess }
                let uptime = self.hostTimeToSeconds(inNow.pointee.hostTime)
                DispatchQueue.main.async {
                    self.renderTick(uptime: uptime)
                }
                return kCVReturnSuccess
            }
            CVDisplayLinkStart(link)
            displayLink = link
            EventDiagnostics.emit("METEOR_RENDER_LOOP display-link")
        } else {
            // Headless/CI fallback: a 60 Hz timer on the same monotonic
            // clock. Movement is a pure function of uptime either way.
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                self?.renderTick(uptime: ProcessInfo.processInfo.systemUptime)
            }
            EventDiagnostics.emit("METEOR_RENDER_LOOP timer-fallback")
        }
    }

    private func stopRenderLoop() {
        if let displayLink {
            CVDisplayLinkStop(displayLink)
            self.displayLink = nil
        }
        timer?.invalidate()
        timer = nil
    }

    private func hostTimeToSeconds(_ hostTime: UInt64) -> TimeInterval {
        Double(hostTime) * Double(timebaseInfo.numer) / Double(timebaseInfo.denom) / 1_000_000_000
    }

    /// THE single frame update: position, trail and gaze all derive from
    /// the controller's one monotonic timebase. Pure function of uptime —
    /// dropped frames, delayed scheduler ticks and differing cadences can
    /// never reset or jump the position.
    func renderTick(uptime: TimeInterval) {
        guard let controller, let sampler, let panel else { return }
        guard let progress = controller.flightProgress(atUptime: uptime) else { return }

        let position = sampler.position(atArcLength: progress)
        let size = panel.frame.size
        panel.setFrameOrigin(CGPoint(
            x: position.x - size.width / 2,
            y: position.y - size.height / 2
        ))
        if panel.alphaValue < 0.99 {
            panel.alphaValue = 1
            EventDiagnostics.emit(String(
                format: "METEOR_ALPHA alpha=%.2f frame=%.0f,%.0f visible=%d level=%d",
                panel.alphaValue, panel.frame.minX, panel.frame.minY,
                panel.isVisible ? 1 : 0, Int(panel.level.rawValue)
            ))
        }
        let now = Date()
        if now.timeIntervalSince(lastFrameLog) >= 1 {
            lastFrameLog = now
            EventDiagnostics.emit(String(
                format: "METEOR_FRAME progress=%.2f x=%.0f y=%.0f",
                progress, position.x, position.y
            ))
        }

        // Trail history (world space; ages out deterministically).
        history.append(HistoryPoint(uptime: uptime, position: position))
        while history.count > historyCapacity {
            history.removeFirst()
        }
        let cutoff = uptime - trailMaxAge
        while let first = history.first, first.uptime < cutoff {
            history.removeFirst()
        }
        updateSceneFrame(headPosition: position, heading: sampler.heading(atArcLength: progress), uptime: uptime)

        // Continuous attention tracking from the SAME position/timeline.
        let direction = EventAttentionMath.direction(from: petBodyCenter, to: position)
        if direction != .zero {
            if attentionDirection == nil {
                attentionDirection = direction
                windowController?.setEventAttention(direction)
            } else if direction != attentionDirection {
                attentionDirection = direction
                windowController?.updateEventAttention(direction)
            }
        }
    }

    // MARK: - Dynamic trail construction (deterministic)

    private func updateSceneFrame(headPosition: CGPoint, heading: CGFloat, uptime: TimeInterval) {
        guard let panel else { return }
        let panelMinX = panel.frame.minX
        let panelMaxY = panel.frame.maxY

        func toPanel(_ world: CGPoint) -> CGPoint {
            CGPoint(x: world.x - panelMinX, y: panelMaxY - world.y)
        }

        var segments: [MeteorTrailSegment] = []
        let points = history.map { $0.position }
        guard points.count >= 3 else {
            sceneState.frame = MeteorSceneFrame(headRotation: heading * 180 / .pi + 15, headAlpha: 1)
            return
        }
        for strand in 0..<strandCount {
            let baseOffset = strand * 3
            let length = 10 + strand * 4
            let end = points.count - 1 - baseOffset
            let start = max(0, end - length)
            guard end > start else { continue }
            var strandPoints: [CGPoint] = []
            var index = start
            while index <= end {
                strandPoints.append(toPanel(points[index]))
                index += 2
            }
            guard strandPoints.count >= 2 else { continue }
            let newestAge = uptime - history[end].uptime
            let ageFade = CGFloat(max(0, 1 - newestAge / trailMaxAge))
            segments.append(MeteorTrailSegment(
                id: strand,
                points: strandPoints,
                opacity: (0.16 + 0.10 * CGFloat(strand)) * ageFade,
                width: 2.8 - 0.4 * CGFloat(strand),
                colorIndex: strand % 2
            ))
        }

        var sparkles: [MeteorSparkle] = []
        for index in 0..<sparkleCount {
            let historyIndex = max(0, points.count - 1 - (index * 5 + 3))
            let anchor = points[historyIndex]
            let age = uptime - history[historyIndex].uptime
            let lifetime: CGFloat = 0.5
            let phase = (sparklePhase[index] + CGFloat(age / Double(lifetime))).truncatingRemainder(dividingBy: 1)
            let opacity = max(0, sin(phase * .pi)) * CGFloat(max(0, 1 - age / trailMaxAge))
            guard opacity > 0.01 else { continue }
            let perpDx: CGFloat = index % 2 == 0 ? 6 : -6
            let perpDy: CGFloat = (index * 11) % 14 - 7
            sparkles.append(MeteorSparkle(
                id: index,
                position: toPanel(CGPoint(x: anchor.x + perpDx, y: anchor.y + perpDy)),
                opacity: opacity * 0.85,
                size: 5 + CGFloat(index % 3) * 2
            ))
        }

        sceneState.frame = MeteorSceneFrame(
            headRotation: heading * 180 / .pi + 15,
            headAlpha: 1,
            trailSegments: segments,
            sparkles: sparkles
        )
    }

    // MARK: - Panel

    private func ensurePanel() {
        guard panel == nil else { return }
        // ONE consistent source-pixel-to-point scale for the approved
        // head crop (408 px, star ≈125 px) at the accepted apparent star
        // size (~36 pt).
        let scale = headStarTargetPt / headStarSourcePx
        let headCanvasPt = headCropPx * scale
        let newPanel = BirthdayPropPanel(size: panelSize, interactive: false)
        if store.image(named: "meteor_head_from_approved.png") != nil {
            let hosting = NSHostingView(rootView: MeteorSceneView(
                state: sceneState,
                headImage: store.image(named: "meteor_head_from_approved.png"),
                sparkleImage: store.image(named: "meteor_sparkle_from_approved.png"),
                headCanvasSize: CGSize(width: headCanvasPt, height: headCanvasPt)
            ))
            hosting.frame = NSRect(origin: .zero, size: panelSize)
            newPanel.contentView = hosting
        }
        newPanel.alphaValue = 0
        panel = newPanel
        if let screen = newPanel.screen {
            EventDiagnostics.emit(String(
                format: "METEOR_RENDER_DEBUG headCanvas=%.1f scale=%.4f backingScale=%.2f panelFrame=%.0f,%.0f,%.0f,%.0f",
                headCanvasPt, scale, screen.backingScaleFactor,
                newPanel.frame.minX, newPanel.frame.minY,
                newPanel.frame.width, newPanel.frame.height
            ))
        }
        EventDiagnostics.emit(String(
            format: "METEOR_PANEL_CREATED size=%.0fx%.0f contentView=%d",
            panelSize.width, panelSize.height, newPanel.contentView != nil ? 1 : 0
        ))
        // A brand-new NSPanel is invisible until ordered front.
        newPanel.orderFrontRegardless()
        EventDiagnostics.emit("METEOR_ORDERED_FRONT")
    }
}

/// The meteor scene: dynamic Canvas-drawn trail + the approved head
/// sprite. No rigid baked-tail image, no giant alpha rectangles.
struct MeteorSceneView: View {
    @ObservedObject var state: MeteorSceneState
    let headImage: NSImage?
    let sparkleImage: NSImage?
    let headCanvasSize: CGSize

    private let warmGold = Color(red: 1.0, green: 0.82, blue: 0.45)
    private let cream = Color(red: 1.0, green: 0.94, blue: 0.80)

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            // Restrained soft glow behind the head.
            let glowRect = CGRect(
                x: center.x - 46, y: center.y - 46, width: 92, height: 92
            )
            context.fill(
                Path(ellipseIn: glowRect),
                with: .radialGradient(
                    Gradient(colors: [
                        warmGold.opacity(0.34),
                        warmGold.opacity(0.0)
                    ]),
                    center: center,
                    startRadius: 4,
                    endRadius: 46
                )
            )

            // Dynamic strands (oldest segments fade first).
            for segment in state.frame.trailSegments {
                guard segment.points.count >= 2 else { continue }
                var path = Path()
                path.move(to: segment.points[0])
                for point in segment.points.dropFirst() {
                    path.addLine(to: point)
                }
                let color = segment.colorIndex == 0 ? warmGold : cream
                context.stroke(
                    path,
                    with: .color(color.opacity(Double(segment.opacity))),
                    style: StrokeStyle(
                        lineWidth: segment.width,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }

            // Sparse sparkles with individual lifetimes (feathered via
            // the sparkle image's own soft alpha).
            if let sparkleImage {
                let sparkle = Image(nsImage: sparkleImage)
                for s in state.frame.sparkles {
                    var sparkleContext = context
                    sparkleContext.opacity = Double(s.opacity)
                    sparkleContext.draw(
                        sparkle,
                        in: CGRect(
                            x: s.position.x - s.size / 2,
                            y: s.position.y - s.size / 2,
                            width: s.size,
                            height: s.size
                        )
                    )
                }
            }

            // The approved painted star head, aligned to the heading.
            if let headImage {
                var head = context
                head.translateBy(x: center.x, y: center.y)
                head.rotate(by: .degrees(Double(state.frame.headRotation)))
                head.opacity = Double(state.frame.headAlpha)
                head.draw(
                    Image(nsImage: headImage),
                    in: CGRect(
                        x: -headCanvasSize.width / 2,
                        y: -headCanvasSize.height / 2,
                        width: headCanvasSize.width,
                        height: headCanvasSize.height
                    )
                )
            }
        }
        .frame(width: 360, height: 360)
    }
}
