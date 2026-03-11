//
//  ContentView.swift
//  MapCompanion
//
//  Created by Miguel Ángel Cofrancesco on 10/3/26.
//

import SwiftUI
import MapKit
import Combine

struct ContentView: View {
    @StateObject private var locationManager = HeadingLocationManager()
    @State private var cameraPosition: MapCameraPosition = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090), distance: 300, heading: 0, pitch: 55))
    @State private var lastCoordinate: CLLocationCoordinate2D? = nil

    // Camera smoothing state
    @State private var currentCenter: CLLocationCoordinate2D? = nil
    @State private var targetCenter: CLLocationCoordinate2D? = nil
    @State private var currentHeading: CLLocationDirection = 0
    @State private var targetHeading: CLLocationDirection = 0
    @State private var currentDistance: CLLocationDistance = 300
    @State private var targetDistance: CLLocationDistance = 300
    @State private var mapPitch: CGFloat = 55

    // Dead reckoning state
    @State private var lastFixCoordinate: CLLocationCoordinate2D? = nil
    @State private var lastFixDate: Date? = nil
    @State private var currentSpeedMS: CLLocationSpeed = 0
    @State private var currentCourseDeg: CLLocationDirection = 0
    @State private var filteredSpeedMS: CLLocationSpeed = 0
    @State private var prevFixDate: Date? = nil
    @State private var prevFixSpeedMS: CLLocationSpeed = 0
    @State private var prevFixCourseDeg: CLLocationDirection = 0

    // 60 FPS update loop for continuous camera movement
    @State private var displayLink = Timer.publish(every: 1.0/60.0, on: .main, in: .common).autoconnect()
    @State private var lastTick: Date? = nil

    private let fallbackCoordinate = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090) // Apple Park

    var body: some View {
        ZStack {
            Map(position: $cameraPosition, interactionModes: []) {
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic, showsTraffic: false))
            .allowsHitTesting(false)
            .overlay {
                GeometryReader { geo in
                    let size = min(geo.size.width, geo.size.height)
                    let circleRect = CGRect(x: (geo.size.width - size) / 2, y: (geo.size.height - size) / 2, width: size, height: size)
                    let ringWidth: CGFloat = max(6, size * 0.02)
                    let tickOuterRadius = size * 0.5 - ringWidth * 0.5
                    let tickInnerRadiusMajor = tickOuterRadius - max(14, ringWidth * 1.4)
                    let tickInnerRadiusMinor = tickOuterRadius - max(8, ringWidth * 0.9)

                    ZStack {
                        // Outer neon gradient rim
                        Circle()
                            .strokeBorder(
                                AngularGradient(gradient: Gradient(colors: [.cyan, .blue, .purple, .pink, .cyan]), center: .center),
                                lineWidth: ringWidth
                            )
                            .frame(width: circleRect.width, height: circleRect.height)
                            .position(x: circleRect.midX, y: circleRect.midY)
                            .shadow(color: .cyan.opacity(0.5), radius: 12)
                            .shadow(color: .purple.opacity(0.4), radius: 24)

                        // Subtle outer halo
                        Circle()
                            .stroke(LinearGradient(colors: [.cyan.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom), lineWidth: ringWidth * 0.6)
                            .blur(radius: 8)
                            .frame(width: circleRect.width * 1.02, height: circleRect.height * 1.02)
                            .position(x: circleRect.midX, y: circleRect.midY)
                            .blendMode(.plusLighter)

                        // Inner glass sheen
                        Circle()
                            .fill(
                                RadialGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.02), Color.clear], center: .top, startRadius: 0, endRadius: size * 0.55)
                            )
                            .frame(width: circleRect.width * 0.96, height: circleRect.height * 0.96)
                            .position(x: circleRect.midX, y: circleRect.midY)
                            .blur(radius: 2)
                            .blendMode(.screen)

                        // Tick marks around the ring
                        TickMarksView(size: size, outerRadius: tickOuterRadius, innerRadiusMajor: tickInnerRadiusMajor, innerRadiusMinor: tickInnerRadiusMinor)
                            .frame(width: circleRect.width, height: circleRect.height)
                            .position(x: circleRect.midX, y: circleRect.midY)
                    }
                }
            }
            .mask {
                GeometryReader { geo in
                    let size = min(geo.size.width, geo.size.height)
                    Circle().frame(width: size, height: size).position(x: geo.size.width/2, y: geo.size.height/2)
                }
            }
            .overlay {
                GeometryReader { geo in
                    let isPortrait = geo.size.height >= geo.size.width
                    let size = min(geo.size.width, geo.size.height)
                    let padding = max(12, size * 0.04)

                    if isPortrait {
                        // Portrait: one centered above the circle, one centered below
                        VStack {
                            SpeedBadge(speedMS: filteredSpeedMS)
                                .padding(.top, padding)
                            Spacer()
                            ClockBadge()
                                .padding(.bottom, padding)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Landscape: keep them on the top corners
                        HStack {
                            SpeedBadge(speedMS: filteredSpeedMS)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ClockBadge()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.horizontal, padding)
                        .padding(.top, padding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)

            // Center arrow pointing up (player heading constant up) with 3D pitch effect
            ArrowIndicator(pitch: mapPitch)
                .frame(width: 42, height: 42)
                .rotation3DEffect(.degrees(Double(mapPitch) * 0.25), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.6)
                .scaleEffect(1 + (mapPitch - 45) / 300)
                .foregroundStyle(LinearGradient(colors: [.white, .cyan], startPoint: .top, endPoint: .bottom))
                .shadow(color: .cyan.opacity(0.8), radius: 10, x: 0, y: 0)
                .overlay {
                    Circle().stroke(Color.cyan.opacity(0.4), lineWidth: 2).blur(radius: 2)
                }
        }
        .onAppear {
            // Initialize camera to fallback; real values will come from location updates
            currentCenter = fallbackCoordinate
            targetCenter = fallbackCoordinate
            currentHeading = 0
            targetHeading = 0
            currentDistance = 300
            targetDistance = 300
            mapPitch = 55
            let camera = MapCamera(centerCoordinate: fallbackCoordinate, distance: currentDistance, heading: currentHeading, pitch: mapPitch)
            cameraPosition = .camera(camera)
        }
        .onReceive(locationManager.$location) { location in
            guard let loc = location else { return }
            // Update target center
            let coord = loc.coordinate
            let speed = max(loc.speed, 0)

            // Compute heading from course if valid, otherwise from last coordinate delta; prefer magnetometer when moving slowly
            var newHeading: CLLocationDirection = currentHeading
            if loc.course >= 0 { // valid course in degrees
                newHeading = loc.course
            } else if let last = lastCoordinate {
                newHeading = bearing(from: last, to: coord)
            }
            if speed < 1.5, let hdg = locationManager.heading?.trueHeading, hdg >= 0 { // fallback to compass when nearly stopped
                newHeading = hdg
            }
            targetCenter = coord
            targetHeading = newHeading
            lastCoordinate = coord

            // Shift previous fix
            prevFixDate = lastFixDate
            prevFixSpeedMS = currentSpeedMS
            prevFixCourseDeg = currentCourseDeg

            // Store fix for dead-reckoning
            lastFixCoordinate = coord
            lastFixDate = Date()
            currentSpeedMS = speed
            currentCourseDeg = newHeading

            // Initialize current state on first fix
            if currentCenter == nil {
                currentCenter = coord
                currentHeading = newHeading
                currentDistance = targetDistance
                filteredSpeedMS = speed
            }
        }
        .onReceive(displayLink) { now in
            // Compute delta time
            let dt: TimeInterval
            if let last = lastTick {
                dt = now.timeIntervalSince(last)
            } else {
                dt = 1.0/60.0
            }
            lastTick = now

            // Smoothing time constants (seconds)
            let tauPos: Double = 0.25
            let tauHeading: Double = 0.25
            let tauDistance: Double = 0.35
            let tauSpeed: Double = 0.40

            // Convert to alpha per frame
            let alphaPos = 1 - exp(-dt / tauPos)
            let alphaHeading = 1 - exp(-dt / tauHeading)
            let alphaDistance = 1 - exp(-dt / tauDistance)
            let alphaSpeed = 1 - exp(-dt / tauSpeed)

            // Predict heading and speed between fixes (angular velocity + acceleration)
            let elapsedSinceFix: TimeInterval = lastFixDate.map { max(now.timeIntervalSince($0), 0) } ?? 0
            var predictedHeading = currentCourseDeg
            if let prevDate = prevFixDate, let lastDate = lastFixDate {
                let dtFix = max(lastDate.timeIntervalSince(prevDate), 0.001)
                let deltaCourse = shortestAngleDelta(from: prevFixCourseDeg, to: currentCourseDeg)
                let omega = deltaCourse / dtFix // deg per second
                predictedHeading = normalizedAngle(currentCourseDeg + omega * elapsedSinceFix)
            }

            var predictedSpeed = currentSpeedMS
            if let prevDate = prevFixDate, let lastDate = lastFixDate {
                let dtFix = max(lastDate.timeIntervalSince(prevDate), 0.001)
                let accel = (currentSpeedMS - prevFixSpeedMS) / dtFix
                predictedSpeed = max(0, currentSpeedMS + accel * elapsedSinceFix)
            }

            // Desired heading each frame: only predict at high speed, otherwise no prediction
            let low: CLLocationSpeed = 0.5
            let high: CLLocationSpeed = 3.0
            let usePrediction = predictedSpeed >= high
            let baseCourse = usePrediction ? predictedHeading : currentCourseDeg
            var desiredHeading = baseCourse
            if let compass = locationManager.heading?.trueHeading, compass >= 0 {
                // Weight: 1 at very baja velocidad, 0 a alta velocidad
                let w = max(0, min(1, (high - predictedSpeed) / max(high - low, 0.001)))
                desiredHeading = angleLerp(from: baseCourse, to: compass, t: w)
            }
            targetHeading = desiredHeading

            // Predict target center via dead-reckoning using desired heading and predicted speed
            var desiredCenter = targetCenter
            if let fix = lastFixCoordinate {
                let distance = predictedSpeed * elapsedSinceFix
                desiredCenter = project(from: fix, bearing: desiredHeading, distanceMeters: distance)
            }

            // Interpolate center toward desired center
            if let tCenter = desiredCenter {
                if currentCenter == nil {
                    currentCenter = tCenter
                } else if var c = currentCenter {
                    c.latitude += (tCenter.latitude - c.latitude) * alphaPos
                    c.longitude += (tCenter.longitude - c.longitude) * alphaPos
                    currentCenter = c
                }
            }

            // Interpolate heading with slew-rate limit to avoid jumps
            let hDelta = shortestAngleDelta(from: currentHeading, to: targetHeading)
            let maxRate: CLLocationDirection = 120 // deg per second
            let maxStep = maxRate * dt
            var step = hDelta * alphaHeading
            if step > maxStep { step = maxStep }
            if step < -maxStep { step = -maxStep }
            currentHeading = normalizedAngle(currentHeading + step)

            // Interpolate speed and derive distance target continuously
            filteredSpeedMS += (predictedSpeed - filteredSpeedMS) * alphaSpeed
            let desiredDistance = distance(for: filteredSpeedMS)
            currentDistance += (desiredDistance - currentDistance) * alphaDistance

            // Build and apply camera without implicit SwiftUI animation
            let center = currentCenter ?? fallbackCoordinate
            let camera = MapCamera(centerCoordinate: center, distance: currentDistance, heading: currentHeading, pitch: mapPitch)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                cameraPosition = .camera(camera)
            }
        }
    }
    
    private func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let lon2 = to.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        var brng = atan2(y, x) * 180 / .pi
        if brng < 0 { brng += 360 }
        return brng
    }

    private func project(from: CLLocationCoordinate2D, bearing: CLLocationDirection, distanceMeters: CLLocationDistance) -> CLLocationCoordinate2D {
        let R = 6_371_000.0 // Earth radius in meters
        let brng = bearing * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(distanceMeters / R) + cos(lat1) * sin(distanceMeters / R) * cos(brng))
        let lon2 = lon1 + atan2(sin(brng) * sin(distanceMeters / R) * cos(lat1), cos(distanceMeters / R) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    private func normalizedAngle(_ angle: CLLocationDirection) -> CLLocationDirection {
        var a = angle.truncatingRemainder(dividingBy: 360)
        if a < 0 { a += 360 }
        return a
    }

    private func shortestAngleDelta(from: CLLocationDirection, to: CLLocationDirection) -> CLLocationDirection {
        let a = normalizedAngle(from)
        let b = normalizedAngle(to)
        var delta = b - a
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    private func angleLerp(from: CLLocationDirection, to: CLLocationDirection, t: Double) -> CLLocationDirection {
        let delta = shortestAngleDelta(from: from, to: to)
        return normalizedAngle(from + delta * t)
    }

    private func distance(for speed: CLLocationSpeed) -> CLLocationDistance {
        // speed in m/s; map 0..44 m/s (~0..158 km/h) to 150..800 meters
        let minSpeed: CLLocationSpeed = 0
        let maxSpeed: CLLocationSpeed = 44 // ~158 km/h
        let minDist: CLLocationDistance = 150
        let maxDist: CLLocationDistance = 800
        let clamped = max(min(speed, maxSpeed), minSpeed)
        let t = clamped / (maxSpeed - minSpeed)
        return minDist + (maxDist - minDist) * t
    }
}

struct ArrowIndicator: View {
    var pitch: CGFloat

    var body: some View {
        ZStack {
            // Glow aura
            Circle()
                .fill(RadialGradient(colors: [.cyan.opacity(0.30), .clear], center: .center, startRadius: 2, endRadius: 34))

            // Arrow body with beveled lighting
            ArrowShape()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.9), Color.cyan.opacity(0.85), Color.purple.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    ArrowShape()
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        .blur(radius: 0.5)
                        .blendMode(.screen)
                )
                .shadow(color: .cyan.opacity(0.7), radius: 8, x: 0, y: 4)
                .shadow(color: .purple.opacity(0.5), radius: 12, x: 0, y: 8)
                .modifier(ArrowInnerShadow())

            // Top highlight simulating reflection depending on pitch
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                .frame(width: 18, height: max(2, 8 - (pitch - 20) * 0.08))
                .offset(y: -12)
                .blur(radius: 0.5)
                .blendMode(.screen)
        }
        .compositingGroup()
        .blendMode(.screen)
    }
}

struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let tip = CGPoint(x: w/2, y: 0)
        let left = CGPoint(x: 0, y: h*0.65)
        let right = CGPoint(x: w, y: h*0.65)
        let tailTop = CGPoint(x: w*0.6, y: h*0.65)
        let tailBottom = CGPoint(x: w*0.6, y: h)
        let tailLeft = CGPoint(x: w*0.4, y: h)
        let tailLeftTop = CGPoint(x: w*0.4, y: h*0.65)

        p.move(to: tip)
        p.addLine(to: left)
        p.addLine(to: tailLeftTop)
        p.addLine(to: tailLeft)
        p.addLine(to: tailBottom)
        p.addLine(to: tailTop)
        p.addLine(to: right)
        p.closeSubpath()
        return p
    }
}

struct ArrowInnerShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlay(
                ArrowShape()
                    .stroke(Color.black.opacity(0.35), lineWidth: 6)
                    .blur(radius: 4)
                    .offset(y: 2)
                    .mask(ArrowShape().fill(LinearGradient(colors: [.black, .clear], startPoint: .bottom, endPoint: .top)))
            )
    }
}

struct TickMarksView: View {
    let size: CGFloat
    let outerRadius: CGFloat
    let innerRadiusMajor: CGFloat
    let innerRadiusMinor: CGFloat

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let majorCount = 12
            let minorPerMajor = 5
            let totalMinor = majorCount * minorPerMajor

