// The SGP4 propagator: a port to Swift of the propagation routines of David Vallado's SGP4.cpp,
//
//     sgp4init, sgp4, initl, dscom, dpper, dsinit, dspace, getgravconst and gstime_SGP4,
//
// from CelesTrak/fundamentals-of-astrodynamics, software/cpp/SGP4/SGP4/SGP4.cpp ("SGP4 Version 2025-12-30"), at
// commit 49df0479c950. That file derives from the code published with Vallado, Crawford, Hujsak and Kelso,
// "Revisiting Spacetrack Report #3", AIAA 2006-6753, and the repository's NOTICE says of it: "That original code was
// released without restriction for any use. The SGP4 C++ source retains those original unrestricted terms." The port
// was made from that one file and from nothing else in that repository. See NOTICE.
//
// The port is a transcription. Names are the C++'s, statements are in its order, and every expression keeps the
// C++'s order of operations, so that the two give the same doubles where the platform's maths library does; the
// tests compile the C++ itself and compare. What is left out is what never reaches a result: the debug includes,
// the satellite number, and the second sidereal time initl computes and does not use. The reader, twoline2rv, is
// not ported: GPKit has its own.

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The record the C++ calls `elsetrec`: the constants, the initialised coefficients and the working values of one
/// element set's propagation.
struct SGP4Core: Sendable {

    enum Gravity: Sendable {
        case wgs72old, wgs72, wgs84
    }

    /// The C++'s `satrec.error`: 0, or the reason the last call stopped.
    ///   1 the mean eccentricity is 1 or more, or below -0.001
    ///   2 the mean motion is zero or less
    ///   3 the perturbed eccentricity is outside 0 to 1
    ///   4 the semi-latus rectum is negative
    ///   6 the satellite has decayed: the radius is below one Earth radius
    var error = 0
    /// `operationmode == 'a'`: the Air Force Space Command's way with two angles, in place of the improved one.
    var afspc = false
    /// `init == 'y'`.
    var initializing = false
    /// `method == 'd'`: a period of 225 minutes or more, with the deep-space terms.
    var deepSpace = false
    var isimp = 0

    // near Earth
    var aycof = 0.0, con41 = 0.0, cc1 = 0.0, cc4 = 0.0, cc5 = 0.0, d2 = 0.0, d3 = 0.0, d4 = 0.0
    var delmo = 0.0, eta = 0.0, argpdot = 0.0, omgcof = 0.0, sinmao = 0.0, t = 0.0, t2cof = 0.0, t3cof = 0.0
    var t4cof = 0.0, t5cof = 0.0, x1mth2 = 0.0, x7thm1 = 0.0, mdot = 0.0, nodedot = 0.0, xlcof = 0.0, xmcof = 0.0
    var nodecf = 0.0

    // deep space
    var irez = 0
    var d2201 = 0.0, d2211 = 0.0, d3210 = 0.0, d3222 = 0.0, d4410 = 0.0, d4422 = 0.0, d5220 = 0.0, d5232 = 0.0
    var d5421 = 0.0, d5433 = 0.0, dedt = 0.0, del1 = 0.0, del2 = 0.0, del3 = 0.0, didt = 0.0, dmdt = 0.0
    var dnodt = 0.0, domdt = 0.0, e3 = 0.0, ee2 = 0.0, peo = 0.0, pgho = 0.0, pho = 0.0, pinco = 0.0
    var plo = 0.0, se2 = 0.0, se3 = 0.0, sgh2 = 0.0, sgh3 = 0.0, sgh4 = 0.0, sh2 = 0.0, sh3 = 0.0
    var si2 = 0.0, si3 = 0.0, sl2 = 0.0, sl3 = 0.0, sl4 = 0.0, gsto = 0.0, xfact = 0.0, xgh2 = 0.0
    var xgh3 = 0.0, xgh4 = 0.0, xh2 = 0.0, xh3 = 0.0, xi2 = 0.0, xi3 = 0.0, xl2 = 0.0, xl3 = 0.0
    var xl4 = 0.0, xlamo = 0.0, zmol = 0.0, zmos = 0.0, atime = 0.0, xli = 0.0, xni = 0.0

    var a = 0.0, altp = 0.0, alta = 0.0, nddot = 0.0, ndot = 0.0
    var bstar = 0.0, inclo = 0.0, nodeo = 0.0, ecco = 0.0, argpo = 0.0, mo = 0.0, no_kozai = 0.0
    var no_unkozai = 0.0

    // singly averaged mean elements, as of the last call
    var am = 0.0, em = 0.0, im = 0.0, Om = 0.0, om = 0.0, mm = 0.0, nm = 0.0

    // constants
    var tumin = 0.0, mus = 0.0, radiusearthkm = 0.0, xke = 0.0, j2 = 0.0, j3 = 0.0, j4 = 0.0, j3oj2 = 0.0

    static let pi = 3.14159265358979323846

    // MARK: - getgravconst

    mutating func getgravconst(_ whichconst: Gravity) {
        switch whichconst {
        case .wgs72old:
            mus = 398600.79964
            radiusearthkm = 6378.135
            xke = 0.0743669161
            tumin = 1.0 / xke
            j2 = 0.001082616
            j3 = -0.00000253881
            j4 = -0.00000165597
            j3oj2 = j3 / j2
        case .wgs72:
            mus = 398600.8
            radiusearthkm = 6378.135
            xke = 60.0 / sqrt(radiusearthkm * radiusearthkm * radiusearthkm / mus)
            tumin = 1.0 / xke
            j2 = 0.001082616
            j3 = -0.00000253881
            j4 = -0.00000165597
            j3oj2 = j3 / j2
        case .wgs84:
            mus = 398600.5
            radiusearthkm = 6378.137
            xke = 60.0 / sqrt(radiusearthkm * radiusearthkm * radiusearthkm / mus)
            tumin = 1.0 / xke
            j2 = 0.00108262998905
            j3 = -0.00000253215306
            j4 = -0.00000161098761
            j3oj2 = j3 / j2
        }
    }

    // MARK: - gstime

    /// Greenwich sidereal time, radians, 0 to 2π, for a Julian date of UT1.
    static func gstime(_ jdut1: Double) -> Double {
        let twopi = 2.0 * pi
        let deg2rad = pi / 180.0
        let tut1 = (jdut1 - 2451545.0) / 36525.0
        var temp = -6.2e-6 * tut1 * tut1 * tut1 + 0.093104 * tut1 * tut1 +
            (876600.0 * 3600 + 8640184.812866) * tut1 + 67310.54841
        temp = fmod(temp * deg2rad / 240.0, twopi)
        if temp < 0.0 {
            temp += twopi
        }
        return temp
    }

    // MARK: - dpper

