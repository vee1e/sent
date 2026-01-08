/* See LICENSE file for copyright and license details. */
/* macOS Native Port - Cocoa/CoreGraphics implementation */

#ifndef DRW_H
#define DRW_H

#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>

typedef struct {
    NSCursor *cursor;
} Cur;

typedef struct Fnt {
    CTFontRef ctFont;
    CGFloat h;  /* height: ascent + descent */
    CGFloat ascent;
    struct Fnt *next;
} Fnt;

enum { ColFg, ColBg }; /* Clr scheme index */

typedef struct {
    CGFloat r, g, b, a;
    unsigned long pixel; /* packed RGB for compatibility */
} Clr;

typedef struct {
    unsigned int w, h;
    int screen;
    CGContextRef drawable;  /* bitmap context for offscreen drawing */
    Clr *scheme;
    Fnt *fonts;
} Drw;

/* Drawable abstraction */
Drw *drw_create(unsigned int w, unsigned int h);
void drw_resize(Drw *drw, unsigned int w, unsigned int h);
void drw_free(Drw *drw);

/* Fnt abstraction */
Fnt *drw_fontset_create(Drw* drw, const char *fonts[], size_t fontcount);
void drw_fontset_free(Fnt* set);
unsigned int drw_fontset_getwidth(Drw *drw, const char *text);
void drw_font_getexts(Fnt *font, const char *text, unsigned int len, unsigned int *w, unsigned int *h);

/* Colorscheme abstraction */
void drw_clr_create(Drw *drw, Clr *dest, const char *clrname);
Clr *drw_scm_create(Drw *drw, const char *clrnames[], size_t clrcount);

/* Cursor abstraction */
Cur *drw_cur_create(Drw *drw, int shape);
void drw_cur_free(Drw *drw, Cur *cursor);

/* Drawing context manipulation */
void drw_setfontset(Drw *drw, Fnt *set);
void drw_setscheme(Drw *drw, Clr *scm);

/* Drawing functions */
void drw_rect(Drw *drw, int x, int y, unsigned int w, unsigned int h, int filled, int invert);
int drw_text(Drw *drw, int x, int y, unsigned int w, unsigned int h, unsigned int lpad, const char *text, int invert);

/* Map functions - draws the offscreen buffer to a view */
void drw_map(Drw *drw, NSView *view, int x, int y, unsigned int w, unsigned int h);

/* Get CGImage from drawable for display */
CGImageRef drw_get_image(Drw *drw);

#endif /* DRW_H */
