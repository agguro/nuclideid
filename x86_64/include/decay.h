#ifndef NUCLIDEID_DECAY_H
#define NUCLIDEID_DECAY_H
#include <stddef.h>
/* Raw samples are interleaved (t,y) doubles until decay_prepare transforms
 * them in place to ((t-t0)/span,log(y)-log(y0)). Count: 3..1000000.
 * The caller owns data and frees it with free(). */
struct decay_work {
    double *data;
    size_t count;
    double t0, span, log_y0;
};
struct decay_fit {
    double k, half_life_seconds, log_amplitude, log_rmse, r_squared;
};
int decay_parse_number(const char *text, double *out);
int decay_csv_load(const char *path, struct decay_work *out);
int decay_prepare(struct decay_work *work);
void decay_moments_cpu(const struct decay_work *work, double stats[5]);
int decay_finish(const struct decay_work *work, const double stats[5], struct decay_fit *fit);
#endif
