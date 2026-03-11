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
                // Circular mask
                GeometryReader { geo in
                    let size = min(geo.size.width, geo.size.height)
                    let circleRect = CGRect(x: (geo.size.width - size) / 2, y: (geo.size.height - size) / 2, width: size, height: size)
                    Circle()
                        .strokeBorder(AngularGradient(gradient: Gradient(colors: [.cyan, .purple, .pink, .cyan]), center: .center), lineWidth: 6)
                        .shadow(color: .cyan.opacity(0.6), radius: 10)
                        .shadow(color: .purple.opacity(0.6), radius: 20)
                        .frame(width: circleRect.width, height: circleRect.height)
                        .position(x: circleRect.midX, y: circleRect.midY)
                        .blendMode(.plusLighter)
                }
            }
            .mask {
                GeometryReader { geo in
                    let size = min(geo.size.width, geo.size.height)
                    Circle().frame(width: size, height: size).position(x: geo.size.width/2, y: geo.size.height/2)
                }
            }
            .background(Color.black.ignoresSafeArea())
            .preferredColorScheme(.dark)
            
            // Center arrow pointing up (player heading constant up)
            ArrowIndicator()
                .frame(width: 36, height: 36)
                .foregroundStyle(LinearGradient(colors: [.white, .cyan], startPoint: .top, endPoint: .bottom))
                .shadow(color: .cyan.opacity(0.8), radius: 10, x: 0, y: 0)
                .overlay {
                    Circle().stroke(Color.cyan.opacity(0.4), lineWidth: 2)
                        .blur(radius: 2)
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

            // Map speed (m/s) to distance (m)
            targetDistance = distance(for: speed)

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

            // Convert to alpha per frame
            let alphaPos = 1 - exp(-dt / tauPos)
            let alphaHeading = 1 - exp(-dt / tauHeading)
            let alphaDistance = 1 - exp(-dt / tauDistance)

            // Predict target center via dead-reckoning between GPS fixes
            var desiredCenter = targetCenter
            if let fix = lastFixCoordinate, let fixTime = lastFixDate {
                let elapsed = max(now.timeIntervalSince(fixTime), 0)
                let distance = max(currentSpeedMS, 0) * elapsed
                desiredCenter = project(from: fix, bearing: currentCourseDeg, distanceMeters: distance)
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

            // Interpolate heading (circular)
            let hDelta = shortestAngleDelta(from: currentHeading, to: targetHeading)
            currentHeading = normalizedAngle(currentHeading + hDelta * alphaHeading)

            // Interpolate distance
            currentDistance += (targetDistance - currentDistance) * alphaDistance

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
    var body: some View {
        ZStack {
            // neon glow aura
            Circle()
                .fill(RadialGradient(colors: [.cyan.opacity(0.25), .clear], center: .center, startRadius: 2, endRadius: 30))
            // arrow
            ArrowShape()
                .fill(LinearGradient(colors: [.cyan, .purple], startPoint: .top, endPoint: .bottom))
                .shadow(color: .cyan.opacity(0.9), radius: 8)
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

#Preview {
    ContentView()
}