    /// The lunar and solar periodics. With `initializing` it changes nothing; otherwise it applies them to the five
    /// elements passed in.
    func dpper(t: Double, initializing: Bool, ep: inout Double, inclp: inout Double, nodep: inout Double, argpp: inout Double, mp: inout Double) {
        let pi = SGP4Core.pi
        let twopi = 2.0 * pi
        var alfdp, betdp, cosip, cosop, dalf, dbet, dls: Double
        var f2, f3, pe, pgh, ph, pinc, pl: Double
        let sel, ses, sghl, sghs, shll, shs, sil: Double
        var sinip, sinop, sinzf: Double
        let sis, sll, sls: Double
        var xls, xnoh, zf, zm: Double
        let zel, zes, znl, zns: Double

        zns = 1.19459e-5
        zes = 0.01675
        znl = 1.5835218e-4
        zel = 0.05490

        zm = zmos + zns * t
        if initializing {
            zm = zmos
        }
        zf = zm + 2.0 * zes * sin(zm)
        sinzf = sin(zf)
        f2 = 0.5 * sinzf * sinzf - 0.25
        f3 = -0.5 * sinzf * cos(zf)
        ses = se2 * f2 + se3 * f3
        sis = si2 * f2 + si3 * f3
        sls = sl2 * f2 + sl3 * f3 + sl4 * sinzf
        sghs = sgh2 * f2 + sgh3 * f3 + sgh4 * sinzf
        shs = sh2 * f2 + sh3 * f3
        zm = zmol + znl * t
        if initializing {
            zm = zmol
        }
        zf = zm + 2.0 * zel * sin(zm)
        sinzf = sin(zf)
        f2 = 0.5 * sinzf * sinzf - 0.25
        f3 = -0.5 * sinzf * cos(zf)
        sel = ee2 * f2 + e3 * f3
        sil = xi2 * f2 + xi3 * f3
        sll = xl2 * f2 + xl3 * f3 + xl4 * sinzf
        sghl = xgh2 * f2 + xgh3 * f3 + xgh4 * sinzf
        shll = xh2 * f2 + xh3 * f3
        pe = ses + sel
        pinc = sis + sil
        pl = sls + sll
        pgh = sghs + sghl
        ph = shs + shll

        if !initializing {
            pe = pe - peo
            pinc = pinc - pinco
            pl = pl - plo
            pgh = pgh - pgho
            ph = ph - pho
            inclp = inclp + pinc
            ep = ep + pe
            sinip = sin(inclp)
            cosip = cos(inclp)

            if inclp >= 0.2 {
                ph = ph / sinip
                pgh = pgh - cosip * ph
                argpp = argpp + pgh
                nodep = nodep + ph
                mp = mp + pl
            } else {
                sinop = sin(nodep)
                cosop = cos(nodep)
                alfdp = sinip * sinop
                betdp = sinip * cosop
                dalf = ph * cosop + pinc * cosip * sinop
                dbet = -ph * sinop + pinc * cosip * cosop
                alfdp = alfdp + dalf
                betdp = betdp + dbet
                nodep = fmod(nodep, twopi)
                if (nodep < 0.0) && afspc {
                    nodep = nodep + twopi
                }
                xls = mp + argpp + cosip * nodep
                dls = pl + pgh - pinc * nodep * sinip
                xls = xls + dls
                xnoh = nodep
                nodep = atan2(alfdp, betdp)
                if (nodep < 0.0) && afspc {
                    nodep = nodep + twopi
                }
                if fabs(xnoh - nodep) > pi {
                    if nodep < xnoh {
                        nodep = nodep + twopi
                    } else {
                        nodep = nodep - twopi
                    }
                }
                mp = mp + pl
                argpp = xls - mp - cosip * nodep
            }
        }
    }

    // MARK: - dscom

    /// What dscom hands back: the terms the deep-space initialisation shares.
    struct DeepCommon {
        var snodm = 0.0, cnodm = 0.0, sinim = 0.0, cosim = 0.0, sinomm = 0.0, cosomm = 0.0, day = 0.0
        var e3 = 0.0, ee2 = 0.0, em = 0.0, emsq = 0.0, gam = 0.0
        var peo = 0.0, pgho = 0.0, pho = 0.0, pinco = 0.0, plo = 0.0, rtemsq = 0.0
        var se2 = 0.0, se3 = 0.0, sgh2 = 0.0, sgh3 = 0.0, sgh4 = 0.0, sh2 = 0.0, sh3 = 0.0
        var si2 = 0.0, si3 = 0.0, sl2 = 0.0, sl3 = 0.0, sl4 = 0.0
        var s1 = 0.0, s2 = 0.0, s3 = 0.0, s4 = 0.0, s5 = 0.0, s6 = 0.0, s7 = 0.0
        var ss1 = 0.0, ss2 = 0.0, ss3 = 0.0, ss4 = 0.0, ss5 = 0.0, ss6 = 0.0, ss7 = 0.0
        var sz1 = 0.0, sz2 = 0.0, sz3 = 0.0, sz11 = 0.0, sz12 = 0.0, sz13 = 0.0
        var sz21 = 0.0, sz22 = 0.0, sz23 = 0.0, sz31 = 0.0, sz32 = 0.0, sz33 = 0.0
        var xgh2 = 0.0, xgh3 = 0.0, xgh4 = 0.0, xh2 = 0.0, xh3 = 0.0, xi2 = 0.0, xi3 = 0.0
        var xl2 = 0.0, xl3 = 0.0, xl4 = 0.0, nm = 0.0
        var z1 = 0.0, z2 = 0.0, z3 = 0.0, z11 = 0.0, z12 = 0.0, z13 = 0.0
        var z21 = 0.0, z22 = 0.0, z23 = 0.0, z31 = 0.0, z32 = 0.0, z33 = 0.0
        var zmol = 0.0, zmos = 0.0
    }

