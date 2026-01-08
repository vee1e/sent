/* See LICENSE file for copyright and license details. */
/* macOS Native Port - Cocoa/CoreGraphics implementation */
/* 
 * Coordinate system: Uses standard CoreGraphics/NSView coordinates
 * Origin at bottom-left, Y increases upward.
 */

#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

static CGContextRef
create_bitmap_context(unsigned int w, unsigned int h)
{
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
        NULL,           /* data - let CG allocate */
        w, h,
        8,              /* bits per component */
        w * 4,          /* bytes per row */
        colorSpace,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little
    );
    CGColorSpaceRelease(colorSpace);
    
    return context;
}

Drw *
drw_create(unsigned int w, unsigned int h)
{
    Drw *drw = ecalloc(1, sizeof(Drw));

    drw->w = w;
    drw->h = h;
    drw->screen = 0;
    drw->drawable = create_bitmap_context(w, h);
    
    if (!drw->drawable) {
        free(drw);
        return NULL;
    }

    return drw;
}

void
drw_resize(Drw *drw, unsigned int w, unsigned int h)
{
    if (!drw)
        return;

    drw->w = w;
    drw->h = h;
    
    if (drw->drawable)
        CGContextRelease(drw->drawable);
    
    drw->drawable = create_bitmap_context(w, h);
}

void
drw_free(Drw *drw)
{
    if (!drw)
        return;
    
    if (drw->drawable)
        CGContextRelease(drw->drawable);
    
    free(drw);
}

/* Create a font from name */
static Fnt *
font_create(Drw *drw, const char *fontname)
{
    Fnt *font;
    CTFontRef ctFont = NULL;
    
    if (!fontname)
        return NULL;
    
    /* Parse font name - handle "fontname:size=X" format */
    char *fname = strdup(fontname);
    char *sizeStr = strstr(fname, ":size=");
    CGFloat fontSize = 12.0; /* default size */
    
    if (sizeStr) {
        *sizeStr = '\0';
        fontSize = atof(sizeStr + 6);
    }
    
    NSString *nsName = [NSString stringWithUTF8String:fname];
    free(fname);
    
    /* Try to find the font */
    ctFont = CTFontCreateWithName((__bridge CFStringRef)nsName, fontSize, NULL);
    
    if (!ctFont) {
        /* Fallback to system font */
        ctFont = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, fontSize, NULL);
    }
    
    if (!ctFont) {
        fprintf(stderr, "error, cannot load font: '%s'\n", fontname);
        return NULL;
    }
    
    font = ecalloc(1, sizeof(Fnt));
    font->ctFont = ctFont;
    font->ascent = CTFontGetAscent(ctFont);
    font->h = font->ascent + CTFontGetDescent(ctFont);
    font->next = NULL;
    
    return font;
}

static void
font_free(Fnt *font)
{
    if (!font)
        return;
    if (font->ctFont)
        CFRelease(font->ctFont);
    free(font);
}

Fnt*
drw_fontset_create(Drw* drw, const char *fonts[], size_t fontcount)
{
    Fnt *cur, *ret = NULL;
    size_t i;

    if (!drw || !fonts)
        return NULL;

    for (i = 1; i <= fontcount; i++) {
        if ((cur = font_create(drw, fonts[fontcount - i]))) {
            cur->next = ret;
            ret = cur;
        }
    }
    return (drw->fonts = ret);
}

void
drw_fontset_free(Fnt *font)
{
    if (font) {
        drw_fontset_free(font->next);
        font_free(font);
    }
}

/* Parse hex color string like "#RRGGBB" */
static int
parse_color(const char *clrname, CGFloat *r, CGFloat *g, CGFloat *b)
{
    if (!clrname || clrname[0] != '#' || strlen(clrname) != 7)
        return 0;
    
    unsigned int rv, gv, bv;
    if (sscanf(clrname + 1, "%02x%02x%02x", &rv, &gv, &bv) != 3)
        return 0;
    
    *r = rv / 255.0;
    *g = gv / 255.0;
    *b = bv / 255.0;
    return 1;
}

void
drw_clr_create(Drw *drw, Clr *dest, const char *clrname)
{
    if (!drw || !dest || !clrname)
        return;

    CGFloat r = 0, g = 0, b = 0;
    
    if (!parse_color(clrname, &r, &g, &b)) {
        /* Try named color */
        NSString *name = [NSString stringWithUTF8String:clrname];
        
        /* Try common color names */
        if ([name isEqualToString:@"black"]) {
            r = g = b = 0;
        } else if ([name isEqualToString:@"white"]) {
            r = g = b = 1;
        } else {
            /* Default to black */
            r = g = b = 0;
        }
    }
    
    dest->r = r;
    dest->g = g;
    dest->b = b;
    dest->a = 1.0;
    dest->pixel = ((unsigned long)(r * 255) << 16) |
                  ((unsigned long)(g * 255) << 8) |
                  ((unsigned long)(b * 255));
}

Clr *
drw_scm_create(Drw *drw, const char *clrnames[], size_t clrcount)
{
    size_t i;
    Clr *ret;

    /* need at least two colors for a scheme */
    if (!drw || !clrnames || clrcount < 2)
        return NULL;
    
    ret = ecalloc(clrcount, sizeof(Clr));
    
    for (i = 0; i < clrcount; i++)
        drw_clr_create(drw, &ret[i], clrnames[i]);
    
    return ret;
}

void
drw_setfontset(Drw *drw, Fnt *set)
{
    if (drw)
        drw->fonts = set;
}

