// The test oracle: a C interface over Vallado's SGP4.cpp, which this target compiles as it is (see ../oracle.cpp).
// It is for GPKit's tests and is no part of the library.
#ifndef SGP4_ORACLE_H
#define SGP4_ORACLE_H

#ifdef __cplusplus
extern "C" {
#endif

/// An initialised `elsetrec`.
typedef struct sgp4oracle sgp4oracle;

/// The arguments of sgp4init, in its units: the epoch in days from 1950 January 0.0, angles in radians, the mean
/// motion in radians per minute.
typedef struct {
    double epoch, bstar, ndot, nddot, ecco, argpo, inclo, mo, no_kozai, nodeo;
} sgp4oracle_elements;

enum { SGP4ORACLE_WGS72OLD = 0, SGP4ORACLE_WGS72 = 1, SGP4ORACLE_WGS84 = 2 };

/// twoline2rv() on a line pair, which reads the lines and calls sgp4init(). With `verification` non-zero line 2 is
/// read as a verification case's, with the start, the stop and the step in minutes after column 69, returned in
/// `times`. `elements` receives what the reader passed to sgp4init().
sgp4oracle *sgp4oracle_twoline(const char *line1, const char *line2, int verification, char opsmode, int whichconst,
                               sgp4oracle_elements *elements, double times[3]);

/// sgp4init() on the arguments given.
sgp4oracle *sgp4oracle_init(int whichconst, char opsmode, const sgp4oracle_elements *elements);

/// sgp4() at `tsince` minutes from the epoch. Returns `satrec.error`, 0 when the call went through.
int sgp4oracle_sgp4(sgp4oracle *oracle, double tsince, double r[3], double v[3]);

/// 1 when the element set took the deep-space branch.
int sgp4oracle_is_deep_space(const sgp4oracle *oracle);

void sgp4oracle_free(sgp4oracle *oracle);

#ifdef __cplusplus
}
#endif

#endif
