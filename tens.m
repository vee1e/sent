/* See LICENSE file for copyright and license details. */
/* macOS Native Port - Main Application */
/* Supports native image formats via NSImage (PNG, JPEG, GIF, etc.) */

/* Include Cocoa FIRST to get all Apple frameworks properly set up */
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

/* Standard C headers */
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "arg.h"
#include "drw.h"

/* Avoid MIN/MAX conflicts with Foundation */
#undef MAX
#undef MIN
#define MAX(A, B)               ((A) > (B) ? (A) : (B))
#define MIN(A, B)               ((A) < (B) ? (A) : (B))
#define BETWEEN(X, A, B)        ((A) <= (X) && (X) <= (B))

/* Utility functions */
void die(const char *fmt, ...);
void *ecalloc(size_t nmemb, size_t size);

char *argv0;

/* macros */
#define LEN(a)         (sizeof(a) / sizeof(a)[0])
#define LIMIT(x, a, b) (x) = (x) < (a) ? (a) : (x) > (b) ? (b) : (x)
#define MAXFONTSTRLEN  128

typedef enum {
    IMGSTATE_NONE = 0,
    IMGSTATE_LOADED = 1,
    IMGSTATE_SCALED = 2,
} imgstate;

typedef struct {
    NSImage *nsImage;       /* Original loaded image */
    CGImageRef scaledImage; /* Scaled version for display */
    unsigned int origWidth, origHeight;
    unsigned int dispWidth, dispHeight;
    imgstate state;
} Image;

typedef struct {
    unsigned int linecount;
    char **lines;
    Image *img;
    char *embed;  /* Path to embedded image (if slide starts with @) */
} Slide;

/* Purely graphic info */
typedef struct {
    NSWindow *win;
    NSView *view;
    int w, h;
    int uw, uh; /* usable dimensions for drawing text and images */
} MacWindow;

typedef union {
    int i;
    unsigned int ui;
    float f;
    const void *v;
} Arg;

typedef struct {
    unsigned int b;
    void (*func)(const Arg *);
    const Arg arg;
} Mousekey;

typedef struct {
    unsigned short keysym;  /* macOS key code */
    void (*func)(const Arg *);
    const Arg arg;
} Shortcut;

static void imgfree(Image *img);
static void imgload(Slide *s);
static void imgprepare(Image *img);
static void imgdraw(Image *img, CGContextRef ctx);

static void getfontsize(Slide *s, unsigned int *width, unsigned int *height);
static void cleanup(int slidesonly);
static void reload(const Arg *arg);
static void load(FILE *fp);
static void advance(const Arg *arg);
static void quit(const Arg *arg);
static void cresize(int width, int height);
static void xdraw(void);
static void xloadfonts(void);

/* config.h for applying patches and the configuration. */
#include "config.h"

/* Globals */
static const char *fname = NULL;
static Slide *slides = NULL;
static int idx = 0;
static int slidecount = 0;
static MacWindow xw;
static Drw *d = NULL;
static Clr *sc;
static Fnt *fonts[NUMFONTSCALES];
static int running = 1;

/* Forward declarations for Objective-C classes */
@class SentView;
@class SentAppDelegate;

/* ============================================================ */
/* SentView - Custom NSView for drawing and event handling      */
/* ============================================================ */

@interface SentView : NSView
@end

@implementation SentView

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)canBecomeKeyView {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    
    if (!ctx || !d)
        return;
    
    /* Clear background */
    CGContextSetRGBFillColor(ctx, sc[ColBg].r, sc[ColBg].g, sc[ColBg].b, 1.0);
    CGContextFillRect(ctx, dirtyRect);
    
    if (idx < 0 || idx >= slidecount)
        return;
    
    Image *im = slides[idx].img;
    
    if (!im) {
        /* Draw text slide */
        CGImageRef drwImage = drw_get_image(d);
        if (drwImage) {
            NSRect bounds = [self bounds];
            CGContextDrawImage(ctx, CGRectMake(0, 0, bounds.size.width, bounds.size.height), drwImage);
            CGImageRelease(drwImage);
        }
    } else {
        /* Draw image slide */
        if (!(im->state & IMGSTATE_SCALED))
            imgprepare(im);
        imgdraw(im, ctx);
    }
}

- (void)keyDown:(NSEvent *)event {
    unsigned short keyCode = [event keyCode];
    
    for (size_t i = 0; i < LEN(shortcuts); i++) {
        if (keyCode == shortcuts[i].keysym && shortcuts[i].func) {
            shortcuts[i].func(&(shortcuts[i].arg));
            return;
        }
    }
}

- (void)mouseDown:(NSEvent *)event {
    for (size_t i = 0; i < LEN(mshortcuts); i++) {
        if (mshortcuts[i].b == MacMouseLeft && mshortcuts[i].func) {
            mshortcuts[i].func(&(mshortcuts[i].arg));
            return;
        }
    }
}

