"""Tests for images_to_pdf progress callback behavior."""

from pathlib import Path

from PIL import Image

from bigocrpdf.utils.pdf_utils import images_to_pdf


def _create_test_image(path: Path, color: tuple[int, int, int]) -> None:
    image = Image.new("RGB", (32, 32), color)
    image.save(path)


def test_images_to_pdf_reports_progress(tmp_path: Path) -> None:
    img1 = tmp_path / "img1.png"
    img2 = tmp_path / "img2.png"
    out_pdf = tmp_path / "merged.pdf"
    _create_test_image(img1, (255, 0, 0))
    _create_test_image(img2, (0, 255, 0))

    updates: list[tuple[int, int, str]] = []

    def on_progress(current: int, total: int, message: str) -> None:
        updates.append((current, total, message))

    result = images_to_pdf([str(img1), str(img2)], output_path=str(out_pdf), progress_callback=on_progress)

    assert result == str(out_pdf)
    assert out_pdf.exists()
    assert updates
    assert updates[-1][0] == updates[-1][1]
    assert updates[-1][2] == "PDF created"
    assert any("Loaded image" in msg for _, _, msg in updates)
