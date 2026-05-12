"""
String formatting helpers for datalake and DW pipelines.

``PROPER_NOUN_PARTICLES_LOWER`` lists conjunctions and articles kept lowercase in
title-style proper-noun phrases (person names, job titles, and similar labels) when
they are not the first word—covering Portuguese, Spanish, and common European / US
patterns.

The single-letter tokens ``a`` and ``o`` are included for Portuguese articles in
compound-name patterns. Trade-off: a standalone token ``A`` or ``O`` after the first
word is lowercased to ``a``/``o``; the first word is always title-cased, never forced
to particle-lowercase.
"""

import re
from typing import Optional

from unidecode import unidecode

PROPER_NOUN_PARTICLES_LOWER = frozenset(
    {
        # Portuguese (Brazil, Portugal)
        "de",
        "da",
        "do",
        "das",
        "dos",
        "e",
        "a",
        "o",
        "ao",
        # Spanish
        "del",
        "la",
        "las",
        "los",
        "el",
        "y",
        # Dutch / German / etc. (common in US & LatAm lineages)
        "van",
        "von",
        "zu",
        "und",
        "der",
        "den",
        "ten",
        "ter",
        "het",
        # Italian / French particles
        "di",
        "le",
        "du",
        "des",
    }
)


class StringFormatter:
    @classmethod
    def set_alphanumeric_snake_case(cls, str_value: str) -> str:
        """
        Returns the string in alphanumerical non-accentuated snake case format.
        e.g.: 0ne ínPut*StrInG => 0ne_inputstring
        """
        str_value = cls.remove_symbols(str_value)
        str_value = cls.set_snake_case(str_value)
        str_value = cls.replace_accents(str_value)
        return str_value

    @classmethod
    def normalize_string(cls, str_value: str) -> str:
        """
        Returns the string in lower case and non-accentuated format.
        e.g.: IndicaAí => indicaai
        """
        if str_value:
            str_value = cls.replace_accents(str_value)
            str_value = str_value.lower()
            return str_value

    @staticmethod
    def slugify(str_value: str) -> str:
        """
        Returns a slugified string (Normal Case => slug-case) string.
        """
        return str_value.replace("_", "-").lower()

    @staticmethod
    def remove_symbols(str_value: str) -> str:
        """
        Removes symbols like * " / returning only spaced alphanumeric charaters.
        """
        return re.sub(r"[^\w\s]", "", str_value)

    @staticmethod
    def set_snake_case(str_value: str) -> str:
        """
        Returns the string in snake case (NoRmal Case => snake_case) format.
        """
        return re.sub(r"\s+", "_", str_value).lower()

    @staticmethod
    def replace_accents(str_value: str) -> str:
        """
        Replaces an accented character by its respective non-accented character.
        """
        return unidecode(str_value)

    @staticmethod
    def format_proper_noun(str_value: Optional[str]) -> Optional[str]:
        """
        Normalizes proper-noun-style phrases for the clean layer: person names, job
        titles, and similar labels. Strips whitespace, transliterates to plain Latin
        letters (ASCII), applies title case, keeps common particles in lowercase when
        not the first word (see ``PROPER_NOUN_PARTICLES_LOWER``), splits hyphenated
        tokens per segment, and applies a ``Mc``-prefix fix only when the entire token
        is ASCII uppercase (e.g. ``MCDONALD`` -> ``McDonald``), matching typical HCM
        exports.

        ``Mac``-style surnames (e.g. ``MACDONALD``) are not rewritten to ``MacDonald``;
        only the ``Mc`` pattern is handled. Suited to data from Portugal, Latin
        America, and the United States; not locale-perfect for every edge case
        (e.g. ``O'Brien``, particles inside non-Latin scripts).

        :param str_value: Raw string from the source row; may be None.
        :return: Formatted string, or None if the input is None or blank after strip.
        """
        if str_value is None:
            return None
        stripped = str_value.strip()
        if not stripped:
            return None
        without_accents = StringFormatter.replace_accents(stripped)
        tokens = without_accents.split()
        formatted_tokens = [
            StringFormatter._format_proper_noun_token(tok, i == 0)
            for i, tok in enumerate(tokens)
        ]
        return " ".join(formatted_tokens)

    @staticmethod
    def _format_proper_noun_token(token: str, is_first_token: bool) -> str:
        """
        Title-cases a whitespace-delimited token, optionally splitting on hyphens.

        :param token: Single token without surrounding spaces.
        :param is_first_token: True if this is the first token in the full string.
        :return: Formatted token.
        """
        parts = token.split("-")
        formatted_parts = [
            StringFormatter._format_proper_noun_segment(
                part, is_first_token and segment_index == 0
            )
            for segment_index, part in enumerate(parts)
        ]
        return "-".join(formatted_parts)

    @staticmethod
    def _format_proper_noun_segment(segment: str, is_first_segment: bool) -> str:
        """
        Applies capitalization rules to a single segment (no hyphen).

        :param segment: Alphanumeric segment (may be empty when splitting hyphens).
        :param is_first_segment: True if this is the leading segment of the full token.
        :return: Segment in title or lowercase form.
        """
        if not segment:
            return segment
        lower = segment.lower()
        mc_formatted = StringFormatter._format_mc_prefix_all_caps(segment, lower)
        if mc_formatted is not None:
            return mc_formatted
        if not is_first_segment and lower in PROPER_NOUN_PARTICLES_LOWER:
            return lower
        return lower.capitalize()

    @staticmethod
    def _format_mc_prefix_all_caps(
        original_segment: str, lower_segment: str
    ) -> Optional[str]:
        """
        Formats surnames that start with the letters ``mc`` when the source token is
        entirely uppercase (e.g. Oracle/HCM exports), e.g. ``MCDONALD`` -> ``McDonald``.
        Does not treat ``MAC...`` as ``Mac...``. Skips mixed-case tokens so Portuguese
        ``Machado`` is not mangled.

        :param original_segment: Segment as in the string after unidecode.
        :param lower_segment: Lowercased ``original_segment``.
        :return: Formatted segment, or None if the heuristic does not apply.
        """
        if len(lower_segment) <= 3 or not original_segment.isupper():
            return None
        if not lower_segment.startswith("mc") or not lower_segment[2].isalpha():
            return None
        tail = lower_segment[2:]
        if len(tail) < 2:
            return None
        return "Mc" + tail.capitalize()
