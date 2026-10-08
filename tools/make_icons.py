"""Иконки «Шлюпки спасения»: спасательный круг (вариант А).

Рисует значок программы, значки трея и логотип для приложения из одного описания,
чтобы все размеры совпадали. Нужен Pillow: python -m pip install pillow

    python tools/make_icons.py

Пишет:
  windows/runner/resources/app_icon.ico      значок программы и установщика (16–256)
  assets/images/tray_icon*.{png,ico}         трей: обычный, тёмная тема, подключено, отключено
  assets/images/logo.svg                     логотип внутри приложения (одноцветный силуэт:
                                             кнопка подключения перекрашивает его целиком)
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent

NAVY = (12, 68, 124, 255)  # #0C447C
RED = (226, 75, 74, 255)  # #E24B4A
WHITE = (255, 255, 255, 255)
GRAY = (136, 135, 128, 255)  # #888780
LIGHT_GRAY = (211, 209, 199, 255)  # #D3D1C7
GREEN = (99, 153, 34, 255)  # #639922

# Геометрия в долях от стороны: кольцо r 84/256..44/256, как в выбранном варианте.
OUTER = 84 / 256
INNER = 44 / 256
# Полосы по 45° с 12, 3, 6 и 9 часов (углы Pillow: от 3 часов по часовой стрелке).
BANDS = [(-90, -45), (0, 45), (90, 135), (180, 225)]

SS = 4  # рисуем крупнее и уменьшаем: гладкие края без отдельного сглаживания


def circle_box(c, r):
    return (c - r, c - r, c + r, c + r)


def lifebuoy(size, *, ring=WHITE, band=RED, background=None, outline=None, dot=None, scale=1.0):
    """Спасательный круг на прозрачном фоне или на скруглённом квадрате."""
    n = size * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = n / 2
    outer = n * OUTER * scale
    inner = n * INNER * scale
    if background:
        d.rounded_rectangle((0, 0, n - 1, n - 1), radius=n * 56 / 256, fill=background)
    if outline:
        w = max(SS, n * 0.035)
        d.ellipse(circle_box(c, outer + w), fill=outline)
    d.ellipse(circle_box(c, outer), fill=ring)
    for a, b in BANDS:
        d.pieslice(circle_box(c, outer), a, b, fill=band)
    if outline:
        w = max(SS, n * 0.035)
        d.ellipse(circle_box(c, inner + w), fill=outline)
    # Дырка: цвет фона или прозрачность.
    hole = background or (0, 0, 0, 0)
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).ellipse(circle_box(c, inner), fill=255)
    img.paste(Image.new("RGBA", (n, n), hole), (0, 0), mask)
    if dot:
        ImageDraw.Draw(img).ellipse(circle_box(c, inner * 0.55), fill=dot)
    return img.resize((size, size), Image.LANCZOS)


def save_ico(path, draw, sizes):
    images = [draw(s) for s in sizes]
    images[-1].save(path, format="ICO", sizes=[(s, s) for s in sizes], append_images=images[:-1])


def main():
    app_sizes = [16, 24, 32, 48, 64, 128, 256]
    save_ico(
        ROOT / "windows/runner/resources/app_icon.ico",
        lambda s: lifebuoy(s, background=NAVY),
        app_sizes,
    )

    tray_sizes = [16, 20, 24, 32, 48, 64]
    # Контур тёмно-синий: белое кольцо не теряется на светлой панели задач.
    trays = {
        "tray_icon": dict(outline=NAVY, scale=1.35),
        "tray_icon_dark": dict(outline=NAVY, scale=1.35),
        "tray_icon_connected": dict(outline=NAVY, dot=GREEN, scale=1.35),
        "tray_icon_disconnected": dict(ring=LIGHT_GRAY, band=GRAY, outline=GRAY, scale=1.35),
    }
    for name, opts in trays.items():
        save_ico(ROOT / f"assets/images/{name}.ico", lambda s, o=opts: lifebuoy(s, **o), tray_sizes)
        lifebuoy(64, **opts).save(ROOT / f"assets/images/{name}.png")

    # Логотип: куски кольца, см. logo_svg().
    (ROOT / "assets/images/logo.svg").write_text(logo_svg(), encoding="utf-8")


def arc_segment(a0, a1, r_out=108, r_in=56, c=128):
    """Кусок кольца от угла a0 до a1 (градусы от 12 часов по часовой стрелке) как путь SVG."""
    import math

    def pt(r, a):
        t = math.radians(a - 90)
        return f"{c + r * math.cos(t):.2f} {c + r * math.sin(t):.2f}"

    large = 1 if a1 - a0 > 180 else 0
    return (
        f"M{pt(r_out, a0)} A{r_out} {r_out} 0 {large} 1 {pt(r_out, a1)} "
        f"L{pt(r_in, a1)} A{r_in} {r_in} 0 {large} 0 {pt(r_in, a0)} Z"
    )


def logo_svg():
    """Восемь кусков кольца с зазорами: красные полосы и синие промежутки.
    Кнопка подключения красит логотип одним цветом (srcIn), зазоры при этом остаются,
    и круг всё равно читается как спасательный."""
    gap = 3
    red, navy = [], []
    for i in range(8):
        a0 = i * 45 + gap
        a1 = (i + 1) * 45 - gap
        (red if i % 2 == 0 else navy).append(arc_segment(a0, a1))
    lines = [
        '<svg width="64" height="64" viewBox="0 0 256 256" xmlns="http://www.w3.org/2000/svg">',
        f'<path fill="#E24B4A" d="{" ".join(red)}"/>',
        f'<path fill="#0C447C" d="{" ".join(navy)}"/>',
        "</svg>",
    ]
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    main()