    static func dscom(epoch: Double, ep: Double, argpp: Double, tc: Double, inclp: Double, nodep: Double, np: Double) -> DeepCommon {
        var o = DeepCommon()
        let zes = 0.01675
        let zel = 0.05490
        let c1ss = 2.9864797e-6
        let c1l = 4.7968065e-7
        let zsinis = 0.39785416
        let zcosis = 0.91744867
        let zcosgs = 0.1945905
        let zsings = -0.98088458
        let twopi = 2.0 * pi

        var a1, a2, a3, a4, a5, a6, a7: Double
        var a8, a9, a10: Double
        let betasq: Double
        var cc: Double
        let ctem, stem: Double
        var x1, x2, x3, x4, x5, x6, x7: Double
        var x8: Double
        let xnodce, xnoi: Double
        var zcosg: Double
        let zcosgl: Double
        var zcosh: Double
        let zcoshl: Double
        var zcosi: Double
        let zcosil: Double
        var zsing: Double
        let zsingl: Double
        var zsinh: Double
        let zsinhl: Double
        var zsini: Double
        let zsinil: Double
        var zx: Double
        let zy: Double

        o.nm = np
        o.em = ep
        o.snodm = sin(nodep)
        o.cnodm = cos(nodep)
        o.sinomm = sin(argpp)
        o.cosomm = cos(argpp)
        o.sinim = sin(inclp)
        o.cosim = cos(inclp)
        o.emsq = o.em * o.em
        betasq = 1.0 - o.emsq
        o.rtemsq = sqrt(betasq)

        o.peo = 0.0
        o.pinco = 0.0
        o.plo = 0.0
        o.pgho = 0.0
        o.pho = 0.0
        o.day = epoch + 18261.5 + tc / 1440.0
        xnodce = fmod(4.5236020 - 9.2422029e-4 * o.day, twopi)
        stem = sin(xnodce)
        ctem = cos(xnodce)
        zcosil = 0.91375164 - 0.03568096 * ctem
        zsinil = sqrt(1.0 - zcosil * zcosil)
        zsinhl = 0.089683511 * stem / zsinil
        zcoshl = sqrt(1.0 - zsinhl * zsinhl)
        o.gam = 5.8351514 + 0.0019443680 * o.day
        zx = 0.39785416 * stem / zsinil
        zy = zcoshl * ctem + 0.91744867 * zsinhl * stem
        zx = atan2(zx, zy)
        zx = o.gam + zx - xnodce
        zcosgl = cos(zx)
        zsingl = sin(zx)

        zcosg = zcosgs
        zsing = zsings
        zcosi = zcosis
        zsini = zsinis
        zcosh = o.cnodm
        zsinh = o.snodm
        cc = c1ss
        xnoi = 1.0 / o.nm

        for lsflg in 1...2 {
            a1 = zcosg * zcosh + zsing * zcosi * zsinh
            a3 = -zsing * zcosh + zcosg * zcosi * zsinh
            a7 = -zcosg * zsinh + zsing * zcosi * zcosh
            a8 = zsing * zsini
            a9 = zsing * zsinh + zcosg * zcosi * zcosh
            a10 = zcosg * zsini
            a2 = o.cosim * a7 + o.sinim * a8
            a4 = o.cosim * a9 + o.sinim * a10
            a5 = -o.sinim * a7 + o.cosim * a8
            a6 = -o.sinim * a9 + o.cosim * a10

            x1 = a1 * o.cosomm + a2 * o.sinomm
            x2 = a3 * o.cosomm + a4 * o.sinomm
            x3 = -a1 * o.sinomm + a2 * o.cosomm
            x4 = -a3 * o.sinomm + a4 * o.cosomm
            x5 = a5 * o.sinomm
            x6 = a6 * o.sinomm
            x7 = a5 * o.cosomm
            x8 = a6 * o.cosomm

            o.z31 = 12.0 * x1 * x1 - 3.0 * x3 * x3
            o.z32 = 24.0 * x1 * x2 - 6.0 * x3 * x4
            o.z33 = 12.0 * x2 * x2 - 3.0 * x4 * x4
            o.z1 = 3.0 * (a1 * a1 + a2 * a2) + o.z31 * o.emsq
            o.z2 = 6.0 * (a1 * a3 + a2 * a4) + o.z32 * o.emsq
            o.z3 = 3.0 * (a3 * a3 + a4 * a4) + o.z33 * o.emsq
            o.z11 = -6.0 * a1 * a5 + o.emsq * (-24.0 * x1 * x7 - 6.0 * x3 * x5)
            o.z12 = -6.0 * (a1 * a6 + a3 * a5) + o.emsq *
                (-24.0 * (x2 * x7 + x1 * x8) - 6.0 * (x3 * x6 + x4 * x5))
            o.z13 = -6.0 * a3 * a6 + o.emsq * (-24.0 * x2 * x8 - 6.0 * x4 * x6)
            o.z21 = 6.0 * a2 * a5 + o.emsq * (24.0 * x1 * x5 - 6.0 * x3 * x7)
            o.z22 = 6.0 * (a4 * a5 + a2 * a6) + o.emsq *
                (24.0 * (x2 * x5 + x1 * x6) - 6.0 * (x4 * x7 + x3 * x8))
            o.z23 = 6.0 * a4 * a6 + o.emsq * (24.0 * x2 * x6 - 6.0 * x4 * x8)
            o.z1 = o.z1 + o.z1 + betasq * o.z31
            o.z2 = o.z2 + o.z2 + betasq * o.z32
            o.z3 = o.z3 + o.z3 + betasq * o.z33
            o.s3 = cc * xnoi
            o.s2 = -0.5 * o.s3 / o.rtemsq
            o.s4 = o.s3 * o.rtemsq
            o.s1 = -15.0 * o.em * o.s4
            o.s5 = x1 * x3 + x2 * x4
            o.s6 = x2 * x3 + x1 * x4
            o.s7 = x2 * x4 - x1 * x3

            if lsflg == 1 {
                o.ss1 = o.s1
                o.ss2 = o.s2
                o.ss3 = o.s3
                o.ss4 = o.s4
                o.ss5 = o.s5
                o.ss6 = o.s6
                o.ss7 = o.s7
                o.sz1 = o.z1
                o.sz2 = o.z2
                o.sz3 = o.z3
                o.sz11 = o.z11
                o.sz12 = o.z12
                o.sz13 = o.z13
                o.sz21 = o.z21
                o.sz22 = o.z22
                o.sz23 = o.z23
                o.sz31 = o.z31
                o.sz32 = o.z32
                o.sz33 = o.z33
                zcosg = zcosgl
                zsing = zsingl
                zcosi = zcosil
                zsini = zsinil
                zcosh = zcoshl * o.cnodm + zsinhl * o.snodm
                zsinh = o.snodm * zcoshl - o.cnodm * zsinhl
                cc = c1l
            }
        }

        o.zmol = fmod(4.7199672 + 0.22997150 * o.day - o.gam, twopi)
        o.zmos = fmod(6.2565837 + 0.017201977 * o.day, twopi)

        o.se2 = 2.0 * o.ss1 * o.ss6
        o.se3 = 2.0 * o.ss1 * o.ss7
        o.si2 = 2.0 * o.ss2 * o.sz12
        o.si3 = 2.0 * o.ss2 * (o.sz13 - o.sz11)
        o.sl2 = -2.0 * o.ss3 * o.sz2
        o.sl3 = -2.0 * o.ss3 * (o.sz3 - o.sz1)
        o.sl4 = -2.0 * o.ss3 * (-21.0 - 9.0 * o.emsq) * zes
        o.sgh2 = 2.0 * o.ss4 * o.sz32
        o.sgh3 = 2.0 * o.ss4 * (o.sz33 - o.sz31)
        o.sgh4 = -18.0 * o.ss4 * zes
        o.sh2 = -2.0 * o.ss2 * o.sz22
        o.sh3 = -2.0 * o.ss2 * (o.sz23 - o.sz21)

        o.ee2 = 2.0 * o.s1 * o.s6
        o.e3 = 2.0 * o.s1 * o.s7
        o.xi2 = 2.0 * o.s2 * o.z12
        o.xi3 = 2.0 * o.s2 * (o.z13 - o.z11)
        o.xl2 = -2.0 * o.s3 * o.z2
        o.xl3 = -2.0 * o.s3 * (o.z3 - o.z1)
        o.xl4 = -2.0 * o.s3 * (-21.0 - 9.0 * o.emsq) * zel
        o.xgh2 = 2.0 * o.s4 * o.z32
        o.xgh3 = 2.0 * o.s4 * (o.z33 - o.z31)
        o.xgh4 = -18.0 * o.s4 * zel
        o.xh2 = -2.0 * o.s2 * o.z22
        o.xh3 = -2.0 * o.s2 * (o.z23 - o.z21)
        return o
    }