- (void)rightMouseDown:(NSEvent *)event {
    for (size_t i = 0; i < LEN(mshortcuts); i++) {
        if (mshortcuts[i].b == MacMouseRight && mshortcuts[i].func) {
            mshortcuts[i].func(&(mshortcuts[i].arg));
            return;
        }
    }
}

- (void)scrollWheel:(NSEvent *)event {
    CGFloat deltaY = [event scrollingDeltaY];
    
    if (deltaY > 0) {
        /* Scroll up */
        for (size_t i = 0; i < LEN(mshortcuts); i++) {
            if (mshortcuts[i].b == MacMouseScrollUp && mshortcuts[i].func) {
                mshortcuts[i].func(&(mshortcuts[i].arg));
                return;
            }
        }
    } else if (deltaY < 0) {
        /* Scroll down */
        for (size_t i = 0; i < LEN(mshortcuts); i++) {
            if (mshortcuts[i].b == MacMouseScrollDown && mshortcuts[i].func) {
                mshortcuts[i].func(&(mshortcuts[i].arg));
                return;
            }
        }
    }
}

- (void)viewDidEndLiveResize {
    [super viewDidEndLiveResize];
    NSRect bounds = [self bounds];
    cresize((int)bounds.size.width, (int)bounds.size.height);
    xdraw();
}

@end

/* ============================================================ */
/* SentAppDelegate - Application delegate                       */
/* ============================================================ */

@interface SentAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end

@implementation SentAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    /* Window is already created in xinit, just make it key */
    [xw.win makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    
    /* Initial draw */
    xdraw();
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)windowWillClose:(NSNotification *)notification {
    running = 0;
    [NSApp terminate:nil];
}

- (void)windowDidResize:(NSNotification *)notification {
    NSRect frame = [[xw.win contentView] frame];
    cresize((int)frame.size.width, (int)frame.size.height);
    /* Mark all images as needing rescaling */
    for (int i = 0; i < slidecount; i++) {
        if (slides[i].img)
            slides[i].img->state &= ~IMGSTATE_SCALED;
    }
    xdraw();
}

@end

/* ============================================================ */
/* Image handling functions (native macOS)                       */
/* ============================================================ */

void
imgfree(Image *img)
{
    if (!img)
        return;
    
    if (img->scaledImage)
        CGImageRelease(img->scaledImage);
    
    /* NSImage is managed by ARC */
    img->nsImage = nil;
    
    free(img);
}

void
imgload(Slide *s)
{
    if (s->img || !s->embed || !s->embed[0])
        return; /* already done or not an image slide */
    
    NSString *path = [NSString stringWithUTF8String:s->embed];
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
    
    if (!image) {
        fprintf(stderr, "tens: Unable to load image '%s'\n", s->embed);
        return;
    }
    
    s->img = ecalloc(1, sizeof(Image));
    s->img->nsImage = image;
    s->img->origWidth = (unsigned int)[image size].width;
    s->img->origHeight = (unsigned int)[image size].height;
    s->img->state = IMGSTATE_LOADED;
}

void
imgprepare(Image *img)
{
    if (!img || !img->nsImage)
        return;
    
    /* Calculate scaled dimensions to fit in usable area */
    int width = xw.uw;
    int height = xw.uh;
    
    if ((unsigned int)xw.uw * img->origHeight > (unsigned int)xw.uh * img->origWidth)
        width = img->origWidth * xw.uh / img->origHeight;
    else
        height = img->origHeight * xw.uw / img->origWidth;
    
    img->dispWidth = width;
    img->dispHeight = height;
    
    /* Release old scaled image if exists */
    if (img->scaledImage) {
        CGImageRelease(img->scaledImage);
        img->scaledImage = NULL;
    }
    
    /* Create scaled CGImage */
    NSSize newSize = NSMakeSize(width, height);
    NSImage *scaledNSImage = [[NSImage alloc] initWithSize:newSize];
    
    [scaledNSImage lockFocus];
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    [img->nsImage drawInRect:NSMakeRect(0, 0, width, height)
                    fromRect:NSZeroRect
                   operation:NSCompositingOperationCopy
                    fraction:1.0];
    
    /* Get CGImage from the context */
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    img->scaledImage = CGBitmapContextCreateImage(ctx);
    [scaledNSImage unlockFocus];
    
    img->state |= IMGSTATE_SCALED;
}

void
imgdraw(Image *img, CGContextRef ctx)
{
    if (!img || !img->scaledImage || !ctx)
        return;
    
    int xoffset = (xw.w - (int)img->dispWidth) / 2;
    int yoffset = (xw.h - (int)img->dispHeight) / 2;
    
    /* Draw the image centered */
    CGContextDrawImage(ctx, 
                       CGRectMake(xoffset, yoffset, img->dispWidth, img->dispHeight), 
                       img->scaledImage);
}

