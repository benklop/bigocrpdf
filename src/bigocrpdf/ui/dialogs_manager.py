"""
BigOcrPdf - Dialogs Manager Module

This module handles all dialog creation and management for the application.
"""

import logging
import threading
from collections.abc import Callable
from typing import TYPE_CHECKING

import gi

gi.require_version("Adw", "1")
gi.require_version("Gtk", "4.0")
from gi.repository import Adw, GLib, Gtk

from bigocrpdf.ui.file_save_mixin import FileSaveDialogMixin
from bigocrpdf.ui.pdf_options_callbacks_mixin import PDFOptionsCallbacksMixin
from bigocrpdf.ui.pdf_options_ui_mixin import PDFOptionsUICreationMixin
from bigocrpdf.ui.text_viewer_mixin import TextViewerDialogMixin
from bigocrpdf.utils.i18n import _

if TYPE_CHECKING:
    from bigocrpdf.services.settings import OcrSettings
    from bigocrpdf.window import BigOcrPdfWindow

logger = logging.getLogger(__name__)


class DialogsManager(
    PDFOptionsUICreationMixin,
    PDFOptionsCallbacksMixin,
    TextViewerDialogMixin,
    FileSaveDialogMixin,
):
    """Manages all dialogs and modal windows for the application"""

    def __init__(self, window: "BigOcrPdfWindow"):
        """Initialize the dialogs manager

        Args:
            window: Reference to the main application window
        """
        self.window = window
        self._image_import_in_progress = False

    # ── Image merge dialog ──────────────────────────────────────────────

    def show_image_merge_dialog(
        self,
        image_files: list[str],
        settings: "OcrSettings",
        *,
        heading: str,
        body: str,
        on_complete: Callable[[], None] | None = None,
    ) -> None:
        """Show dialog asking whether to merge images into one PDF or keep separate.

        Args:
            image_files: Paths to the image files.
            settings: OcrSettings instance for tracking file origins.
            heading: Dialog heading text.
            body: Dialog body text.
            on_complete: Optional callback invoked after files are added.
        """
        dialog = Adw.AlertDialog()
        dialog.set_heading(heading)
        dialog.set_body(body)
        dialog.add_response("separate", _("Separate PDFs"))
        dialog.add_response("merge", _("Merge into One PDF"))
        dialog.set_response_appearance("merge", Adw.ResponseAppearance.SUGGESTED)
        dialog.set_default_response("merge")

        def on_response(_dialog: Adw.AlertDialog, response: str) -> None:
            if response == "merge":
                self.convert_images_for_import(
                    image_files,
                    settings,
                    merge=True,
                    success_toast=_("Merged {} images into one PDF").format(len(image_files)),
                    error_toast=_("Error merging images"),
                    on_complete=on_complete,
                )
            elif response == "separate":
                self.convert_images_for_import(
                    image_files,
                    settings,
                    merge=False,
                    error_toast=_("Error converting images"),
                    on_complete=on_complete,
                )

        dialog.connect("response", on_response)
        dialog.present(self.window)

    def convert_images_for_import(
        self,
        image_files: list[str],
        settings: "OcrSettings",
        *,
        merge: bool,
        on_complete: Callable[[], None] | None = None,
        success_toast: str | None = None,
        error_toast: str | None = None,
    ) -> None:
        """Convert image files to PDF in a background thread with progress UI."""
        if not image_files:
            if on_complete:
                on_complete()
            return

        if self._image_import_in_progress:
            self.window.show_toast(_("Image conversion is already running"))
            return

        from bigocrpdf.utils.pdf_utils import images_to_pdf

        progress_dialog, status_label, progress_bar = self._create_import_progress_dialog(
            total=len(image_files)
        )
        self._image_import_in_progress = True

        converted_files: list[tuple[str, str]] = []
        errors: list[str] = []

        def update_progress(current: int, total: int, message: str) -> bool:
            if total > 0:
                fraction = max(0.0, min(1.0, current / total))
                progress_bar.set_fraction(fraction)
                progress_bar.set_text(f"{int(fraction * 100)}%")
            status_label.set_text(message)
            return False

        def finish() -> bool:
            progress_dialog.force_close()
            self._image_import_in_progress = False

            for pdf_path, original_path in converted_files:
                settings.original_file_paths[pdf_path] = original_path

            if converted_files:
                settings.add_files([pdf_path for pdf_path, _ in converted_files])

            if errors:
                for msg in errors:
                    logger.error(msg)
                self.window.show_toast(error_toast or _("Some images could not be converted"))
            elif success_toast:
                self.window.show_toast(success_toast)

            if on_complete:
                on_complete()
            return False

        def worker() -> None:
            total_images = len(image_files)
            GLib.idle_add(
                update_progress,
                0,
                total_images,
                _("Converting {count} image(s)...").format(count=total_images),
            )

            if merge:

                def merge_progress(current: int, total: int, _message: str) -> None:
                    GLib.idle_add(
                        update_progress,
                        current,
                        max(1, total_images),
                        _("Preparing merged PDF ({current}/{total})").format(
                            current=min(current, total_images),
                            total=total_images,
                        ),
                    )

                try:
                    pdf_path = images_to_pdf(image_files, progress_callback=merge_progress)
                    converted_files.append((pdf_path, image_files[0]))
                    GLib.idle_add(
                        update_progress,
                        total_images,
                        total_images,
                        _("Merge complete"),
                    )
                except (OSError, ValueError, RuntimeError) as e:
                    errors.append(f"Failed to merge images: {e}")
            else:
                for index, img_path in enumerate(image_files, start=1):
                    GLib.idle_add(
                        update_progress,
                        index - 1,
                        total_images,
                        _("Converting image {current}/{total}...").format(
                            current=index,
                            total=total_images,
                        ),
                    )
                    try:
                        pdf_path = images_to_pdf([img_path])
                        converted_files.append((pdf_path, img_path))
                    except (OSError, ValueError, RuntimeError) as e:
                        errors.append(f"Failed to convert image to PDF ({img_path}): {e}")

                    GLib.idle_add(
                        update_progress,
                        index,
                        total_images,
                        _("Converted image {current}/{total}").format(
                            current=index,
                            total=total_images,
                        ),
                    )

            GLib.idle_add(finish)

        threading.Thread(target=worker, daemon=True).start()

    def _create_import_progress_dialog(
        self, total: int
    ) -> tuple[Adw.Dialog, Gtk.Label, Gtk.ProgressBar]:
        """Create and present a modal progress dialog for image conversion."""
        dialog = Adw.Dialog()
        dialog.set_title(_("Converting Images"))
        dialog.set_content_width(360)
        dialog.set_can_close(False)

        toolbar_view = Adw.ToolbarView()
        header = Adw.HeaderBar()
        header.set_show_start_title_buttons(False)
        header.set_show_end_title_buttons(False)
        toolbar_view.add_top_bar(header)

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content.set_margin_start(24)
        content.set_margin_end(24)
        content.set_margin_top(24)
        content.set_margin_bottom(24)

        status_label = Gtk.Label(
            label=_("Converting {count} image(s)...").format(count=total)
        )
        status_label.set_halign(Gtk.Align.START)
        status_label.set_wrap(True)

        progress_bar = Gtk.ProgressBar()
        progress_bar.set_show_text(True)
        progress_bar.set_text("0%")
        progress_bar.set_fraction(0.0)

        content.append(status_label)
        content.append(progress_bar)
        toolbar_view.set_content(content)
        dialog.set_child(toolbar_view)
        dialog.present(self.window)

        return dialog, status_label, progress_bar
