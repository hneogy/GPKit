// The oracle GPKit's SGP4 is compared with: David Vallado's SGP4.cpp, as CelesTrak publishes it, compiled here
// unmodified. vallado/SGP4.cpp and vallado/SGP4.h are the two files of software/cpp/SGP4/SGP4/ in
// CelesTrak/fundamentals-of-astrodynamics at commit 49df0479c950, byte for byte (see ../../NOTICE).
//
// The file is brought in by inclusion and not compiled on its own so that one thing can be said to the compiler
// first: not to fuse a multiplication and an addition into one operation. Clang does that by default on arm64, and
// Swift never does, so without this the two would differ in the last bit for a reason that is neither's arithmetic.

#pragma STDC FP_CONTRACT OFF

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Weverything"
#include "vallado/SGP4.cpp"
#pragma clang diagnostic pop

#include "SGP4Oracle.h"

#include <cstring>

struct sgp4oracle {
    elsetrec satrec;
};

extern "C" {

sgp4oracle *sgp4oracle_twoline(const char *line1, const char *line2, int verification, char opsmode, int whichconst,
                               sgp4oracle_elements *elements, double times[3]) {
    char first[130], second[130];
    std::memset(first, 0, sizeof first);
    std::memset(second, 0, sizeof second);
    std::strncpy(first, line1, sizeof first - 1);
    std::strncpy(second, line2, sizeof second - 1);
    sgp4oracle *oracle = new sgp4oracle();
    std::memset(&oracle->satrec, 0, sizeof oracle->satrec);
    double start = 0.0, stop = 0.0, step = 0.0;
    // 'v': a verification run, the times read from line 2. 'c': a catalog run, which asks nothing of the terminal.
    SGP4Funcs::twoline2rv(first, second, verification ? 'v' : 'c', 'e', opsmode, static_cast<gravconsttype>(whichconst),
                          start, stop, step, oracle->satrec);
    const elsetrec &s = oracle->satrec;
    if (elements) {
        elements->epoch = (s.jdsatepoch + s.jdsatepochF) - 2433281.5;
        elements->bstar = s.bstar;
        elements->ndot = s.ndot;
        elements->nddot = s.nddot;
        elements->ecco = s.ecco;
        elements->argpo = s.argpo;
        elements->inclo = s.inclo;
        elements->mo = s.mo;
        elements->no_kozai = s.no_kozai;
        elements->nodeo = s.nodeo;
    }
    if (times) {
        times[0] = start;
        times[1] = stop;
        times[2] = step;
    }
    return oracle;
}

sgp4oracle *sgp4oracle_init(int whichconst, char opsmode, const sgp4oracle_elements *e) {
    sgp4oracle *oracle = new sgp4oracle();
    std::memset(&oracle->satrec, 0, sizeof oracle->satrec);
    SGP4Funcs::sgp4init(static_cast<gravconsttype>(whichconst), opsmode, "00000", e->epoch, e->bstar, e->ndot, e->nddot,
                        e->ecco, e->argpo, e->inclo, e->mo, e->no_kozai, e->nodeo, oracle->satrec);
    return oracle;
}

int sgp4oracle_sgp4(sgp4oracle *oracle, double tsince, double r[3], double v[3]) {
    SGP4Funcs::sgp4(oracle->satrec, tsince, r, v);
    return oracle->satrec.error;
}

int sgp4oracle_is_deep_space(const sgp4oracle *oracle) {
    return oracle->satrec.method == 'd';
}

void sgp4oracle_free(sgp4oracle *oracle) {
    delete oracle;
}

}
