"""Loads the tars skill's SKILL.md verbatim as the harness system prompt.

Tars's progressive-disclosure design already instructs the model to Read
docs/*.md on demand via its own tool contract — the eval harness must not
pre-inline those docs, since that would test a different (easier) prompt
than the one tars actually ships.
"""

from pathlib import Path


def load_system_prompt(skill_dir: Path) -> str:
    """Return the verbatim contents of `skill_dir`/SKILL.md.

    Raises:
        FileNotFoundError: if SKILL.md does not exist under skill_dir.
    """
    skill_md = Path(skill_dir) / "SKILL.md"
    if not skill_md.is_file():
        raise FileNotFoundError(f"SKILL.md not found under {skill_dir!s}")
    return skill_md.read_text()
