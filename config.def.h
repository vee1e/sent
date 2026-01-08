/* See LICENSE file for copyright and license details. */
/* macOS Native Port - Configuration */
/* Note: Image support removed for simplicity */

#import <Carbon/Carbon.h> /* For key codes */

static char *fontfallbacks[] = {
    "SF Pro",
    "Helvetica Neue",
    "Helvetica",
};
#define NUMFONTSCALES 42
#define FONTSZ(x) ((int)(10.0 * powf(1.1288, (x)))) /* x in [0, NUMFONTSCALES-1] */

static const char *colors[] = {
    "#000000", /* foreground color */
    "#FFFFFF", /* background color */
};

static const float linespacing = 1.4;

/* how much screen estate is to be used at max for the content */
static const float usablewidth = 0.75;
static const float usableheight = 0.75;

/* macOS key codes (from Carbon/HIToolbox/Events.h) */
#define MAC_KEY_ESCAPE      0x35
#define MAC_KEY_Q           0x0C
#define MAC_KEY_R           0x0F
#define MAC_KEY_H           0x04
#define MAC_KEY_J           0x26
#define MAC_KEY_K           0x28
#define MAC_KEY_L           0x25
#define MAC_KEY_N           0x2D
#define MAC_KEY_P           0x23
#define MAC_KEY_SPACE       0x31
#define MAC_KEY_RETURN      0x24
#define MAC_KEY_DELETE      0x33  /* Backspace */
#define MAC_KEY_LEFT        0x7B
#define MAC_KEY_RIGHT       0x7C
#define MAC_KEY_DOWN        0x7D
#define MAC_KEY_UP          0x7E
#define MAC_KEY_PAGEUP      0x74
#define MAC_KEY_PAGEDOWN    0x79

/* Mouse button types for macOS */
typedef enum {
    MacMouseLeft = 0,
    MacMouseRight = 1,
    MacMouseScrollUp = 10,
    MacMouseScrollDown = 11,
} MacMouseButton;

static Mousekey mshortcuts[] = {
    /* button              function        argument */
    { MacMouseLeft,        advance,        {.i = +1} },
    { MacMouseRight,       advance,        {.i = -1} },
    { MacMouseScrollUp,    advance,        {.i = -1} },
    { MacMouseScrollDown,  advance,        {.i = +1} },
};

static Shortcut shortcuts[] = {
    /* keycode              function        argument */
    { MAC_KEY_ESCAPE,       quit,           {0} },
    { MAC_KEY_Q,            quit,           {0} },
    { MAC_KEY_RIGHT,        advance,        {.i = +1} },
    { MAC_KEY_LEFT,         advance,        {.i = -1} },
    { MAC_KEY_RETURN,       advance,        {.i = +1} },
    { MAC_KEY_SPACE,        advance,        {.i = +1} },
    { MAC_KEY_DELETE,       advance,        {.i = -1} },
    { MAC_KEY_L,            advance,        {.i = +1} },
    { MAC_KEY_H,            advance,        {.i = -1} },
    { MAC_KEY_J,            advance,        {.i = +1} },
    { MAC_KEY_K,            advance,        {.i = -1} },
    { MAC_KEY_DOWN,         advance,        {.i = +1} },
    { MAC_KEY_UP,           advance,        {.i = -1} },
    { MAC_KEY_PAGEDOWN,     advance,        {.i = +1} },
    { MAC_KEY_PAGEUP,       advance,        {.i = -1} },
    { MAC_KEY_N,            advance,        {.i = +1} },
    { MAC_KEY_P,            advance,        {.i = -1} },
    { MAC_KEY_R,            reload,         {0} },
};
