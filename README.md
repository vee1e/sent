# sent - Simple Plaintext Presentation Tool (macOS Native Port)

sent is a simple plaintext presentation tool that displays slides in a window.

This is a **native macOS port** that uses Cocoa/AppKit instead of X11, eliminating the need for XQuartz.

## Features

- **No dependencies** - Uses native macOS frameworks (Cocoa, CoreText, CoreGraphics)
- **Simple format** - Plain text files, one paragraph per slide
- **Auto-scaling** - Text automatically scales to fit the window
- **Image support** - Native support for PNG, JPEG, GIF, TIFF, BMP, and more
- **Keyboard navigation** - Arrow keys, vim keys, or mouse

## Building

```bash
make clean
make
```

## Usage

```bash
./sent [FILE]
```

If FILE is omitted or equals `-`, stdin will be read.

## Presentation Format

- Each paragraph (separated by empty lines) is one slide
- Lines starting with `#` are comments (ignored)
- Lines starting with `@` followed by a filename create image slides
- Use `\` at start of line to escape `@` and `#`

### Example

```
Welcome to sent

@logo.png

Features:
- Simple
- Fast
- Native macOS

# This is a comment

\@this shows the @ symbol

Thanks!
```

## Controls

| Key | Action |
|-----|--------|
| `→` `Space` `Return` `l` `j` `n` `PageDown` | Next slide |
| `←` `Backspace` `h` `k` `p` `PageUp` | Previous slide |
| `q` `Escape` | Quit |
| `r` | Reload presentation |
| Left click | Next slide |
| Right click | Previous slide |
| Scroll | Navigate slides |

## Supported Image Formats

All formats supported by macOS NSImage:
- PNG
- JPEG / JPG
- GIF
- TIFF
- BMP
- HEIC
- WebP (macOS 11+)
- And more...

## Configuration

Edit `config.def.h` before building to customize:
- Default fonts
- Colors (foreground/background)
- Key bindings
- Usable screen area

Then rebuild:
```bash
cp config.def.h config.h
make clean
make
```

## Installation

```bash
make install
```

This installs to `/usr/local/bin` by default. Change `PREFIX` in `config.mk` to install elsewhere.

## Original Project

This is a port of [sent](https://tools.suckless.org/sent/) from suckless.org.

The original version uses X11/Xlib and requires XQuartz on macOS. This port uses native Cocoa APIs for a better macOS experience.

## License

See LICENSE file for copyright and license details (MIT/X).
