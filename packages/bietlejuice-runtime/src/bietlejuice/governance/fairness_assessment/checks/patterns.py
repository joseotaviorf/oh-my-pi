"""Shared regexes for findable / accessibility checks."""

import re

EMAIL_RE = re.compile(
    r"^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$",
)
IDENTIFIER_RE = re.compile(r"^[a-zA-Z0-9_][a-zA-Z0-9_]*$")