            func point(angle: CGFloat, radius: CGFloat) -> CGPoint {
                CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius
                )
            }

            // Minor ticks
            for i in 0..<totalMinor {
                let isMajor = i % minorPerMajor == 0
                let a = (CGFloat(i) / CGFloat(totalMinor)) * .pi * 2 - .pi/2
                let r1 = outerRadius
                let r2 = isMajor ? innerRadiusMajor : innerRadiusMinor
                var path = Path()
                path.move(to: point(angle: a, radius: r1))
                path.addLine(to: point(angle: a, radius: r2))
                let stroke = StrokeStyle(lineWidth: isMajor ? 2.0 : 1.0, lineCap: .round)
                context.stroke(path, with: .color(isMajor ? .cyan : .white.opacity(0.7)), style: stroke)
            }
        }
    }
}

struct SpeedometerView: View {
    let speedMS: CLLocationSpeed
    let radius: CGFloat

    private var speedKmh: Int { Int(max(0, speedMS) * 3.6 + 0.5) }

    var body: some View {
        ZStack {
            // Background arc to host the label
            ArcTextBackground(radius: radius, angleStart: -110, angleEnd: -70)
                .fill(Color.black.opacity(0.35))
                .blur(radius: 2)
                .overlay(
                    ArcText(text: "\(speedKmh) km/h", radius: radius, angle: -90)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [.white, .cyan], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .cyan.opacity(0.6), radius: 4)
                )
        }
    }
}

