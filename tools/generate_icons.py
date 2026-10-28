"""从项目书本与播放标识生成原生平台图标。运行前安装 Pillow。"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
BACKGROUND = '#C96442'
SIZE = 1024


def point(x, y):
    return ((54 + (x - 54) * 1.25) * SIZE / 108,
            (54 + (y - 54) * 1.25) * SIZE / 108)


def curve(start, control_a, control_b, end):
    return [point(*(
        (1 - t) ** 3 * start[axis]
        + 3 * (1 - t) ** 2 * t * control_a[axis]
        + 3 * (1 - t) * t ** 2 * control_b[axis]
        + t ** 3 * end[axis] for axis in (0, 1)))
        for t in (step / 64 for step in range(65))]


icon = Image.new('RGB', (SIZE, SIZE), BACKGROUND)
draw = ImageDraw.Draw(icon)
# 横幅中的白色圆角卡片、棕色书本和白色播放标记。
draw.rounded_rectangle((SIZE * .13, SIZE * .13, SIZE * .87, SIZE * .87),
                       radius=SIZE * .17, fill='#FAF9F6')
for edge, inner, control_a, control_b in ((30, 53, 38, 46), (78, 55, 70, 62)):
    points = curve((edge, 38), (control_a, 35), (control_b, 35), (inner, 40))
    points += curve((inner, 72), (control_b, 67), (control_a, 67), (edge, 70))
    draw.polygon(points, fill=BACKGROUND)
draw.polygon([point(61, 47), point(71, 54), point(61, 61)], fill='#FAF9F6')


def save(path, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    icon.resize((size, size), Image.Resampling.LANCZOS).save(path)


save(ROOT / 'assets/branding/app_icon.png', SIZE)
for density, size in (('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)):
    save(ROOT / f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', size)
icon.save(ROOT / 'windows/runner/resources/app_icon.ico',
          sizes=[(size, size) for size in (16, 24, 32, 48, 64, 128, 256)])
# 单色资源只保留书本轮廓，播放符号镂空；不能把彩色卡片当作 alpha 蒙版。
mono = '''<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#FFFFFFFF" android:fillType="evenOdd"
        android:pathData="M30,38 C38,35 46,35 53,40 L53,72 C46,67 38,67 30,70 Z M78,38 C70,35 62,35 55,40 L55,72 C62,67 70,67 78,70 Z M61,47 L71,54 L61,61 Z"/>
</vector>
'''
(ROOT / 'android/app/src/main/res/drawable/ic_launcher_mono.xml').write_text(
    mono, encoding='utf-8', newline='\n')
print('原生平台图标已生成。')
