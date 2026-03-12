"""Regression tests for GTK status markup escaping in terminal page."""

from bigocrpdf.ui.terminal_page import TerminalPageManager


class _DummyProgressState:
    def update_status(self, _text: str) -> bool:
        return True


class _DummyLabel:
    def __init__(self) -> None:
        self.last_markup: str | None = None
        self.last_text: str | None = None

    def set_markup(self, text: str) -> None:
        self.last_markup = text

    def set_text(self, text: str) -> None:
        self.last_text = text


class _DummyWindow:
    def announce_status(self, _text: str) -> None:
        return None


def _build_manager() -> TerminalPageManager:
    mgr = TerminalPageManager.__new__(TerminalPageManager)
    mgr.window = _DummyWindow()
    mgr._progress_state = _DummyProgressState()
    mgr.terminal_status_bar = _DummyLabel()
    mgr.stop_progress_monitor = lambda: None
    return mgr


def test_processing_status_escapes_pdf_filename_and_status() -> None:
    mgr = _build_manager()

    mgr._show_processing_status(
        {
            "filename": "Book & Manual <v2>.pdf",
            "file_number": 1,
            "total_files": 2,
            "status_message": "Processing page 3/10 & cleaning",
        },
        "1m 2s",
    )

    assert mgr.terminal_status_bar.last_markup is not None
    assert "Book &amp; Manual &lt;v2&gt;.pdf" in mgr.terminal_status_bar.last_markup
    assert "Processing page 3/10 &amp; cleaning" in mgr.terminal_status_bar.last_markup


def test_processing_status_escapes_image_filename_and_time() -> None:
    mgr = _build_manager()

    mgr._show_processing_status(
        {
            "filename": "Scan & Fix <draft>.tif",
            "file_number": 2,
            "total_files": 2,
            "status_message": "",
        },
        "2m & 3s",
    )

    assert mgr.terminal_status_bar.last_markup is not None
    assert "Scan &amp; Fix &lt;draft&gt;.tif" in mgr.terminal_status_bar.last_markup
    assert "2m &amp; 3s" in mgr.terminal_status_bar.last_markup


def test_completion_and_plain_status_paths_are_safe() -> None:
    mgr = _build_manager()

    mgr._show_completion_status(2, "5m & 0s")
    assert mgr.terminal_status_bar.last_markup is not None
    assert "5m &amp; 0s" in mgr.terminal_status_bar.last_markup

    mgr._show_simple_progress_status(1, 2, "3m & 1s")
    assert mgr.terminal_status_bar.last_text == "Processing files: 1/2 completed • Time: 3m & 1s"

    mgr._show_initial_status(2, "0m & 5s")
    assert mgr.terminal_status_bar.last_text == "Starting processing of 2 files... • Time: 0m & 5s"
