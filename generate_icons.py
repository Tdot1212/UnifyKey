#!/usr/bin/env python3
"""Generate UnifyKey app icons - globe/translation symbol on blue-to-teal gradient."""

from PIL import Image, ImageDraw, ImageFont
import math
import os

OUTPUT_DIR = "UnifyKey/Assets.xcassets/AppIcon.appiconset"

SIZES = [40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024]


def draw_icon(size):
    """Draw a clean, minimal globe icon on a blue-to-teal gradient background."""
    img = Image.new("RGBA", (size, size))
    draw = ImageDraw.Draw(img)

    # Blue-to-teal gradient (#007AFF to #00C6FB), diagonal
    r1, g1, b1 = 0x00, 0x7A, 0xFF  # #007AFF
    r2, g2, b2 = 0x00, 0xC6, 0xFB  # #00C6FB

    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * size)
            r = int(r1 + (r2 - r1) * t)
            g = int(g1 + (g2 - g1) * t)
            b = int(b1 + (b2 - b1) * t)
            img.putpixel((x, y), (r, g, b, 255))

    # Draw globe symbol in white
    cx, cy = size / 2, size / 2
    radius = size * 0.32
    line_width = max(1, int(size * 0.025))
    white = (255, 255, 255, 255)

    # Outer circle
    draw.ellipse(
        [cx - radius, cy - radius, cx + radius, cy + radius],
        outline=white,
        width=line_width,
    )

    # Vertical ellipse (meridian)
    meridian_rx = radius * 0.45
    draw.ellipse(
        [cx - meridian_rx, cy - radius, cx + meridian_rx, cy + radius],
        outline=white,
        width=line_width,
    )

    # Horizontal line (equator)
    draw.line(
        [cx - radius, cy, cx + radius, cy],
        fill=white,
        width=line_width,
    )

    # Upper latitude line (curved)
    lat_y = cy - radius * 0.45
    lat_rx = math.sqrt(max(0, radius**2 - (lat_y - cy) ** 2))
    arc_bbox = [cx - lat_rx, lat_y - radius * 0.12, cx + lat_rx, lat_y + radius * 0.12]
    draw.arc(arc_bbox, 0, 180, fill=white, width=line_width)

    # Lower latitude line (curved)
    lat_y = cy + radius * 0.45
    lat_rx = math.sqrt(max(0, radius**2 - (lat_y - cy) ** 2))
    arc_bbox = [cx - lat_rx, lat_y - radius * 0.12, cx + lat_rx, lat_y + radius * 0.12]
    draw.arc(arc_bbox, 180, 360, fill=white, width=line_width)

    # Small "A" and Japanese character below the globe to hint at translation
    if size >= 80:
        font_size_char = max(10, int(size * 0.13))
        # Try to get a font
        try:
            font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size_char)
        except (OSError, IOError):
            try:
                font = ImageFont.truetype(
                    "/System/Library/Fonts/SFNSText.ttf", font_size_char
                )
            except (OSError, IOError):
                font = ImageFont.load_default()

        # Draw "A" on the left side below globe
        a_x = cx - radius * 0.55
        a_y = cy + radius + size * 0.04
        draw.text((a_x, a_y), "A", fill=white, font=font, anchor="mt")

        # Draw "文" on the right side below globe
        try:
            jp_font = ImageFont.truetype(
                "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc", font_size_char
            )
        except (OSError, IOError):
            try:
                jp_font = ImageFont.truetype(
                    "/System/Library/Fonts/Hiragino Sans GB.ttc", font_size_char
                )
            except (OSError, IOError):
                jp_font = font

        b_x = cx + radius * 0.55
        draw.text((b_x, a_y), "文", fill=white, font=jp_font, anchor="mt")

    # Convert to RGB (no alpha for iOS icons)
    rgb_img = Image.new("RGB", (size, size))
    rgb_img.paste(img, mask=img.split()[3])
    return rgb_img


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    for s in SIZES:
        icon = draw_icon(s)
        filename = f"icon_{s}x{s}.png"
        filepath = os.path.join(OUTPUT_DIR, filename)
        icon.save(filepath, "PNG")
        print(f"Generated {filepath}")

    # Write Contents.json
    import json

    contents = {
        "images": [
            # iPhone Notification @2x
            {"size": "20x20", "idiom": "iphone", "filename": "icon_40x40.png", "scale": "2x"},
            # iPhone Notification @3x
            {"size": "20x20", "idiom": "iphone", "filename": "icon_60x60.png", "scale": "3x"},
            # iPhone Settings @2x
            {"size": "29x29", "idiom": "iphone", "filename": "icon_58x58.png", "scale": "2x"},
            # iPhone Settings @3x
            {"size": "29x29", "idiom": "iphone", "filename": "icon_87x87.png", "scale": "3x"},
            # iPhone Spotlight @2x
            {"size": "40x40", "idiom": "iphone", "filename": "icon_80x80.png", "scale": "2x"},
            # iPhone Spotlight @3x
            {"size": "40x40", "idiom": "iphone", "filename": "icon_120x120.png", "scale": "3x"},
            # iPhone App @2x
            {"size": "60x60", "idiom": "iphone", "filename": "icon_120x120.png", "scale": "2x"},
            # iPhone App @3x
            {"size": "60x60", "idiom": "iphone", "filename": "icon_180x180.png", "scale": "3x"},
            # iPad Notification @1x
            {"size": "20x20", "idiom": "ipad", "filename": "icon_40x40.png", "scale": "2x"},
            # iPad Settings @1x (29pt)
            {"size": "29x29", "idiom": "ipad", "filename": "icon_58x58.png", "scale": "2x"},
            # iPad Spotlight @1x
            {"size": "40x40", "idiom": "ipad", "filename": "icon_40x40.png", "scale": "1x"},
            # iPad Spotlight @2x
            {"size": "40x40", "idiom": "ipad", "filename": "icon_80x80.png", "scale": "2x"},
            # iPad App @1x
            {"size": "76x76", "idiom": "ipad", "filename": "icon_76x76.png", "scale": "1x"},
            # iPad App @2x
            {"size": "76x76", "idiom": "ipad", "filename": "icon_152x152.png", "scale": "2x"},
            # iPad Pro App @2x
            {"size": "83.5x83.5", "idiom": "ipad", "filename": "icon_167x167.png", "scale": "2x"},
            # App Store
            {"size": "1024x1024", "idiom": "ios-marketing", "filename": "icon_1024x1024.png", "scale": "1x"},
        ],
        "info": {"version": 1, "author": "xcode"},
    }

    contents_path = os.path.join(OUTPUT_DIR, "Contents.json")
    with open(contents_path, "w") as f:
        json.dump(contents, f, indent=2)
    print(f"\nWrote {contents_path}")


if __name__ == "__main__":
    main()