    // MARK: - dsinit

    /// The deep-space contributions to the mean elements, and the resonance terms for half-day and one-day orbits.
    /// `c` is dscom's result; the six elements and `dndt` are the caller's.
    mutating func dsinit(_ c: DeepCommon, t: Double, tc: Double, xpidot: Double, eccsq: Double,
                         em: inout Double, argpm: inout Double, inclm: inout Double, mm: inout Double,
                         nm: inout Double, nodem: inout Double, dndt: inout Double) {
        let pi = SGP4Core.pi
        let twopi = 2.0 * pi
        let cosim = c.cosim, sinim = c.sinim
        var emsq = c.emsq
        let s1 = c.s1, s2 = c.s2, s3 = c.s3, s4 = c.s4, s5 = c.s5
        let ss1 = c.ss1, ss2 = c.ss2, ss3 = c.ss3, ss4 = c.ss4, ss5 = c.ss5
        let sz1 = c.sz1, sz3 = c.sz3, sz11 = c.sz11, sz13 = c.sz13, sz21 = c.sz21, sz23 = c.sz23, sz31 = c.sz31, sz33 = c.sz33
        let z1 = c.z1, z3 = c.z3, z11 = c.z11, z13 = c.z13, z21 = c.z21, z23 = c.z23, z31 = c.z31, z33 = c.z33
        let no = no_unkozai

        var ainv2: Double
        var aonv = 0.0
        var cosisq, eoc, f220, f221, f311: Double
        var f321, f322, f330, f441, f442, f522, f523: Double
        var f542, f543, g200, g201, g211, g300, g310: Double
        var g322, g410, g422, g520, g521, g532, g533: Double
        let ses, sgs: Double
        var sghl: Double
        let sghs: Double
        var shs, shll: Double
        let sis: Double
        var sini2: Double
        let sls: Double
        var temp, temp1: Double
        let theta: Double
        var xno2: Double
        let q22, q31, q33, root22, root44, root54, rptim, root32: Double
        let root52, x2o3, znl: Double
        var emo: Double
        let zns: Double
        var emsqo: Double

        q22 = 1.7891679e-6
        q31 = 2.1460748e-6
        q33 = 2.2123015e-7
        root22 = 1.7891679e-6
        root44 = 7.3636953e-9
        root54 = 2.1765803e-9
        rptim = 4.37526908801129966e-3
        root32 = 3.7393792e-7
        root52 = 1.1428639e-7
        x2o3 = 2.0 / 3.0
        znl = 1.5835218e-4
        zns = 1.19459e-5

        irez = 0
        if (nm < 0.0052359877) && (nm > 0.0034906585) {
            irez = 1
        }
        if (nm >= 8.26e-3) && (nm <= 9.24e-3) && (em >= 0.5) {
            irez = 2
        }

        ses = ss1 * zns * ss5
        sis = ss2 * zns * (sz11 + sz13)
        sls = -zns * ss3 * (sz1 + sz3 - 14.0 - 6.0 * emsq)
        sghs = ss4 * zns * (sz31 + sz33 - 6.0)
        shs = -zns * ss2 * (sz21 + sz23)
        if (inclm < 5.2359877e-2) || (inclm > pi - 5.2359877e-2) {
            shs = 0.0
        }
        if sinim != 0.0 {
            shs = shs / sinim
        }
        sgs = sghs - cosim * shs

        dedt = ses + s1 * znl * s5
        didt = sis + s2 * znl * (z11 + z13)
        dmdt = sls - znl * s3 * (z1 + z3 - 14.0 - 6.0 * emsq)
        sghl = s4 * znl * (z31 + z33 - 6.0)
        shll = -znl * s2 * (z21 + z23)
        if (inclm < 5.2359877e-2) || (inclm > pi - 5.2359877e-2) {
            shll = 0.0
        }
        domdt = sgs + sghl
        dnodt = shs
        if sinim != 0.0 {
            domdt = domdt - cosim / sinim * shll
            dnodt = dnodt + shll / sinim
        }

        dndt = 0.0
        theta = fmod(gsto + tc * rptim, twopi)
        em = em + dedt * t
        inclm = inclm + didt * t
        argpm = argpm + domdt * t
        nodem = nodem + dnodt * t
        mm = mm + dmdt * t

        if irez != 0 {
            aonv = pow(nm / xke, x2o3)

            if irez == 2 {
                cosisq = cosim * cosim
                emo = em
                em = ecco
                emsqo = emsq
                emsq = eccsq
                eoc = em * emsq
                g201 = -0.306 - (em - 0.64) * 0.440

                if em <= 0.65 {
                    g211 = 3.616 - 13.2470 * em + 16.2900 * emsq
                    g310 = -19.302 + 117.3900 * em - 228.4190 * emsq + 156.5910 * eoc
                    g322 = -18.9068 + 109.7927 * em - 214.6334 * emsq + 146.5816 * eoc
                    g410 = -41.122 + 242.6940 * em - 471.0940 * emsq + 313.9530 * eoc
                    g422 = -146.407 + 841.8800 * em - 1629.014 * emsq + 1083.4350 * eoc
                    g520 = -532.114 + 3017.977 * em - 5740.032 * emsq + 3708.2760 * eoc
                } else {
                    g211 = -72.099 + 331.819 * em - 508.738 * emsq + 266.724 * eoc
                    g310 = -346.844 + 1582.851 * em - 2415.925 * emsq + 1246.113 * eoc
                    g322 = -342.585 + 1554.908 * em - 2366.899 * emsq + 1215.972 * eoc
                    g410 = -1052.797 + 4758.686 * em - 7193.992 * emsq + 3651.957 * eoc
                    g422 = -3581.690 + 16178.110 * em - 24462.770 * emsq + 12422.520 * eoc
                    if em > 0.715 {
                        g520 = -5149.66 + 29936.92 * em - 54087.36 * emsq + 31324.56 * eoc
                    } else {
                        g520 = 1464.74 - 4664.75 * em + 3763.64 * emsq
                    }
                }
                if em < 0.7 {
                    g533 = -919.22770 + 4988.6100 * em - 9064.7700 * emsq + 5542.21 * eoc
                    g521 = -822.71072 + 4568.6173 * em - 8491.4146 * emsq + 5337.524 * eoc
                    g532 = -853.66600 + 4690.2500 * em - 8624.7700 * emsq + 5341.4 * eoc
                } else {
                    g533 = -37995.780 + 161616.52 * em - 229838.20 * emsq + 109377.94 * eoc
                    g521 = -51752.104 + 218913.95 * em - 309468.16 * emsq + 146349.42 * eoc
                    g532 = -40023.880 + 170470.89 * em - 242699.48 * emsq + 115605.82 * eoc
                }

                sini2 = sinim * sinim
                f220 = 0.75 * (1.0 + 2.0 * cosim + cosisq)
                f221 = 1.5 * sini2
                f321 = 1.875 * sinim * (1.0 - 2.0 * cosim - 3.0 * cosisq)
                f322 = -1.875 * sinim * (1.0 + 2.0 * cosim - 3.0 * cosisq)
                f441 = 35.0 * sini2 * f220
                f442 = 39.3750 * sini2 * sini2
                f522 = 9.84375 * sinim * (sini2 * (1.0 - 2.0 * cosim - 5.0 * cosisq) +
                    0.33333333 * (-2.0 + 4.0 * cosim + 6.0 * cosisq))
                f523 = sinim * (4.92187512 * sini2 * (-2.0 - 4.0 * cosim +
                    10.0 * cosisq) + 6.56250012 * (1.0 + 2.0 * cosim - 3.0 * cosisq))
                f542 = 29.53125 * sinim * (2.0 - 8.0 * cosim + cosisq *
                    (-12.0 + 8.0 * cosim + 10.0 * cosisq))
                f543 = 29.53125 * sinim * (-2.0 - 8.0 * cosim + cosisq *
                    (12.0 + 8.0 * cosim - 10.0 * cosisq))
                xno2 = nm * nm
                ainv2 = aonv * aonv
                temp1 = 3.0 * xno2 * ainv2
                temp = temp1 * root22
                d2201 = temp * f220 * g201
                d2211 = temp * f221 * g211
                temp1 = temp1 * aonv
                temp = temp1 * root32
                d3210 = temp * f321 * g310
                d3222 = temp * f322 * g322
                temp1 = temp1 * aonv
                temp = 2.0 * temp1 * root44
                d4410 = temp * f441 * g410
                d4422 = temp * f442 * g422
                temp1 = temp1 * aonv
                temp = temp1 * root52
                d5220 = temp * f522 * g520
                d5232 = temp * f523 * g532
                temp = 2.0 * temp1 * root54
                d5421 = temp * f542 * g521
                d5433 = temp * f543 * g533
                xlamo = fmod(mo + nodeo + nodeo - theta - theta, twopi)
                xfact = mdot + dmdt + 2.0 * (nodedot + dnodt - rptim) - no
                em = emo
                emsq = emsqo
            }

            if irez == 1 {
                g200 = 1.0 + emsq * (-2.5 + 0.8125 * emsq)
                g310 = 1.0 + 2.0 * emsq
                g300 = 1.0 + emsq * (-6.0 + 6.60937 * emsq)
                f220 = 0.75 * (1.0 + cosim) * (1.0 + cosim)
                f311 = 0.9375 * sinim * sinim * (1.0 + 3.0 * cosim) - 0.75 * (1.0 + cosim)
                f330 = 1.0 + cosim
                f330 = 1.875 * f330 * f330 * f330
                del1 = 3.0 * nm * nm * aonv * aonv
                del2 = 2.0 * del1 * f220 * g200 * q22
                del3 = 3.0 * del1 * f330 * g300 * q33 * aonv
                del1 = del1 * f311 * g310 * q31 * aonv
                xlamo = fmod(mo + nodeo + argpo - theta, twopi)
                xfact = mdot + xpidot - rptim + dmdt + domdt + dnodt - no
            }

            xli = xlamo
            xni = no
            atime = 0.0
            nm = no + dndt
        }
    }

