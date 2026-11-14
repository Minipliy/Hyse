#!/usr/bin/env python3
"""Extract exact blue anatomy overlays from the supplied reference screens.

The screenshots are the visual source of truth.  Their blue pixels are
registered back onto the original 1536 × 1024 anatomy atlas so SwiftUI can
compose the same fibre-level illustrations without re-drawing muscle shapes.
"""

from __future__ import annotations

import json
from collections import deque
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "CalorieTrackerApp" / "Assets.xcassets"
DOWNLOADS = Path("/Users/lukashammer/Downloads")

# All reference sheets render the same anatomy canvas at this scale and x
# origin. The y origin varies with the bottom-sheet height in each screen.
REFERENCE_SCALE = 0.613
REFERENCE_X = 188
CANVAS = (round(1536 * REFERENCE_SCALE), round(1024 * REFERENCE_SCALE))
REFERENCE_Y: dict[str, tuple[int, int]] = {
    "Biceps": (8349, 1181),
    "Core": (8350, 1180),
    "BenchPress": (8351, 1041),
    "PullUp": (8352, 1508),
    "Neck": (8353, 1233),
    "Row": (8354, 1477),
    "FacePull": (8355, 1247),
    "Traps": (8356, 1558),
    "Triceps": (8357, 1285),
    "Forearms": (8358, 1245),
    "LowerBack": (8359, 1592),
    "Abductors": (8360, 1514),
    "Adductors": (8361, 1635),
    "Hamstrings": (8362, 1198),
    "BirdDog": (8363, 1432),
    "Quadriceps": (8364, 1220),
    "Calves": (8365, 1363),
}


def blue_pixels(reference: Image.Image) -> Image.Image:
    """Retain only the Hyse blue anatomy pixels, preserving screenshot colour."""
    rgb = reference.convert("RGB")
    output = Image.new("RGBA", rgb.size)
    source = rgb.load()
    target = output.load()
    for y in range(rgb.height):
        for x in range(rgb.width):
            red, green, blue = source[x, y]
            # This isolates the accent's blue hue from the neutral white/grey
            # anatomy and the dark sheet background.
            # Neutral anatomy shading is slightly blue-grey too. It must stay
            # transparent: otherwise one reference layer can paint grey over
            # the actual blue fibres of another layer. The accent has a clear
            # blue-over-green and green-over-red separation.
            chroma = max(red, green, blue) - min(red, green, blue)
            if blue >= 80 and blue - green >= 22 and green - red >= 17 and chroma >= 45:
                target[x, y] = (red, green, blue, 255)
    return output


