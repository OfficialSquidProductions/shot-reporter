"""Fail closed when a report-only build contains a retired runtime payload."""
from pathlib import Path, PurePosixPath

# These are rejection signatures, never bundled dependencies or migration targets.
RETIRED_COMPONENTS = frozenset({
    'desktopmedia', 'desktopcodecs', 'media-worker',
    'ffmpeg', 'ffmpeg.exe', 'ffprobe', 'ffprobe.exe',
    'redline', 'redline.exe', 'shot-reporter-braw',
    'blackmagicrawapi.framework', 'blackmagicrawapi.dll',
})


def reject_retired_resource(relative):
    parts = PurePosixPath(str(relative).replace('\\', '/')).parts
    if any(part.casefold() in RETIRED_COMPONENTS or part.casefold().startswith('media-worker-') for part in parts):
        raise ValueError('Retired runtime resource in report-only application: ' + str(relative))


def validate_report_bundle(app):
    """Inspect only. Never remove or rewrite a supplied application."""
    app = Path(app)
    for entry in app.rglob('*'):
        reject_retired_resource(entry.relative_to(app).as_posix())
