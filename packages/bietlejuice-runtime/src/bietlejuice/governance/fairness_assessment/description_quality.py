"""Heuristics for table and column description text in governance documentation."""

from __future__ import annotations

import re
import unicodedata
from typing import FrozenSet, Optional

from bietlejuice.governance.fairness_assessment.constants import (
    TDQ_BOILERPLATE_PHRASES,
    TDQ_BOILERPLATE_TOKENS,
    TDQ_MAX_NAME_OVERLAP_RATIO,
    TDQ_MIN_DESC_CHARS,
    TDQ_MIN_SUBSTANTIVE_EXTRA_WORDS,
    TDQ_STOPWORDS,
    TDQ_WORD_RE,
)
from bietlejuice.governance.fairness_assessment.models import (
    TableDescriptionQualityResult,
)


def _tdq_normalize(s: Optional[str]) -> str:
    if s is None:
        return ""
    t = unicodedata.normalize("NFKC", str(s)).strip().lower()
    return t


def _tdq_fold_token(t: str) -> str:
    return "".join(
        c for c in unicodedata.normalize("NFD", t) if unicodedata.category(c) != "Mn"
    ).lower()


def _tdq_identifier_tokens(
    database_name: Optional[str], table_name: Optional[str]
) -> FrozenSet[str]:
    out: set[str] = set()
    db = _tdq_normalize(database_name or "")
    tb = _tdq_normalize(table_name or "")
    for s in (db, tb):
        if not s:
            continue
        out.add(_tdq_fold_token(s))
        for piece in re.split(r"[\s_.\-]+", s):
            if piece and not piece.isdigit():
                out.add(_tdq_fold_token(piece))
    if db and tb:
        out.add(_tdq_fold_token(f"{db}.{tb}"))
        out.add(_tdq_fold_token(f"{db}_{tb}"))
    return frozenset(out)


def _tdq_identifier_tokens_including_column(
    database_name: Optional[str],
    table_name: Optional[str],
    column_name: Optional[str],
) -> FrozenSet[str]:
    """F2-02: include column name and common splits (``snake_case``) in the identifier vocabulary."""

    base = set(_tdq_identifier_tokens(database_name, table_name))
    col = _tdq_normalize(column_name or "")
    if not col:
        return frozenset(base)
    base.add(_tdq_fold_token(col))
    for piece in re.split(r"[\s_.\-]+", col):
        if piece and not piece.isdigit():
            base.add(_tdq_fold_token(piece))
    return frozenset(base)


def _tdq_strip_boilerplate_phrases(normalized_desc: str) -> str:
    out = normalized_desc
    for phrase in sorted(TDQ_BOILERPLATE_PHRASES, key=len, reverse=True):
        out = out.replace(phrase, " ")
    return out


def _tdq_word_tokens(s: str) -> list[str]:
    return [m.group(0) for m in TDQ_WORD_RE.finditer(s) if m.group(0)]


def _assess_description_body(
    desc: str,
    id_vocab: FrozenSet[str],
) -> TableDescriptionQualityResult:
    """Heuristic substance check given NFKC-stripped, lowercased text and a folded identifier token set."""
    if not desc:
        return TableDescriptionQualityResult(
            is_substantive=False,
            content_word_count=0,
            non_identifier_word_count=0,
            name_overlap_ratio=0.0,
            reason_code="empty",
        )

    stripped = _tdq_strip_boilerplate_phrases(desc)
    tokens = [_tdq_fold_token(t) for t in _tdq_word_tokens(stripped)]
    tokens_nostop = [t for t in tokens if t not in TDQ_STOPWORDS and not t.isdigit()]

    content_word_count = len(tokens_nostop)
    boilerplate_folded = {_tdq_fold_token(x) for x in TDQ_BOILERPLATE_TOKENS}
    substantive_tokens = [
        t for t in tokens_nostop if t not in id_vocab and t not in boilerplate_folded
    ]
    non_identifier_word_count = len(substantive_tokens)

    if not tokens_nostop:
        name_overlap_ratio = 1.0
    else:
        hit = sum(1 for t in tokens_nostop if t in id_vocab)
        name_overlap_ratio = hit / float(len(tokens_nostop))

    if non_identifier_word_count >= TDQ_MIN_SUBSTANTIVE_EXTRA_WORDS:
        return TableDescriptionQualityResult(
            is_substantive=True,
            content_word_count=content_word_count,
            non_identifier_word_count=non_identifier_word_count,
            name_overlap_ratio=name_overlap_ratio,
            reason_code=None,
        )
    if len(desc) < TDQ_MIN_DESC_CHARS:
        return TableDescriptionQualityResult(
            is_substantive=False,
            content_word_count=content_word_count,
            non_identifier_word_count=non_identifier_word_count,
            name_overlap_ratio=name_overlap_ratio,
            reason_code="too_short",
        )
    if (
        non_identifier_word_count == 1
        and name_overlap_ratio > TDQ_MAX_NAME_OVERLAP_RATIO
    ):
        return TableDescriptionQualityResult(
            is_substantive=False,
            content_word_count=content_word_count,
            non_identifier_word_count=non_identifier_word_count,
            name_overlap_ratio=name_overlap_ratio,
            reason_code="boilerplate_or_name_echo",
        )
    if non_identifier_word_count == 0:
        return TableDescriptionQualityResult(
            is_substantive=False,
            content_word_count=content_word_count,
            non_identifier_word_count=non_identifier_word_count,
            name_overlap_ratio=name_overlap_ratio,
            reason_code="boilerplate_or_name_echo",
        )
    return TableDescriptionQualityResult(
        is_substantive=True,
        content_word_count=content_word_count,
        non_identifier_word_count=non_identifier_word_count,
        name_overlap_ratio=name_overlap_ratio,
        reason_code=None,
    )


def assess_table_description_quality(
    database_name: Optional[str],
    table_name: Optional[str],
    table_description: Optional[str],
) -> TableDescriptionQualityResult:
    """Return whether the table description adds substance beyond the identifier / boilerplate."""
    desc = _tdq_normalize(table_description)
    id_vocab = _tdq_identifier_tokens(database_name, table_name)
    return _assess_description_body(desc, id_vocab)


def assess_column_description_quality(
    database_name: Optional[str],
    table_name: Optional[str],
    column_name: Optional[str],
    column_description: Optional[str],
) -> TableDescriptionQualityResult:
    """F2-02: same heuristics as table descriptions, with column name in the identifier token set."""
    desc = _tdq_normalize(column_description)
    id_vocab = _tdq_identifier_tokens_including_column(
        database_name, table_name, column_name
    )
    return _assess_description_body(desc, id_vocab)
