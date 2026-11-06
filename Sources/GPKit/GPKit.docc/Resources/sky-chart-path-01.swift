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