    // MARK: - dspace

    /// The deep-space secular effects and, for a resonant orbit, the integration of the resonance terms from the
    /// epoch to `t` in steps of 720 minutes.
    mutating func dspace(t: Double, tc: Double, em: inout Double, argpm: inout Double, inclm: inout Double,
                         mm: inout Double, nodem: inout Double, dndt: inout Double, nm: inout Double) {
        let twopi = 2.0 * SGP4Core.pi
        let no = no_unkozai
        var iretn: Int
        let delt: Double
        var ft: Double
        let theta: Double
        var x2li, x2omi: Double
        let xl: Double
        var xldot = 0.0, xnddt = 0.0, xndt = 0.0
        var xomi: Double
        let g22, g32, g44, g52, g54, fasx2, fasx4, fasx6, rptim, step2, stepn, stepp: Double

        fasx2 = 0.13130908
        fasx4 = 2.8843198
        fasx6 = 0.37448087
        g22 = 5.7686396
        g32 = 0.95240898
        g44 = 1.8014998
        g52 = 1.0508330
        g54 = 4.4108898
        rptim = 4.37526908801129966e-3
        stepp = 720.0
        stepn = -720.0
        step2 = 259200.0

        dndt = 0.0
        theta = fmod(gsto + tc * rptim, twopi)
        em = em + dedt * t

        inclm = inclm + didt * t
        argpm = argpm + domdt * t
        nodem = nodem + dnodt * t
        mm = mm + dmdt * t

        ft = 0.0
        if irez != 0 {
            if (atime == 0.0) || (t * atime <= 0.0) || (fabs(t) < fabs(atime)) {
                atime = 0.0
                xni = no
                xli = xlamo
            }
            if t > 0.0 {
                delt = stepp
            } else {
                delt = stepn
            }

            iretn = 381
            while iretn == 381 {
                if irez != 2 {
                    xndt = del1 * sin(xli - fasx2) + del2 * sin(2.0 * (xli - fasx4)) +
                        del3 * sin(3.0 * (xli - fasx6))
                    xldot = xni + xfact
                    xnddt = del1 * cos(xli - fasx2) +
                        2.0 * del2 * cos(2.0 * (xli - fasx4)) +
                        3.0 * del3 * cos(3.0 * (xli - fasx6))
                    xnddt = xnddt * xldot
                } else {
                    xomi = argpo + argpdot * atime
                    x2omi = xomi + xomi
                    x2li = xli + xli
                    xndt = d2201 * sin(x2omi + xli - g22) + d2211 * sin(xli - g22) +
                        d3210 * sin(xomi + xli - g32) + d3222 * sin(-xomi + xli - g32) +
                        d4410 * sin(x2omi + x2li - g44) + d4422 * sin(x2li - g44) +
                        d5220 * sin(xomi + xli - g52) + d5232 * sin(-xomi + xli - g52) +
                        d5421 * sin(xomi + x2li - g54) + d5433 * sin(-xomi + x2li - g54)
                    xldot = xni + xfact
                    xnddt = d2201 * cos(x2omi + xli - g22) + d2211 * cos(xli - g22) +
                        d3210 * cos(xomi + xli - g32) + d3222 * cos(-xomi + xli - g32) +
                        d5220 * cos(xomi + xli - g52) + d5232 * cos(-xomi + xli - g52) +
                        2.0 * (d4410 * cos(x2omi + x2li - g44) +
                        d4422 * cos(x2li - g44) + d5421 * cos(xomi + x2li - g54) +
                        d5433 * cos(-xomi + x2li - g54))
                    xnddt = xnddt * xldot
                }

                if fabs(t - atime) >= stepp {
                    iretn = 381
                } else {
                    ft = t - atime
                    iretn = 0
                }

                if iretn == 381 {
                    xli = xli + xldot * delt + xndt * step2
                    xni = xni + xndt * delt + xnddt * step2
                    atime = atime + delt
                }
            }

            nm = xni + xndt * ft + xnddt * ft * ft * 0.5
            xl = xli + xldot * ft + xndt * ft * ft * 0.5
            if irez != 1 {
                mm = xl - 2.0 * nodem + 2.0 * theta
                dndt = nm - no
            } else {
                mm = xl - nodem - argpm + theta
                dndt = nm - no
            }
            nm = no + dndt
        }
    }

