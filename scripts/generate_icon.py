"""Generate macOS app icon for Sitempo."""
from PIL import Image, ImageDraw

SIZE = 1024
CENTER = SIZE // 2
RADIUS = SIZE * 0.34


def generate_icon():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Rounded rect background - dark
    bg_rect = [SIZE * 0.06, SIZE * 0.06, SIZE * 0.94, SIZE * 0.94]
    corner = SIZE * 0.22
    draw.rounded_rectangle(bg_rect, radius=corner, fill=(26, 26, 46, 255))

    # Timer ring background
    ring_bbox = [
        CENTER - RADIUS, CENTER - RADIUS,
        CENTER + RADIUS, CENTER + RADIUS,
    ]
    ring_width = int(SIZE * 0.04)
    draw.ellipse(ring_bbox, outline=(255, 255, 255, 25), width=ring_width)

    # Blue arc (sitting - 70%)
    draw.arc(ring_bbox, -90, 162, fill=(108, 155, 255, 255), width=ring_width)

    # Orange arc (standing - 20%)
    draw.arc(ring_bbox, 166, 238, fill=(255, 140, 66, 255), width=ring_width)

    # Green arc (movement - 10%)
    draw.arc(ring_bbox, 242, 266, fill=(102, 187, 106, 255), width=ring_width)

    # Standing person figure in center
    fig_scale = SIZE * 0.001

    # Head
    head_r = 38 * fig_scale
    head_y = CENTER - 95 * fig_scale
    draw.ellipse(
        [CENTER - head_r, head_y - head_r, CENTER + head_r, head_y + head_r],
        fill=(255, 255, 255, 230),
    )

    # Body
    body_w = 18 * fig_scale
    body_top = head_y + head_r + 12 * fig_scale
    body_bottom = CENTER + 55 * fig_scale
    draw.rounded_rectangle(
        [CENTER - body_w, body_top, CENTER + body_w, body_bottom],
        radius=body_w,
        fill=(255, 255, 255, 230),
    )

    # Arms raised slightly
    arm_w = int(18 * fig_scale)
    arm_y = body_top + 25 * fig_scale
    arm_len = 70 * fig_scale
    draw.line(
        [(CENTER, arm_y), (CENTER - arm_len, arm_y - 25 * fig_scale)],
        fill=(255, 255, 255, 210), width=arm_w,
    )
    draw.line(
        [(CENTER, arm_y), (CENTER + arm_len, arm_y - 25 * fig_scale)],
        fill=(255, 255, 255, 210), width=arm_w,
    )

    # Legs
    leg_w = int(18 * fig_scale)
    leg_len = 90 * fig_scale
    draw.line(
        [(CENTER, body_bottom), (CENTER - 42 * fig_scale, body_bottom + leg_len)],
        fill=(255, 255, 255, 210), width=leg_w,
    )
    draw.line(
        [(CENTER, body_bottom), (CENTER + 42 * fig_scale, body_bottom + leg_len)],
        fill=(255, 255, 255, 210), width=leg_w,
    )

    return img


def main():
    icon = generate_icon()
    base = "/Users/josed/development/Code/sitempo/macos/Runner/Assets.xcassets/AppIcon.appiconset"

    sizes = [16, 32, 64, 128, 256, 512, 1024]
    for s in sizes:
        resized = icon.resize((s, s), Image.LANCZOS)
        resized.save(f"{base}/app_icon_{s}.png")
        print(f"  Generated {s}x{s}")

    print("Done!")


if __name__ == "__main__":
    main()