/* ============================================================ */
/* Core presentation logic                                       */
/* ============================================================ */

void
getfontsize(Slide *s, unsigned int *width, unsigned int *height)
{
    int i, j;
    unsigned int curw, newmax;
    float lfac = linespacing * (s->linecount - 1) + 1;

    /* fit height */
    for (j = NUMFONTSCALES - 1; j >= 0; j--)
        if (fonts[j]->h * lfac <= xw.uh)
            break;
    LIMIT(j, 0, NUMFONTSCALES - 1);
    drw_setfontset(d, fonts[j]);

    /* fit width */
    *width = 0;
    for (i = 0; i < (int)s->linecount; i++) {
        curw = drw_fontset_getwidth(d, s->lines[i]);
        newmax = (curw >= *width);
        while (j > 0 && curw > (unsigned int)xw.uw) {
            drw_setfontset(d, fonts[--j]);
            curw = drw_fontset_getwidth(d, s->lines[i]);
        }
        if (newmax)
            *width = curw;
    }
    *height = (unsigned int)(fonts[j]->h * lfac);
}

void
cleanup(int slidesonly)
{
    unsigned int i, j;

    if (!slidesonly) {
        for (i = 0; i < NUMFONTSCALES; i++)
            drw_fontset_free(fonts[i]);
        free(sc);
        drw_free(d);
    }

    if (slides) {
        for (i = 0; i < (unsigned int)slidecount; i++) {
            for (j = 0; j < slides[i].linecount; j++)
                free(slides[i].lines[j]);
            free(slides[i].lines);
            if (slides[i].img)
                imgfree(slides[i].img);
        }
        if (!slidesonly) {
            free(slides);
            slides = NULL;
        }
    }
}

void
reload(const Arg *arg)
{
    FILE *fp = NULL;
    unsigned int i;

    if (!fname) {
        fprintf(stderr, "tens: Cannot reload from stdin. Use a file!\n");
        return;
    }

    cleanup(1);
    slidecount = 0;

    if (!(fp = fopen(fname, "r")))
die("tens: Unable to open '%s' for reading:", fname);
	load(fp);
	fclose(fp);

	LIMIT(idx, 0, slidecount-1);
	for (i = 0; i < (unsigned int)slidecount; i++)
		imgload(&slides[i]);
	xdraw();
}

void
load(FILE *fp)
{
    static size_t size = 0;
    size_t blen, maxlines;
    char buf[BUFSIZ], *p;
    Slide *s;

    /* read each line from fp and add it to the item list */
    while (1) {
        /* eat consecutive empty lines */
        while ((p = fgets(buf, sizeof(buf), fp)))
            if (strcmp(buf, "\n") != 0 && buf[0] != '#')
                break;
        if (!p)
            break;

if ((slidecount+1) * sizeof(*slides) >= size)
			if (!(slides = realloc(slides, (size += BUFSIZ))))
				die("tens: Unable to reallocate %zu bytes:", size);

        /* read one slide */
        maxlines = 0;
        memset((s = &slides[slidecount]), 0, sizeof(Slide));
        do {
            /* if there's a leading null, we can't do blen-1 */
            if (buf[0] == '\0')
                continue;

            if (buf[0] == '#')
                continue;

/* grow lines array */
			if (s->linecount >= maxlines) {
				maxlines = 2 * s->linecount + 1;
				if (!(s->lines = realloc(s->lines, maxlines * sizeof(s->lines[0]))))
					die("tens: Unable to reallocate %zu bytes:", maxlines * sizeof(s->lines[0]));
			}

blen = strlen(buf);
			if (!(s->lines[s->linecount] = strdup(buf)))
				die("tens: Unable to strdup:");
            if (s->lines[s->linecount][blen-1] == '\n')
                s->lines[s->linecount][blen-1] = '\0';

            /* mark as image slide if first line of a slide starts with @ */
            if (s->linecount == 0 && s->lines[0][0] == '@')
                s->embed = &s->lines[0][1];

            /* Handle escape characters */
            if (s->lines[s->linecount][0] == '\\')
                memmove(s->lines[s->linecount], &s->lines[s->linecount][1], blen);
            s->linecount++;
        } while ((p = fgets(buf, sizeof(buf), fp)) && strcmp(buf, "\n") != 0);

        slidecount++;
        if (!p)
            break;
    }

if (!slidecount)
		die("tens: No slides in file");
}

void
advance(const Arg *arg)
{
    int new_idx = idx + arg->i;
    LIMIT(new_idx, 0, slidecount-1);
    if (new_idx != idx) {
        if (slides[idx].img)
            slides[idx].img->state &= ~IMGSTATE_SCALED;
        idx = new_idx;
        xdraw();
    }
}

