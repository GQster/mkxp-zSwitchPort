/* Force-included when building FluidSynth for Switch (configure_mkxpz.sh). */
#ifndef FLUIDSYNTH_SWITCH_COMPAT_H
#define FLUIDSYNTH_SWITCH_COMPAT_H

#include <pthread.h>
#include <sched.h>

/* newlib has no pthread_setschedparam. FluidSynth only uses it to raise the
 * priority of its own audio driver threads, which mkxp-z never starts (it
 * renders the synth itself), so report failure like an unprivileged POSIX
 * process would. */
static inline int pthread_setschedparam(pthread_t thread, int policy,
                                        const struct sched_param *param)
{
    (void)thread; (void)policy; (void)param;
    return -1;
}

#endif