    // MARK: - initl

    struct Initial {
        var ainv = 0.0, ao = 0.0, con42 = 0.0, cosio = 0.0, cosio2 = 0.0, eccsq = 0.0, omeosq = 0.0
        var posq = 0.0, rp = 0.0, rteosq = 0.0, sinio = 0.0
    }

    /// The first quantities of the initialisation: the mean motion with the Kozai term removed, the semi-major
    /// axis, the sidereal time at the epoch. `epoch` is days from 1950 January 0.0.
    mutating func initl(epoch: Double) -> Initial {
        var o = Initial()
        let ak, d1: Double
        var del: Double
        let adel, po, x2o3: Double

        x2o3 = 2.0 / 3.0

        o.eccsq = ecco * ecco
        o.omeosq = 1.0 - o.eccsq
        o.rteosq = sqrt(o.omeosq)
        o.cosio = cos(inclo)
        o.cosio2 = o.cosio * o.cosio

        ak = pow(xke / no_kozai, x2o3)
        d1 = 0.75 * j2 * (3.0 * o.cosio2 - 1.0) / (o.rteosq * o.omeosq)
        del = d1 / (ak * ak)
        adel = ak * (1.0 - del * del - del *
            (1.0 / 3.0 + 134.0 * del * del / 81.0))
        del = d1 / (adel * adel)
        no_unkozai = no_kozai / (1.0 + del)

        o.ao = pow(xke / (no_unkozai), x2o3)
        o.sinio = sin(inclo)
        po = o.ao * o.omeosq
        o.con42 = 1.0 - 5.0 * o.cosio2
        con41 = -o.con42 - o.cosio2 - o.cosio2
        o.ainv = 1.0 / o.ao
        o.posq = po * po
        o.rp = o.ao * (1.0 - ecco)
        deepSpace = false

        gsto = SGP4Core.gstime(epoch + 2433281.5)
        return o
    }

    // MARK: - sgp4init

    /// Initialises the propagation of one element set, as the C++'s sgp4init does, and makes its first call, at
    /// the epoch.
    ///
    /// `epoch` is days from 1950 January 0.0 (the Julian date less 2433281.5). The angles are in radians, the mean
    /// motion `xno_kozai` in radians per minute, and the two derivatives in the units the C++'s reader leaves them
    /// in; propagation does not use the derivatives.
    init(_ whichconst: Gravity, afspc: Bool, epoch: Double, xbstar: Double, xndot: Double, xnddot: Double, xecco: Double,
         xargpo: Double, xinclo: Double, xmo: Double, xno_kozai: Double, xnodeo: Double) {
        let pi = SGP4Core.pi
        let cc1sq: Double
        let cc2: Double
        var cc3: Double
        let coef, coef1, cosio4: Double
        var dndt = 0.0
        var em, argpm, nodem: Double
        var inclm, mm, nm: Double
        let eeta, etasq: Double
        let perige, pinvsq, psisq: Double
        var qzms24: Double
        var sfour: Double
        let tc: Double
        let temp, temp1, temp2, temp3, tsi, xpidot: Double
        let xhdot1: Double
        let qzms2t, ss, x2o3: Double
        let delmotemp, qzms2ttemp, qzms24temp: Double

        let temp4 = 1.5e-12

        getgravconst(whichconst)

        error = 0
        self.afspc = afspc

        bstar = xbstar
        ndot = xndot
        nddot = xnddot
        ecco = xecco
        argpo = xargpo
        inclo = xinclo
        mo = xmo
        no_kozai = xno_kozai
        nodeo = xnodeo

        ss = 78.0 / radiusearthkm + 1.0
        qzms2ttemp = (120.0 - 78.0) / radiusearthkm
        qzms2t = qzms2ttemp * qzms2ttemp * qzms2ttemp * qzms2ttemp
        x2o3 = 2.0 / 3.0

        initializing = true
        t = 0.0

        let i = initl(epoch: epoch)
        let ao = i.ao, con42 = i.con42, cosio = i.cosio, cosio2 = i.cosio2, eccsq = i.eccsq, omeosq = i.omeosq
        let posq = i.posq, rp = i.rp, rteosq = i.rteosq, sinio = i.sinio

        a = pow(no_unkozai * tumin, (-2.0 / 3.0))
        alta = a * (1.0 + ecco) - 1.0
        altp = a * (1.0 - ecco) - 1.0
        error = 0

        if (omeosq >= 0.0) || (no_unkozai >= 0.0) {
            isimp = 0
            if rp < (220.0 / radiusearthkm + 1.0) {
                isimp = 1
            }
            sfour = ss
            qzms24 = qzms2t
            perige = (rp - 1.0) * radiusearthkm

            if perige < 156.0 {
                sfour = perige - 78.0
                if perige < 98.0 {
                    sfour = 20.0
                }
                qzms24temp = (120.0 - sfour) / radiusearthkm
                qzms24 = qzms24temp * qzms24temp * qzms24temp * qzms24temp
                sfour = sfour / radiusearthkm + 1.0
            }
            pinvsq = 1.0 / posq

            tsi = 1.0 / (ao - sfour)
            eta = ao * ecco * tsi
            etasq = eta * eta
            eeta = ecco * eta
            psisq = fabs(1.0 - etasq)
            coef = qzms24 * pow(tsi, 4.0)
            coef1 = coef / pow(psisq, 3.5)
            cc2 = coef1 * no_unkozai * (ao * (1.0 + 1.5 * etasq + eeta *
                (4.0 + etasq)) + 0.375 * j2 * tsi / psisq * con41 *
                (8.0 + 3.0 * etasq * (8.0 + etasq)))
            cc1 = bstar * cc2
            cc3 = 0.0
            if ecco > 1.0e-4 {
                cc3 = -2.0 * coef * tsi * j3oj2 * no_unkozai * sinio / ecco
            }
            x1mth2 = 1.0 - cosio2
            cc4 = 2.0 * no_unkozai * coef1 * ao * omeosq *
                (eta * (2.0 + 0.5 * etasq) + ecco *
                (0.5 + 2.0 * etasq) - j2 * tsi / (ao * psisq) *
                (-3.0 * con41 * (1.0 - 2.0 * eeta + etasq *
                (1.5 - 0.5 * eeta)) + 0.75 * x1mth2 *
                (2.0 * etasq - eeta * (1.0 + etasq)) * cos(2.0 * argpo)))
            cc5 = 2.0 * coef1 * ao * omeosq * (1.0 + 2.75 *
                (etasq + eeta) + eeta * etasq)
            cosio4 = cosio2 * cosio2
            temp1 = 1.5 * j2 * pinvsq * no_unkozai
            temp2 = 0.5 * temp1 * j2 * pinvsq
            temp3 = -0.46875 * j4 * pinvsq * pinvsq * no_unkozai
            mdot = no_unkozai + 0.5 * temp1 * rteosq * con41 + 0.0625 *
                temp2 * rteosq * (13.0 - 78.0 * cosio2 + 137.0 * cosio4)
            argpdot = -0.5 * temp1 * con42 + 0.0625 * temp2 *
                (7.0 - 114.0 * cosio2 + 395.0 * cosio4) +
                temp3 * (3.0 - 36.0 * cosio2 + 49.0 * cosio4)
            xhdot1 = -temp1 * cosio
            nodedot = xhdot1 + (0.5 * temp2 * (4.0 - 19.0 * cosio2) +
                2.0 * temp3 * (3.0 - 7.0 * cosio2)) * cosio
            xpidot = argpdot + nodedot
            omgcof = bstar * cc3 * cos(argpo)
            xmcof = 0.0
            if ecco > 1.0e-4 {
                xmcof = -x2o3 * coef * bstar / eeta
            }
            nodecf = 3.5 * omeosq * xhdot1 * cc1
            t2cof = 1.5 * cc1
            if fabs(cosio + 1.0) > 1.5e-12 {
                xlcof = -0.25 * j3oj2 * sinio * (3.0 + 5.0 * cosio) / (1.0 + cosio)
            } else {
                xlcof = -0.25 * j3oj2 * sinio * (3.0 + 5.0 * cosio) / temp4
            }
            aycof = -0.5 * j3oj2 * sinio
            delmotemp = 1.0 + eta * cos(mo)
            delmo = delmotemp * delmotemp * delmotemp
            sinmao = sin(mo)
            x7thm1 = 7.0 * cosio2 - 1.0

            if (2 * pi / no_unkozai) >= 225.0 {
                deepSpace = true
                isimp = 1
                tc = 0.0
                inclm = inclo

                let c = SGP4Core.dscom(epoch: epoch, ep: ecco, argpp: argpo, tc: tc, inclp: inclo, nodep: nodeo, np: no_unkozai)
                e3 = c.e3
                ee2 = c.ee2
                peo = c.peo
                pgho = c.pgho
                pho = c.pho
                pinco = c.pinco
                plo = c.plo
                se2 = c.se2
                se3 = c.se3
                sgh2 = c.sgh2
                sgh3 = c.sgh3
                sgh4 = c.sgh4
                sh2 = c.sh2
                sh3 = c.sh3
                si2 = c.si2
                si3 = c.si3
                sl2 = c.sl2
                sl3 = c.sl3
                sl4 = c.sl4
                xgh2 = c.xgh2
                xgh3 = c.xgh3
                xgh4 = c.xgh4
                xh2 = c.xh2
                xh3 = c.xh3
                xi2 = c.xi2
                xi3 = c.xi3
                xl2 = c.xl2
                xl3 = c.xl3
                xl4 = c.xl4
                zmol = c.zmol
                zmos = c.zmos
                em = c.em
                nm = c.nm

                // with init == 'y' dpper computes and changes nothing, so it is handed copies of the five elements
                var ep = ecco, inclp = inclo, nodep = nodeo, argpp = argpo, mp = mo
                dpper(t: t, initializing: true, ep: &ep, inclp: &inclp, nodep: &nodep, argpp: &argpp, mp: &mp)

                argpm = 0.0
                nodem = 0.0
                mm = 0.0

                dsinit(c, t: t, tc: tc, xpidot: xpidot, eccsq: eccsq, em: &em, argpm: &argpm, inclm: &inclm, mm: &mm,
                       nm: &nm, nodem: &nodem, dndt: &dndt)
            }

            if isimp != 1 {
                cc1sq = cc1 * cc1
                d2 = 4.0 * ao * tsi * cc1sq
                temp = d2 * tsi * cc1 / 3.0
                d3 = (17.0 * ao + sfour) * temp
                d4 = 0.5 * temp * ao * tsi * (221.0 * ao + 31.0 * sfour) *
                    cc1
                t3cof = d2 + 2.0 * cc1sq
                t4cof = 0.25 * (3.0 * d3 + cc1 *
                    (12.0 * d2 + 10.0 * cc1sq))
                t5cof = 0.2 * (3.0 * d4 +
                    12.0 * cc1 * d3 +
                    6.0 * d2 * d2 +
                    15.0 * cc1sq * (2.0 * d2 + cc1sq))
            }
        }

        var r = (0.0, 0.0, 0.0), v = (0.0, 0.0, 0.0)
        _ = sgp4(0.0, &r, &v)

        initializing = false
    }