void
quit(const Arg *arg)
{
    running = 0;
    [NSApp terminate:nil];
}

void
cresize(int width, int height)
{
    xw.w = width;
    xw.h = height;
    xw.uw = usablewidth * width;
    xw.uh = usableheight * height;
    drw_resize(d, width, height);
}

void
xdraw(void)
{
    unsigned int height, width, i;
    Image *im = slides[idx].img;

    if (!im) {
        /* Text slide */
        getfontsize(&slides[idx], &width, &height);
        
        drw_rect(d, 0, 0, xw.w, xw.h, 1, 1);
        for (i = 0; i < slides[idx].linecount; i++)
            drw_text(d,
                     (xw.w - width) / 2,
                     (xw.h - height) / 2 + i * linespacing * d->fonts->h,
                     width,
                     (unsigned int)d->fonts->h,
                     0,
                     slides[idx].lines[i],
                     0);
    }
    /* Image slides are drawn directly in drawRect */
    
    /* Trigger redraw */
    [xw.view setNeedsDisplay:YES];
}

void
xloadfonts(void)
{
    int i, j;
    char *fstrs[LEN(fontfallbacks)];

    for (j = 0; j < (int)LEN(fontfallbacks); j++) {
        fstrs[j] = ecalloc(1, MAXFONTSTRLEN);
    }

    for (i = 0; i < NUMFONTSCALES; i++) {
        for (j = 0; j < (int)LEN(fontfallbacks); j++) {
if (MAXFONTSTRLEN < snprintf(fstrs[j], MAXFONTSTRLEN, "%s:size=%d", fontfallbacks[j], FONTSZ(i)))
				die("tens: Font string too long");
        }
if (!(fonts[i] = drw_fontset_create(d, (const char**)fstrs, LEN(fstrs))))
			die("tens: Unable to load any font for size %d", FONTSZ(i));
    }

    for (j = 0; j < (int)LEN(fontfallbacks); j++)
        free(fstrs[j]);
}

void
xinit(void)
{
    unsigned int i;
    
    /* Get screen dimensions */
    NSScreen *screen = [NSScreen mainScreen];
    NSRect screenFrame = [screen frame];
    
    xw.w = (int)screenFrame.size.width;
    xw.h = (int)screenFrame.size.height;
    xw.uw = usablewidth * xw.w;
    xw.uh = usableheight * xw.h;
    
/* Create drawing context */
	if (!(d = drw_create(xw.w, xw.h)))
		die("tens: Unable to create drawing context");
    
    sc = drw_scm_create(d, colors, 2);
    drw_setscheme(d, sc);
    
    xloadfonts();
    
    /* Load images for all slides */
    for (i = 0; i < (unsigned int)slidecount; i++)
        imgload(&slides[i]);
    
    /* Create window */
    NSRect windowRect = NSMakeRect(0, 0, xw.w, xw.h);
    NSWindowStyleMask style = NSWindowStyleMaskTitled | 
                               NSWindowStyleMaskClosable | 
                               NSWindowStyleMaskMiniaturizable | 
                               NSWindowStyleMaskResizable;
    
    xw.win = [[NSWindow alloc] initWithContentRect:windowRect
                                         styleMask:style
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    
    [xw.win setTitle:@"tens"];
    [xw.win setBackgroundColor:[NSColor colorWithRed:sc[ColBg].r 
                                              green:sc[ColBg].g 
                                               blue:sc[ColBg].b 
                                              alpha:1.0]];
    
    /* Create custom view */
    xw.view = [[SentView alloc] initWithFrame:windowRect];
    [xw.win setContentView:xw.view];
    [xw.win makeFirstResponder:xw.view];
    
    /* Set up delegate */
    SentAppDelegate *delegate = [[SentAppDelegate alloc] init];
    [xw.win setDelegate:delegate];
    
    /* Center and show window */
    [xw.win center];
}

void
usage(void)
{
    die("usage: %s [file]", argv0);
}

int
main(int argc, char *argv[])
{
    FILE *fp = NULL;

    ARGBEGIN {
    case 'v':
        fprintf(stderr, "tens-"VERSION"\n");
        return 0;
    default:
        usage();
    } ARGEND

if (!argv[0] || !strcmp(argv[0], "-"))
		fp = stdin;
	else if (!(fp = fopen(fname = argv[0], "r")))
		die("tens: Unable to open '%s' for reading:", fname);
    load(fp);
    fclose(fp);

    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        
        /* Create app delegate */
        SentAppDelegate *appDelegate = [[SentAppDelegate alloc] init];
        [NSApp setDelegate:appDelegate];
        
        /* Initialize window and graphics */
        xinit();
        
        /* Run the application */
        [NSApp run];
    }

    cleanup(0);
    return 0;
}