void
drw_setscheme(Drw *drw, Clr *scm)
{
    if (drw)
        drw->scheme = scm;
}

/* 
 * Draw a rectangle.
 * Input: x, y are in top-left origin coordinates (like X11)
 * We convert to bottom-left origin for CoreGraphics
 */
void
drw_rect(Drw *drw, int x, int y, unsigned int w, unsigned int h, int filled, int invert)
{
    if (!drw || !drw->scheme || !drw->drawable)
        return;
    
    Clr *clr = invert ? &drw->scheme[ColBg] : &drw->scheme[ColFg];
    CGContextSetRGBFillColor(drw->drawable, clr->r, clr->g, clr->b, clr->a);
    CGContextSetRGBStrokeColor(drw->drawable, clr->r, clr->g, clr->b, clr->a);
    
    /* Convert from top-left origin (X11 style) to bottom-left origin (CoreGraphics) */
    int cg_y = drw->h - y - h;
    CGRect rect = CGRectMake(x, cg_y, w, h);
    
    if (filled)
        CGContextFillRect(drw->drawable, rect);
    else
        CGContextStrokeRect(drw->drawable, rect);
}

/* 
 * Draw text.
 * Input: x, y are in top-left origin coordinates (like X11)
 * We convert to bottom-left origin for CoreGraphics/CoreText
 */
int
drw_text(Drw *drw, int x, int y, unsigned int w, unsigned int h, unsigned int lpad, const char *text, int invert)
{
    if (!drw || !drw->scheme || !text || !drw->fonts)
        return 0;
    
    int render = x || y || w || h;
    
    if (!render) {
        w = ~w;
    }
    
    Fnt *usedfont = drw->fonts;
    
    /* Create attributed string */
    NSString *nsText = [NSString stringWithUTF8String:text];
    if (!nsText || [nsText length] == 0)
        return x;
    
    /* Set up attributes */
    Clr *fgClr = invert ? &drw->scheme[ColBg] : &drw->scheme[ColFg];
    Clr *bgClr = invert ? &drw->scheme[ColFg] : &drw->scheme[ColBg];
    
    NSColor *fgColor = [NSColor colorWithRed:fgClr->r green:fgClr->g blue:fgClr->b alpha:1.0];
    
    NSDictionary *attrs = @{
        (__bridge id)kCTFontAttributeName: (__bridge id)usedfont->ctFont,
        (__bridge id)kCTForegroundColorAttributeName: (__bridge id)[fgColor CGColor]
    };
    
    NSAttributedString *attrStr = [[NSAttributedString alloc] initWithString:nsText 
                                                                  attributes:attrs];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attrStr);
    
    /* Get text width */
    CGFloat textWidth = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    
    if (render && drw->drawable) {
        /* Convert from top-left origin to bottom-left origin */
        int cg_y = drw->h - y - h;
        
        /* Fill background */
        CGContextSetRGBFillColor(drw->drawable, bgClr->r, bgClr->g, bgClr->b, bgClr->a);
        CGContextFillRect(drw->drawable, CGRectMake(x, cg_y, w, h));
        
        /* Calculate text baseline position in CoreGraphics coordinates */
        /* The text should be vertically centered. In CG coords, baseline is above the rect bottom. */
        CGFloat descent = CTFontGetDescent(usedfont->ctFont);
        CGFloat textBaseline = cg_y + (h - usedfont->h) / 2 + descent;
        
        /* Draw text */
        CGContextSetTextPosition(drw->drawable, x + lpad, textBaseline);
        CTLineDraw(line, drw->drawable);
    }
    
    CFRelease(line);
    
    return x + (render ? w : (unsigned int)textWidth);
}

void
drw_map(Drw *drw, NSView *view, int x, int y, unsigned int w, unsigned int h)
{
    if (!drw || !view)
        return;
    
    [view setNeedsDisplay:YES];
}

CGImageRef
drw_get_image(Drw *drw)
{
    if (!drw || !drw->drawable)
        return NULL;
    
    return CGBitmapContextCreateImage(drw->drawable);
}

unsigned int
drw_fontset_getwidth(Drw *drw, const char *text)
{
    if (!drw || !drw->fonts || !text)
        return 0;
    return drw_text(drw, 0, 0, 0, 0, 0, text, 0);
}

void
drw_font_getexts(Fnt *font, const char *text, unsigned int len, unsigned int *w, unsigned int *h)
{
    if (!font || !text)
        return;

    NSString *nsText = [[NSString alloc] initWithBytes:text 
                                                length:len 
                                              encoding:NSUTF8StringEncoding];
    if (!nsText) {
        if (w) *w = 0;
        if (h) *h = (unsigned int)font->h;
        return;
    }
    
    NSDictionary *attrs = @{
        (__bridge id)kCTFontAttributeName: (__bridge id)font->ctFont
    };
    
    NSAttributedString *attrStr = [[NSAttributedString alloc] initWithString:nsText 
                                                                  attributes:attrs];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)attrStr);
    
    CGFloat width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    
    CFRelease(line);
    
    if (w)
        *w = (unsigned int)width;
    if (h)
        *h = (unsigned int)font->h;
}

Cur *
drw_cur_create(Drw *drw, int shape)
{
    Cur *cur;

    if (!drw)
        return NULL;
    
    cur = ecalloc(1, sizeof(Cur));
    cur->cursor = [NSCursor arrowCursor];
    
    return cur;
}

void
drw_cur_free(Drw *drw, Cur *cursor)
{
    if (!cursor)
        return;
    
    /* NSCursor is managed by ARC */
    cursor->cursor = nil;
    free(cursor);
}