    // MARK: - sgp4

    /// Propagates to `tsince` minutes from the epoch. The position, kilometres, and the velocity, kilometres per
    /// second, are in the true equator, mean equinox frame of the epoch (TEME). False when the call stopped, with
    /// `error` saying why; for a decayed satellite (6) the position and velocity are filled in all the same.
    mutating func sgp4(_ tsince: Double, _ r: inout (Double, Double, Double), _ v: inout (Double, Double, Double)) -> Bool {
        let pi = SGP4Core.pi
        var am: Double
        let axnl, aynl, betal: Double
        var cosim: Double
        let cnod: Double
        let cos2u: Double
        var coseo1 = 0.0
        let cosi: Double
        var cosip: Double
        let cosisq, cossu, cosu: Double
        let delm, delomg: Double
        var em: Double
        let emsq, ecose, el2: Double
        var eo1: Double
        var ep: Double
        let esine: Double
        var argpm, argpp: Double
        let argpdf, pl: Double
        var mrt = 0.0
        let mvt, rdotl, rl, rvdot, rvdotl: Double
        var sinim: Double
        let sin2u: Double
        var sineo1 = 0.0
        let sini: Double
        var sinip: Double
        let sinsu, sinu: Double
        let snod: Double
        var su: Double
        let t2, t3, t4: Double
        var tem5, temp: Double
        let temp1, temp2: Double
        var tempa, tempe, templ: Double
        let u, ux: Double
        let uy, uz, vx, vy, vz: Double
        var inclm, mm: Double
        var nm, nodem: Double
        let xinc: Double
        var xincp: Double
        let xl: Double
        var xlm, mp: Double
        let xmdf, xmx, xmy, nodedf, xnode: Double
        var nodep: Double
        let tc: Double
        var dndt = 0.0
        let twopi, x2o3, vkmpersec, delmtemp: Double
        var ktr: Int

        let temp4 = 1.5e-12
        twopi = 2.0 * pi
        x2o3 = 2.0 / 3.0
        vkmpersec = radiusearthkm * xke / 60.0

        t = tsince
        error = 0

        xmdf = mo + mdot * t
        argpdf = argpo + argpdot * t
        nodedf = nodeo + nodedot * t
        argpm = argpdf
        mm = xmdf
        t2 = t * t
        nodem = nodedf + nodecf * t2
        tempa = 1.0 - cc1 * t
        tempe = bstar * cc4 * t
        templ = t2cof * t2

        if isimp != 1 {
            delomg = omgcof * t
            delmtemp = 1.0 + eta * cos(xmdf)
            delm = xmcof *
                (delmtemp * delmtemp * delmtemp -
                delmo)
            temp = delomg + delm
            mm = xmdf + temp
            argpm = argpdf - temp
            t3 = t2 * t
            t4 = t3 * t
            tempa = tempa - d2 * t2 - d3 * t3 -
                d4 * t4
            tempe = tempe + bstar * cc5 * (sin(mm) -
                sinmao)
            templ = templ + t3cof * t3 + t4 * (t4cof +
                t * t5cof)
        }

        nm = no_unkozai
        em = ecco
        inclm = inclo
        if deepSpace {
            tc = t
            dspace(t: t, tc: tc, em: &em, argpm: &argpm, inclm: &inclm, mm: &mm, nodem: &nodem, dndt: &dndt, nm: &nm)
        }

        if nm <= 0.0 {
            error = 2
            return false
        }
        am = pow((xke / nm), x2o3) * tempa * tempa
        nm = xke / pow(am, 1.5)
        em = em - tempe

        if (em >= 1.0) || (em < -0.001) {
            error = 1
            return false
        }
        if em < 1.0e-6 {
            em = 1.0e-6
        }
        mm = mm + no_unkozai * templ
        xlm = mm + argpm + nodem
        emsq = em * em
        temp = 1.0 - emsq

        nodem = fmod(nodem, twopi)
        argpm = fmod(argpm, twopi)
        xlm = fmod(xlm, twopi)
        mm = fmod(xlm - argpm - nodem, twopi)

        self.am = am
        self.em = em
        self.im = inclm
        self.Om = nodem
        self.om = argpm
        self.mm = mm
        self.nm = nm

        sinim = sin(inclm)
        cosim = cos(inclm)

        ep = em
        xincp = inclm
        argpp = argpm
        nodep = nodem
        mp = mm
        sinip = sinim
        cosip = cosim
        if deepSpace {
            dpper(t: t, initializing: false, ep: &ep, inclp: &xincp, nodep: &nodep, argpp: &argpp, mp: &mp)
            if xincp < 0.0 {
                xincp = -xincp
                nodep = nodep + pi
                argpp = argpp - pi
            }
            if (ep < 0.0) || (ep > 1.0) {
                error = 3
                return false
            }
        }

        if deepSpace {
            sinip = sin(xincp)
            cosip = cos(xincp)
            aycof = -0.5 * j3oj2 * sinip
            if fabs(cosip + 1.0) > 1.5e-12 {
                xlcof = -0.25 * j3oj2 * sinip * (3.0 + 5.0 * cosip) / (1.0 + cosip)
            } else {
                xlcof = -0.25 * j3oj2 * sinip * (3.0 + 5.0 * cosip) / temp4
            }
        }
        axnl = ep * cos(argpp)
        temp = 1.0 / (am * (1.0 - ep * ep))
        aynl = ep * sin(argpp) + temp * aycof
        xl = mp + argpp + nodep + temp * xlcof * axnl

        u = fmod(xl - nodep, twopi)
        eo1 = u
        tem5 = 9999.9
        ktr = 1
        while (fabs(tem5) >= 1.0e-12) && (ktr <= 10) {
            sineo1 = sin(eo1)
            coseo1 = cos(eo1)
            tem5 = 1.0 - coseo1 * axnl - sineo1 * aynl
            tem5 = (u - aynl * coseo1 + axnl * sineo1 - eo1) / tem5
            if fabs(tem5) >= 0.95 {
                tem5 = tem5 > 0.0 ? 0.95 : -0.95
            }
            eo1 = eo1 + tem5
            ktr = ktr + 1
        }

        ecose = axnl * coseo1 + aynl * sineo1
        esine = axnl * sineo1 - aynl * coseo1
        el2 = axnl * axnl + aynl * aynl
        pl = am * (1.0 - el2)
        if pl < 0.0 {
            error = 4
            return false
        } else {
            rl = am * (1.0 - ecose)
            rdotl = sqrt(am) * esine / rl
            rvdotl = sqrt(pl) / rl
            betal = sqrt(1.0 - el2)
            temp = esine / (1.0 + betal)
            sinu = am / rl * (sineo1 - aynl - axnl * temp)
            cosu = am / rl * (coseo1 - axnl + aynl * temp)
            su = atan2(sinu, cosu)
            sin2u = (cosu + cosu) * sinu
            cos2u = 1.0 - 2.0 * sinu * sinu
            temp = 1.0 / pl
            temp1 = 0.5 * j2 * temp
            temp2 = temp1 * temp

            if deepSpace {
                cosisq = cosip * cosip
                con41 = 3.0 * cosisq - 1.0
                x1mth2 = 1.0 - cosisq
                x7thm1 = 7.0 * cosisq - 1.0
            }
            mrt = rl * (1.0 - 1.5 * temp2 * betal * con41) +
                0.5 * temp1 * x1mth2 * cos2u
            su = su - 0.25 * temp2 * x7thm1 * sin2u
            xnode = nodep + 1.5 * temp2 * cosip * sin2u
            xinc = xincp + 1.5 * temp2 * cosip * sinip * cos2u
            mvt = rdotl - nm * temp1 * x1mth2 * sin2u / xke
            rvdot = rvdotl + nm * temp1 * (x1mth2 * cos2u +
                1.5 * con41) / xke

            sinsu = sin(su)
            cossu = cos(su)
            snod = sin(xnode)
            cnod = cos(xnode)
            sini = sin(xinc)
            cosi = cos(xinc)
            xmx = -snod * cosi
            xmy = cnod * cosi
            ux = xmx * sinsu + cnod * cossu
            uy = xmy * sinsu + snod * cossu
            uz = sini * sinsu
            vx = xmx * cossu - cnod * sinsu
            vy = xmy * cossu - snod * sinsu
            vz = sini * cossu

            r.0 = (mrt * ux) * radiusearthkm
            r.1 = (mrt * uy) * radiusearthkm
            r.2 = (mrt * uz) * radiusearthkm
            v.0 = (mvt * ux + rvdot * vx) * vkmpersec
            v.1 = (mvt * uy + rvdot * vy) * vkmpersec
            v.2 = (mvt * uz + rvdot * vz) * vkmpersec
        }

        if mrt < 1.0 {
            error = 6
            return false
        }

        return true
    }
}

