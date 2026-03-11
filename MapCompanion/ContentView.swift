//
//  ContentView.swift
//  MapCompanion
//
//  Created by Miguel Ángel Cofrancesco on 10/3/26.
//

import SwiftUI
import MapKit

struct ContentView: View {
    @StateObject private var locationManager = HeadingLocationManager()
    @State private var cameraPosition: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var lastCoordinate: CLLocationCoordinate2D? = nil
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
            // Set initial zoom to 300m, then return to userLocation follow with heading
            let camera = MapCamera(centerCoordinate: fallbackCoordinate, distance: 300, heading: 0, pitch: 45)
            cameraPosition = .camera(camera)
            DispatchQueue.main.async {
                cameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
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
}

// MARK: - Arrow Indicator
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

