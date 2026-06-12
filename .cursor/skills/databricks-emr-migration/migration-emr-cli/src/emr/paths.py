from __future__ import annotations

from pathlib import Path


def package_root() -> Path:
    """Directory that contains ``config/`` (and usually ``samples/``).

    - **Wheel / PEX:** ``config`` is bundled as ``emr/config`` next to this module.
    - **Editable checkout:** ``packages/emr-cli`` (``src/emr/paths.py`` → ``parents[1]``).
    """
    pkg_dir = Path(__file__).resolve().parent
    if (pkg_dir / "config").is_dir():
        return pkg_dir
    checkout_root = pkg_dir.parents[1]
    if (checkout_root / "config").is_dir():
        return checkout_root
    return checkout_root