// MARK: - From an element set

extension SGP4Core {
    /// The propagation of an element set, with the conversions the C++'s reader makes: degrees to radians,
    /// revolutions per day to radians per minute. The epoch is the set's own, exactly, unless `epoch` gives
    /// another count of days from 1950 January 0.0 (the tests do, to stand where the C++'s reader stands).
    init(_ set: ElementSet, gravity: Gravity = .wgs72, afspc: Bool = false, epoch: Double? = nil) {
        let pi = SGP4Core.pi
        let deg2rad = pi / 180.0
        let xpdotp = 1440.0 / (2.0 * pi)
        self.init(gravity, afspc: afspc, epoch: epoch ?? set.epoch.daysSince1950,
                  xbstar: set.bstar.double,
                  xndot: set.meanMotionDot.double / (xpdotp * 1440.0),
                  xnddot: set.meanMotionDDot.double / (xpdotp * 1440.0 * 1440),
                  xecco: set.eccentricity.double,
                  xargpo: set.argumentOfPericenter.double * deg2rad,
                  xinclo: set.inclination.double * deg2rad,
                  xmo: set.meanAnomaly.double * deg2rad,
                  xno_kozai: set.meanMotion.double / xpdotp,
                  xnodeo: set.rightAscension.double * deg2rad)
    }
}
