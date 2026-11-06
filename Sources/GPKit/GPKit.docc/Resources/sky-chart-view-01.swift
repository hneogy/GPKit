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
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
