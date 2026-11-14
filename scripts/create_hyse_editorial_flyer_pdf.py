from pathlib import Path

from reportlab.lib.pagesizes import A5
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas


ROOT = Path(__file__).resolve().parents[1]
PNG = ROOT / "output" / "png" / "hyse-gym-flyer-a5-editorial.png"
PDF = ROOT / "output" / "pdf" / "hyse-gym-flyer-a5-editorial.pdf"
PDF.parent.mkdir(parents=True, exist_ok=True)

W, H = A5
c = canvas.Canvas(str(PDF), pagesize=A5)
c.setTitle("Hyse Gym Flyer - Editorial")
c.setAuthor("Hyse")
c.drawImage(ImageReader(str(PNG)), 0, 0, width=W, height=H, preserveAspectRatio=False, mask="auto")
c.showPage()
c.save()
print(PDF)
