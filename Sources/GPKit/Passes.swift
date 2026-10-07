/// One pass of a satellite over a place: from where it rises to where it sets.
public struct Pass: Sendable, Hashable {

    /// A moment of a pass and where the satellite is at it.
    public struct Event: Sendable, Hashable {
        /// UTC, to the millisecond.
        public var time: Epoch
        public var look: Look
    }

    /// The satellite comes up through the elevation asked for. nil when it was already above it at the start of
    /// the search.
    public var rise: Event?
    /// The satellite at its highest in the pass. Where the elevation peaks more than once, as it can in a long pass
    /// of a high, eccentric orbit, this is the highest of the peaks. For a pass cut off by the start or the end of
    /// the search it is the highest point inside the search, which may be that very start or end.
    public var culmination: Event
    /// The satellite goes down through the elevation asked for. nil when it was still above it at the end of the
    /// search.
    public var set: Event?
}

/// What a search for passes found: the passes in order of time and, if the search could not go to its end, why.
///
/// It is a collection of its passes, so `for pass in` and `first` work on it as on an array.
public struct Passes: Sendable, Hashable, RandomAccessCollection {
    let found: [Pass]

    /// Why the search stopped before the end of its span, and at how many minutes from the element set's epoch;
    /// nil when the whole span was searched. The passes are the ones found up to there.
    public let failure: PropagationFailure?

    public var startIndex: Int { found.startIndex }
    public var endIndex: Int { found.endIndex }
    public subscript(position: Int) -> Pass { found[position] }
}

extension Propagator {

    /// The passes over a place in a span of time.
    ///
    /// - Parameters:
    ///   - observer: The place.
    ///   - start: The instant the search begins, UTC.
    ///   - duration: How long to search.
    ///   - minimumElevation: Degrees above the horizon a pass is counted from and to. The default is the horizon.
    ///     The elevation is geometric: no refraction.
    /// - Returns: The passes in order of time. A pass under way at the start has no rise, and one under way at the
    ///   end has no set.
    ///
    /// The elevation is sampled every 30 seconds, each crossing is then narrowed to a millisecond, and a peak
    /// between two samples is looked into, so a pass shorter than the sampling step is found too.
    ///
    /// If the element set cannot be propagated to some time in the span, a decayed satellite's for one, the search
    /// stops at the first such time it meets. What it found before that is returned, with the reason in `failure`:
    /// every pass that had set by then, and a pass under way then, which has no set and whose culmination is the
    /// highest point up to the last time that could be propagated to.
    public func passes(over observer: Observer, from start: Epoch, for duration: Duration, above minimumElevation: Double = 0) -> Passes {
        let (whole, fraction) = duration.components
        let span = Double(whole) + Double(fraction) / 1.0e18     // seconds
        guard span > 0, minimumElevation.isFinite else { return Passes(found: [], failure: nil) }
        let first = start.seconds(since: elementSet.epoch) / 60.0   // minutes from the element set's epoch
        guard first.isFinite, (try? start.advanced(by: span)) != nil else {
            return Passes(found: [], failure: PropagationFailure(kind: .time, minutesFromEpoch: nil))
        }

        // the elevation above the one asked for, at a number of seconds into the span
        func height(_ t: Double) throws(PropagationFailure) -> Double {
            try look(from: observer, minutes: first + t / 60.0).elevation - minimumElevation
        }
        func event(_ t: Double) throws(PropagationFailure) -> Pass.Event {
            let look = try look(from: observer, minutes: first + t / 60.0)
            // to the millisecond, which is what the search narrows to
            let time = Epoch(unixDay: start.unixDay, microsecondOfDay: Int(((start.secondOfDay + t) * 1000.0).rounded()) * 1000)
            return Pass.Event(time: time, look: look)
        }
        // the crossing between a time below and a time above, to a millisecond
        func crossing(below: Double, above: Double) throws(PropagationFailure) -> Double {
            var low = below, high = above
            while abs(high - low) > 0.0005 {
                let middle = 0.5 * (low + high)
                if try height(middle) > 0 { high = middle } else { low = middle }
            }
            return 0.5 * (low + high)
        }
        // the highest point between two times, by golden-section search, to a millisecond
        func peak(_ a: Double, _ b: Double) throws(PropagationFailure) -> Double {
            let ratio = 0.6180339887498949
            var low = a, high = b
            var x1 = high - ratio * (high - low), x2 = low + ratio * (high - low)
            var f1 = try height(x1), f2 = try height(x2)
            while high - low > 0.0005 {
                if f1 < f2 {
                    low = x1
                    x1 = x2
                    f1 = f2
                    x2 = low + ratio * (high - low)
                    f2 = try height(x2)
                } else {
                    high = x2
                    x2 = x1
                    f2 = f1
                    x1 = high - ratio * (high - low)
                    f1 = try height(x1)
                }
            }
            return 0.5 * (low + high)
        }

        let step = 30.0
        var passes: [Pass] = []
        var rise: (t: Double, event: Pass.Event)?   // the open pass's rise; nil for a pass under way at the start
        var up = false
        var best = (t: 0.0, h: -Double.infinity)    // the highest sample of the open pass
        var before = (t: 0.0, h: 0.0)               // the last sample taken
        var twoBefore: (t: Double, h: Double)?

        func close(set: Double?, end: Double) throws(PropagationFailure) {
            // the culmination is looked for around the highest sample, within the pass
            let from = max(rise?.t ?? 0, best.t - step), to = min(set ?? end, best.t + step)
            let top = to > from ? try peak(from, to) : best.t
            passes.append(Pass(rise: rise?.event, culmination: try event(top),
                               set: try set.map { t throws(PropagationFailure) in try event(t) }))
        }

        do throws(PropagationFailure) {
            before = (0, try height(0))
            if before.h > 0 {
                up = true
                best = before
            }
            var t = 0.0
            while t < span {
                t = min(t + step, span)
                let now = (t: t, h: try height(t))
                if up {
                    if now.h > best.h { best = now }
                    if now.h <= 0 {
                        try close(set: try crossing(below: now.t, above: before.t), end: span)
                        up = false
                    }
                } else if now.h > 0 {
                    let at = try crossing(below: before.t, above: now.t)
                    rise = (at, try event(at))
                    up = true
                    best = now
                } else if let earlier = twoBefore, before.h > earlier.h, before.h > now.h, before.h > -5.0 {
                    // a peak between samples that stayed below: look at its top, and it is a pass if the top is above
                    let top = try peak(earlier.t, now.t)
                    let h = try height(top)
                    if h > 0 {
                        let at = try crossing(below: earlier.t, above: top)
                        rise = (at, try event(at))
                        best = (top, h)
                        try close(set: try crossing(below: now.t, above: top), end: span)
                    }
                }
                twoBefore = before
                before = now
            }
            if up {
                try close(set: nil, end: span)
            }
        } catch {
            // The search ends here. A pass under way is kept without a set: its highest sample is at or before the
            // last sample taken, and its culmination is looked for no later than that.
            if up {
                let from = max(rise?.t ?? 0, best.t - step), to = min(before.t, best.t + step)
                let top = to > from ? (try? peak(from, to)) ?? best.t : best.t
                if let culmination = (try? event(top)) ?? (try? event(best.t)) {
                    passes.append(Pass(rise: rise?.event, culmination: culmination, set: nil))
                }
            }
            return Passes(found: passes, failure: error)
        }
        return Passes(found: passes, failure: nil)
    }
}
