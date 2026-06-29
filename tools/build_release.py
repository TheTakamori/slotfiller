from __future__ import annotations

from pathlib import Path
import shutil
import tempfile
import zipfile


ADDON_ROOT = Path(__file__).resolve().parents[1]
ADDON_NAME = "SlotFiller"
TOC_NAME = f"{ADDON_NAME}.toc"
OUTPUT_DIR = ADDON_ROOT.parents[1]

# Files that exist in the source tree for development but must be stripped
# from the release zip and removed from the .toc load list.
DEV_ONLY_PATHS = (
    Path("UI/CopyFrame.lua"),
    Path("UI/DevCommands.lua"),
)

# Top-level names to exclude from the release zip entirely.
IGNORE_NAMES = {
    ".git",
    ".gitignore",
    "CURSEFORGE_SUBMISSION.md",
    "tests",
    "__pycache__",
    "tools",
    "build",
    "dist",
    "release",
}

# Icon sizes kept in the release (used by the game engine).
RELEASE_ICON_NAMES = {"slotfiller-64.png"}


def read_version() -> str:
    toc_path = ADDON_ROOT / TOC_NAME
    for line in toc_path.read_text().splitlines():
        prefix = "## Version:"
        if line.startswith(prefix):
            return line.split(":", 1)[1].strip()
    raise RuntimeError(f"Unable to find version in {toc_path}")


def ignore_filter(_directory: str, names: list[str]) -> set[str]:
    ignored = set()
    for name in names:
        if name in IGNORE_NAMES:
            ignored.add(name)
        elif name.endswith(".pyc") or name.endswith(".pyo") or name.endswith(".zip"):
            ignored.add(name)
    return ignored


def strip_dev_only_files(staging_root: Path) -> None:
    """Remove dev-only Lua files from the staging tree and from the .toc."""
    toc_path = staging_root / TOC_NAME
    toc_exclusions = set()

    for relative_path in DEV_ONLY_PATHS:
        staged_path = staging_root / relative_path
        if staged_path.exists():
            staged_path.unlink()
        toc_exclusions.add(str(relative_path).replace("\\", "/"))

    lines = toc_path.read_text().splitlines()
    filtered = [line for line in lines if line.strip() not in toc_exclusions]
    toc_path.write_text("\n".join(filtered) + "\n")


def strip_source_icons(staging_root: Path) -> None:
    """Keep only the icon size(s) the game engine actually loads."""
    icons_dir = staging_root / "Media" / "Icons"
    if not icons_dir.exists():
        return
    for path in icons_dir.iterdir():
        if path.is_file() and path.name not in RELEASE_ICON_NAMES:
            path.unlink()


def build_release_zip() -> Path:
    version = read_version()
    output_path = OUTPUT_DIR / f"{ADDON_NAME}-{version}.zip"

    with tempfile.TemporaryDirectory() as temp_dir:
        staging_parent = Path(temp_dir)
        staging_root = staging_parent / ADDON_NAME
        shutil.copytree(ADDON_ROOT, staging_root, ignore=ignore_filter)
        strip_dev_only_files(staging_root)
        strip_source_icons(staging_root)

        with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(staging_root.rglob("*")):
                archive.write(path, path.relative_to(staging_parent))

    return output_path


def main() -> None:
    output_path = build_release_zip()
    print(output_path)


if __name__ == "__main__":
    main()
