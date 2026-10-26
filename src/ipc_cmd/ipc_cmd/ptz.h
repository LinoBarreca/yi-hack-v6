#define V5               1
#define MSTAR            2
#define ALLWINNER        3
#define ALLWINNER_V2     4
#define ALLWINNER_V2_ALT 5

int is_ptz(char *model);
int get_model_suffix(char *model, int size);
int read_ptz(int *px, int *py);

/* Native PTZ (no stock dispatch): direction codes of the ms41909 driver. */
#define NATIVE_UP    1
#define NATIVE_DOWN  2
#define NATIVE_LEFT  3
#define NATIVE_RIGHT 4

int native_ptz_available();
int native_ptz_move(int dir);
int native_ptz_stop();
int native_ptz_jump(int x, int y);
int native_ptz_calibrate();
