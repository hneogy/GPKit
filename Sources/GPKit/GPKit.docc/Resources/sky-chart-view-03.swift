import SwiftUI
import GPKit

struct SkyChart: View {
    let path: [Look]

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let horizon = CGRect(x: centre.x - radius, y: centre.y - radius, width: 2 * radius, height: 2 * radius)
            context.stroke(Path(ellipseIn: horizon), with: .color(.secondary))
            var track = Path()
            track.addLines(path.map { look in
                let point = chartPoint(look)
                return CGPoint(x: centre.x + point.x * radius, y: centre.y + point.y * radius)
            })
            context.stroke(track, with: .color(.accentColor), lineWidth: 3)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(said)
    }

    var said: String {
        guard let first = path.first, let last = path.last, let top = path.max(by: { $0.elevation < $1.elevation }) else {
            return "No pass"
        }
        return "Rises at azimuth \(Int(first.azimuth.rounded())) degrees, highest \(Int(top.elevation.rounded())) degrees, "
            + "sets at azimuth \(Int(last.azimuth.rounded())) degrees"
    }
}