struct ClockOnRingView: View {
    let radius: CGFloat
    let angleDegrees: CGFloat

    var body: some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let time = formatter.string(from: Date())

        return ArcTextBackground(radius: radius, angleStart: 70, angleEnd: 110)
            .fill(Color.black.opacity(0.35))
            .blur(radius: 2)
            .overlay(
                ArcText(text: time, radius: radius, angle: 90)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, .pink], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .pink.opacity(0.6), radius: 4)
            )
    }
}

// Helpers to render text along an arc
struct ArcTextBackground: Shape {
    let radius: CGFloat
    let angleStart: CGFloat
    let angleEnd: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        p.addArc(center: center, radius: radius, startAngle: .degrees(angleStart), endAngle: .degrees(angleEnd), clockwise: false)
        return p.strokedPath(StrokeStyle(lineWidth: 18, lineCap: .round))
    }
}

struct ArcText: View {
    let text: String
    let radius: CGFloat
    let angle: CGFloat // center angle in degrees where text is placed

    var body: some View {
        Text(text)
            .kerning(0.5)
            .modifier(ArcPositionModifier(radius: radius, angleDegrees: angle))
    }
}

struct ArcPositionModifier: ViewModifier {
    let radius: CGFloat
    let angleDegrees: CGFloat

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let rad = angleDegrees * .pi / 180
            let pos = CGPoint(x: center.x + cos(rad) * radius, y: center.y + sin(rad) * radius)
            content
                .position(pos)
                .rotationEffect(.degrees(angleDegrees + 90))
        }
    }
}

struct SpeedBadge: View {
    let speedMS: CLLocationSpeed
    private var speedKmh: Int { Int(max(0, speedMS) * 3.6 + 0.5) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.medium")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white.opacity(0.9), .cyan)
                .imageScale(.large)
                .font(.system(size: 18, weight: .semibold))
            Text("\(speedKmh) km/h")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().stroke(LinearGradient(colors: [.cyan.opacity(0.6), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                )
        )
        .shadow(color: .cyan.opacity(0.35), radius: 8, x: 0, y: 6)
    }
}

struct ClockBadge: View {
    @State private var now: Date = Date()
    private var formatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white.opacity(0.9), .pink)
                .imageScale(.large)
                .font(.system(size: 18, weight: .semibold))
            Text(formatter.string(from: now))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().stroke(LinearGradient(colors: [.pink.opacity(0.6), .purple.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                )
        )
        .shadow(color: .pink.opacity(0.35), radius: 8, x: 0, y: 6)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0 }
    }
}

#Preview {
    ContentView()
}

