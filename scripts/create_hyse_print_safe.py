from pathlib import Path

from PIL import Image
from reportlab.lib.pagesizes import A5
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "output" / "png" / "hyse-gym-flyer-a5-red-white-no-qr.png"
PNG = ROOT / "output" / "png" / "hyse-gym-flyer-a5-red-white-print-safe-300dpi.png"
PDF = ROOT / "output" / "pdf" / "hyse-gym-flyer-a5-red-white-print-safe.pdf"
PNG.parent.mkdir(parents=True, exist_ok=True)
PDF.parent.mkdir(parents=True, exist_ok=True)

# Re-encode and normalize to a true A5 raster at 300 dpi, dropping source metadata.
target = Image.open(SOURCE).convert("RGB").resize((1748, 2480), Image.Resampling.LANCZOS)
target.save(PNG, format="PNG", dpi=(300, 300), optimize=True)

W, H = A5
c = canvas.Canvas(str(PDF), pagesize=A5, pageCompression=1)
c.setTitle("Hyse - Print Safe Gym Flyer")
c.setAuthor("Hyse")
c.drawImage(ImageReader(str(PNG)), 0, 0, width=W, height=H, preserveAspectRatio=False, mask="auto")
c.showPage()
c.save()
print(PDF)
