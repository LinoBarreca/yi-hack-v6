#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <errno.h>

#define PARAM_SIZE    128
#define PARAM_OPTIONS 9

/* Row count is derived from the table itself (see validate.c) - it used to be a
 * hand-maintained #define, and it had drifted one row ahead of reality, so the
 * lookup loop walked off the end into an all-NULL row and passed NULL to
 * strcasecmp for every key not in the table. */
extern char *config_params[][PARAM_OPTIONS];
extern const int config_params_num;

int validate_param(char *file, char *key, char *value);
int extract_param(char *param, char *file, char *key, int index);
