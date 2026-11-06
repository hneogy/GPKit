import GPKit

let tle = """
ISS (ZARYA)
1 25544U 98067A   98324.28472222 -.00003657  11563-4  00000+0 0    10
2 25544  51.5908 168.3788 0125362  86.4185 359.7454 16.05064833    05
"""
let iss = try ElementSets.read(tle, as: .tle).elementSets[0]
let propagator = try Propagator(iss)
let home = Observer(latitude: 40.0, longitude: -75.0)
let passes = propagator.passes(over: home, from: iss.epoch, for: .seconds(86_400))
for pass in passes {
    if let rise = pass.rise {
        print(rise.time, "highest", Int(pass.culmination.look.elevation.rounded()), "degrees")
    }
}
