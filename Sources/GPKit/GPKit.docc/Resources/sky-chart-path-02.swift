import Foundation
import GPKit

func skyPath(of pass: Pass, with propagator: Propagator, from home: Observer) throws -> [Look] {
    guard let rise = pass.rise, let set = pass.set else { return [] }
    var path: [Look] = []
    var time = rise.time
    while time < set.time {
        path.append(try propagator.look(from: home, at: time))
        time = try time.advanced(by: 10)
    }
    path.append(set.look)
    return path
}

func chartPoint(_ look: Look) -> (x: Double, y: Double) {
    let radius = (90 - look.elevation) / 90
    let angle = look.azimuth * .pi / 180
    return (x: radius * sin(angle), y: -radius * cos(angle))
}
