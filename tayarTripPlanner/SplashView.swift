//
//  SplashView.swift
//  tayarTripPlanner
//
//  Animated launch splash: a plane flies a curved route into FRA,
//  then the app title appears and the splash fades to the board.
//

import SwiftUI

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let startDate = Date()

    private let flightDuration: Double = 1.8

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            let t = reduceMotion ? 1.0 : easeInOutCubic(min(1, elapsed / flightDuration))

            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.08, blue: 0.15),
                        Color(red: 0.10, green: 0.14, blue: 0.24),
                        Color(red: 0.16, green: 0.10, blue: 0.14),
                    ],
                    startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

                GeometryReader { geo in
                    let size = geo.size
                    let p0 = CGPoint(x: -40, y: size.height * 0.72)
                    let p1 = CGPoint(x: size.width * 0.42, y: size.height * 0.16)
                    let p2 = CGPoint(x: size.width * 0.74, y: size.height * 0.40)

                    // Faint stars.
                    ForEach(0..<18, id: \.self) { index in
                        let fx = CGFloat((index * 37 % 100)) / 100
                        let fy = CGFloat((index * 61 % 100)) / 100
                        Circle()
                            .fill(.white.opacity(0.10 + 0.12 * Double(index % 3)))
                            .frame(width: index % 4 == 0 ? 3 : 2)
                            .position(x: fx * size.width, y: fy * size.height * 0.8)
                    }

                    // Dotted route, drawn up to the plane.
                    QuadCurve(start: p0, control: p1, end: p2)
                        .trim(from: 0, to: t)
                        .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [0.5, 10]))
                        .foregroundStyle(.white.opacity(0.65))

                    // Destination marker.
                    ZStack {
                        Circle()
                            .stroke(Color(red: 0.88, green: 0.35, blue: 0.42), lineWidth: 2)
                            .frame(width: 30, height: 30)
                            .scaleEffect(t >= 1 ? 1.35 : 1)
                            .opacity(t >= 1 ? 0 : 1)
                            .animation(.easeOut(duration: 0.9).repeatForever(autoreverses: false), value: t >= 1)
                        Circle()
                            .fill(Color(red: 0.88, green: 0.35, blue: 0.42))
                            .frame(width: 10, height: 10)
                        Text("FRA")
                            .font(.caption2.weight(.bold).monospaced())
                            .foregroundStyle(.white.opacity(0.9))
                            .offset(y: 24)
                    }
                    .position(p2)
                    .opacity(0.4 + 0.6 * t)

                    // The plane, following the curve and its tangent.
                    let position = quadPoint(p0, p1, p2, t)
                    let tangent = quadTangent(p0, p1, p2, t)
                    Image(systemName: "airplane")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                        .rotationEffect(.radians(atan2(tangent.dy, tangent.dx)))
                        .position(position)
                        .opacity(t >= 1 ? 0 : 1)
                }

                // Title, once the plane has arrived.
                VStack(spacing: 8) {
                    Spacer()
                    Text("FRA Arrivals")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("VIKING · FRANKFURT AIRPORT")
                        .font(.caption.weight(.semibold))
                        .kerning(2.5)
                        .foregroundStyle(Color(red: 0.88, green: 0.35, blue: 0.42))
                    Spacer().frame(height: 120)
                }
                .opacity(titleOpacity(t))
                .offset(y: (1 - titleOpacity(t)) * 14)
            }
        }
    }

    private func titleOpacity(_ t: Double) -> Double {
        max(0, min(1, (t - 0.65) / 0.35))
    }

    private func easeInOutCubic(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    private func quadPoint(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ t: Double) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * p0.x + 2 * u * t * p1.x + t * t * p2.x,
            y: u * u * p0.y + 2 * u * t * p1.y + t * t * p2.y)
    }

    private func quadTangent(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ t: Double) -> CGVector {
        let u = 1 - t
        return CGVector(
            dx: 2 * u * (p1.x - p0.x) + 2 * t * (p2.x - p1.x),
            dy: 2 * u * (p1.y - p0.y) + 2 * t * (p2.y - p1.y))
    }
}

private struct QuadCurve: Shape {
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }
}

#Preview {
    SplashView()
}