def write_imageset(name: str, image: Image.Image) -> None:
    directory = ASSETS / f"TrainingReference{name}.imageset"
    directory.mkdir(parents=True, exist_ok=True)
    filename = f"TrainingReference{name}.png"
    image.save(directory / filename, compress_level=6)
    contents = {
        "images": [
            {"filename": filename, "idiom": "universal", "scale": "1x"},
            {"idiom": "universal", "scale": "2x"},
            {"idiom": "universal", "scale": "3x"},
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (directory / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def isolate_box(image: Image.Image, box: tuple[int, int, int, int]) -> Image.Image:
    """Keep one anatomically separate region on the original canvas."""
    result = Image.new("RGBA", image.size)
    region = image.crop(box)
    result.alpha_composite(region, dest=(box[0], box[1]))
    return result


def remove_connected_dark_background(image: Image.Image) -> Image.Image:
    """Make only the screenshot sheet behind the anatomy transparent.

    The supplied reference has a nearly-black bottom-sheet surface around the
    figures.  A normal colour-key would also erase their ink contours; instead
    flood from the outer border and remove solely the dark, low-chroma pixels
    connected to that edge.  Dark details enclosed by the anatomical artwork
    remain untouched.
    """
    result = image.convert("RGBA")
    pixels = result.load()
    width, height = result.size
    seen: set[tuple[int, int]] = set()
    queue: deque[tuple[int, int]] = deque()

    def is_sheet_background(x: int, y: int) -> bool:
        red, green, blue, alpha = pixels[x, y]
        return alpha > 0 and max(red, green, blue) <= 54 and max(red, green, blue) - min(red, green, blue) <= 12

    for x in range(width):
        queue.extend(((x, 0), (x, height - 1)))
    for y in range(1, height - 1):
        queue.extend(((0, y), (width - 1, y)))

    while queue:
        x, y = queue.popleft()
        if (x, y) in seen or not is_sheet_background(x, y):
            continue
        seen.add((x, y))
        red, green, blue, _ = pixels[x, y]
        pixels[x, y] = (red, green, blue, 0)
        for next_x, next_y in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= next_x < width and 0 <= next_y < height and (next_x, next_y) not in seen:
                queue.append((next_x, next_y))

    return result


def reference_crop(number: int, y_origin: int) -> Image.Image:
    source = Image.open(DOWNLOADS / f"IMG_{number}.PNG")
    return source.crop((REFERENCE_X, y_origin, REFERENCE_X + CANVAS[0], y_origin + CANVAS[1]))


def main() -> None:
    # IMG_8349 has only biceps active; IMG_8353 has only neck active. Swapping
    # their blue pixels produces the unmodified neutral atlas without having
    # to paint, redraw or infer any anatomy ourselves.
    biceps_reference = reference_crop(*REFERENCE_Y["Biceps"]).convert("RGBA")
    neck_reference = reference_crop(*REFERENCE_Y["Neck"]).convert("RGBA")
    biceps_alpha = blue_pixels(biceps_reference).getchannel("A")
    neutral = biceps_reference.copy()
    neutral.paste(neck_reference, mask=biceps_alpha)
    write_imageset("AnatomyNeutral", remove_connected_dark_background(neutral))

    for name, (number, y_origin) in REFERENCE_Y.items():
        overlay = blue_pixels(reference_crop(number, y_origin))
        write_imageset(name, overlay)
        print(f"extracted {name} from IMG_{number}.PNG")

    # Face Pull is the supplied high-detail shoulder reference. Split it by
    # view, so posterior delts never tint the front figure and anterior/lateral
    # delts never tint the rear figure. The boxes contain only the respective
    # shoulder fibre components, not the arms.
    shoulder_reference = blue_pixels(reference_crop(*REFERENCE_Y["FacePull"]))
    write_imageset("FrontShoulders", isolate_box(shoulder_reference, (180, 100, 445, 212)))
    write_imageset("RearShoulders", isolate_box(shoulder_reference, (515, 100, 745, 162)))
    print("extracted separate front and rear shoulder references")

    # The Pull Up and Row captures each include lighter assistance highlights
    # in the neighbouring back region. Export their actual targets separately
    # so a lat pulldown cannot wash out the dark upper-back fibres of a Kelso
    # shrug or seated row (and vice versa).
    pull_up_reference = blue_pixels(reference_crop(*REFERENCE_Y["PullUp"]))
    row_reference = blue_pixels(reference_crop(*REFERENCE_Y["Row"]))
    # The adjoining boxes meet at y=165 but never overlap. This keeps a
    # dark upper-back target from replacing the latissimus (or the reverse).
    write_imageset("Lats", isolate_box(pull_up_reference, (535, 165, 715, 285)))
    write_imageset("UpperBack", isolate_box(row_reference, (520, 65, 745, 165)))
    print("extracted separate latissimus and upper-back references")

    # Keep the primary-only contract all the way through to the pixels. These
    # source captures show assistance muscles too, but chest, glutes and
    # hamstrings each need a layer containing only their own fibre region.
    bench_reference = blue_pixels(reference_crop(*REFERENCE_Y["BenchPress"]))
    bird_dog_reference = blue_pixels(reference_crop(*REFERENCE_Y["BirdDog"]))
    hamstring_reference = blue_pixels(reference_crop(*REFERENCE_Y["Hamstrings"]))
    write_imageset("Chest", isolate_box(bench_reference, (245, 110, 380, 185)))
    write_imageset("Glutes", isolate_box(bird_dog_reference, (550, 255, 710, 340)))
    write_imageset("Hamstrings", isolate_box(hamstring_reference, (540, 330, 720, 430)))
    print("extracted primary-only chest, glute and hamstring references")


if __name__ == "__main__":
    main()
