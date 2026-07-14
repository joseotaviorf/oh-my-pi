"""Unit tests for markdown_sanitizer — DataHub rich-text export artifacts."""

from __future__ import annotations

from sync.markdown_sanitizer import sanitize_datahub_markdown

# ── sanitize_datahub_markdown ───────────────────────────────────────────────


def test_strips_font_size_span_keeping_text():
    md = '# **<span style="font-size:12px">Property Integrity</span>**'
    assert sanitize_datahub_markdown(md) == "# **Property Integrity**"


def test_strips_u_tags_around_link_target():
    md = "([link](<u>https://datahub.apps.data-prd.habitat.zone/x</u>))"
    assert (
        sanitize_datahub_markdown(md)
        == "([link](https://datahub.apps.data-prd.habitat.zone/x))"
    )


def test_bold_italic_underscore_becomes_bold_only():
    assert sanitize_datahub_markdown("***_Data Owner:_***") == "**Data Owner:**"


def test_asterisk_underscore_italic_becomes_bold_only():
    assert sanitize_datahub_markdown("*_without friction_*") == "**without friction**"


def test_triple_asterisk_bold_italic_becomes_bold_only():
    assert sanitize_datahub_markdown("***without repairs***") == "**without repairs**"


def test_single_asterisk_italic_becomes_bold_only():
    assert sanitize_datahub_markdown("a *word* here") == "a **word** here"


def test_pure_underscore_italic_is_preserved():
    # Italic is allowed only via underscores with no asterisks present.
    assert sanitize_datahub_markdown("this is _really_ important") == (
        "this is _really_ important"
    )


def test_existing_bold_is_left_untouched():
    assert sanitize_datahub_markdown("keep **this** bold") == "keep **this** bold"


def test_leaves_clean_markdown_untouched():
    md = (
        "# NPS FR\n\n"
        "## Ownership\n\n"
        "**Data Owner:**\n"
        "- samia.lauar@quintoandar.com.br\n"
    )
    assert sanitize_datahub_markdown(md) == md


def test_reflows_role_heading_glued_to_inline_bullets():
    md = (
        "***_Data Owner:_***- [carolina.espinoza@quintoandar.com.br]"
        "(mailto:carolina.espinoza@quintoandar.com.br)- [felipe.abreu@quintoandar.com.br]"
        "(mailto:felipe.abreu@quintoandar.com.br)  "
    )
    result = sanitize_datahub_markdown(md)
    lines = [ln for ln in result.split("\n") if ln.strip()]
    assert lines[0] == "**Data Owner:**"
    assert (
        lines[1]
        == "- [carolina.espinoza@quintoandar.com.br](mailto:carolina.espinoza@quintoandar.com.br)"
    )
    assert (
        lines[2]
        == "- [felipe.abreu@quintoandar.com.br](mailto:felipe.abreu@quintoandar.com.br)"
    )


def test_reflows_bullet_list_with_first_item_intact():
    md = (
        "- **Property Integrity** → this family of four metrics- "
        "**% Offb. W/o Mediation** → % Offb. W/o Mediation- "
        "**% Without Repairs** → % Without Repairs"
    )
    result = sanitize_datahub_markdown(md)
    lines = result.split("\n")
    assert lines == [
        "- **Property Integrity** → this family of four metrics",
        "- **% Offb. W/o Mediation** → % Offb. W/o Mediation",
        "- **% Without Repairs** → % Without Repairs",
    ]


def test_prose_with_spaced_dash_is_not_turned_into_bullets():
    # A prose line with a spaced dash ("A - B") must not be reflowed into a list.
    md = "Not Concilied - SAP missing"
    assert sanitize_datahub_markdown(md) == md


def test_prose_line_with_glue_like_dash_but_no_heading_is_left_alone():
    # No leading bullet and no pseudo-heading → prose, even with "word- word".
    md = "Use `schema.table-name` here- and here"
    assert sanitize_datahub_markdown(md) == md


def test_single_bullet_with_inner_spaced_dash_is_not_split():
    md = "- A single bullet with - a prose dash inside"
    assert sanitize_datahub_markdown(md) == md


def test_second_pseudo_heading_gets_blank_line_before_it():
    # Two role groups on separate glued lines: the second heading must not be
    # absorbed as a lazy continuation of the first group's last bullet.
    md = (
        "***_Data Owner:_***- a@quintoandar.com.br- b@quintoandar.com.br\n"
        "***_Data Steward:_***- c@quintoandar.com.br"
    )
    lines = sanitize_datahub_markdown(md).split("\n")
    steward_idx = lines.index("**Data Steward:**")
    assert lines[steward_idx - 1] == "", (
        "expected a blank line before the second heading"
    )


def test_reflows_collapsed_table_into_rows():
    md = (
        "| Concept | Column || :---- | :---- "
        "|| Mediation ticket | `has_mediation_ticket` "
        "|| Termination had repairs | `has_repairs` |"
    )
    lines = [ln for ln in sanitize_datahub_markdown(md).split("\n") if ln.strip()]
    assert lines == [
        "| Concept | Column |",
        "| :---- | :---- |",
        "| Mediation ticket | `has_mediation_ticket` |",
        "| Termination had repairs | `has_repairs` |",
    ]


def test_joins_table_rows_datahub_exported_as_separate_paragraphs():
    # Regression: DataHub exported each row of the "Cases Perspective" Context
    # Document's last_team exclusion table as its own blank-line-separated
    # paragraph — the opposite shape from the single-line-glued-with-"||"
    # case above. GFM requires contiguous rows, so this rendered as isolated
    # text instead of a table.
    md = (
        "regardless of which department they were logged under:\n\n"
        "| `last_team` | Why it is excluded |\n\n"
        "| :---- | :---- |\n\n"
        "| `CX Expert` | Pre-Contract |\n\n"
        "| `Propostas` | Pre-Contract |\n\n"
        "One additional `last_team` is excluded for a different reason\n"
    )
    result = sanitize_datahub_markdown(md)
    assert result == (
        "regardless of which department they were logged under:\n\n"
        "| `last_team` | Why it is excluded |\n"
        "| :---- | :---- |\n"
        "| `CX Expert` | Pre-Contract |\n"
        "| `Propostas` | Pre-Contract |\n\n"
        "One additional `last_team` is excluded for a different reason\n"
    )


def test_does_not_join_a_single_isolated_pipe_line():
    # A lone line that starts/ends with "|" but has no adjacent row is left
    # alone — never part of a table, so nothing to join.
    md = "Some prose.\n\n| not really a table row |\n\nMore prose.\n"
    assert sanitize_datahub_markdown(md) == md


def test_leaves_well_formed_multiline_table_untouched():
    md = "| A | B |\n| :-- | :-- |\n| 1 | 2 |"
    assert sanitize_datahub_markdown(md) == md


def test_unwraps_bold_wrapped_atx_heading():
    md = "**### Query 1 — Property Integrity (all four metrics by month)**"
    assert (
        sanitize_datahub_markdown(md)
        == "### Query 1 — Property Integrity (all four metrics by month)"
    )


def test_unwraps_bold_wrapped_h2_heading_with_trailing_hard_break():
    md = "**## Dos and Don'ts**  "
    assert sanitize_datahub_markdown(md) == "## Dos and Don'ts"


def test_does_not_unwrap_literal_bold_hashtag():
    md = "**#1 priority**"
    assert sanitize_datahub_markdown(md) == md


def test_preserves_clean_code_block_content():
    md = "```sql\nSELECT * FROM a.b-c\n```"
    out = sanitize_datahub_markdown(md)
    # Content is preserved verbatim (dashes inside code are never reflowed);
    # a clean block may gain surrounding blank lines, which are harmless.
    assert out.strip() == "```sql\nSELECT * FROM a.b-c\n```"


def test_glued_closing_fence_closes_the_block():
    # DataHub glues the closing ``` to the last line; the block must still close
    # there so following prose/sections are not swallowed.
    md = (
        "```% Without Repairs = count_if(x = false) / count(*)\n"
        "% Both Agree = count_if(y) / count_if(z)```\n"
        "The denominators differ by metric.\n\n"
        "### Canonical Filter"
    )
    lines = sanitize_datahub_markdown(md).split("\n")
    fence_lines = [i for i, ln in enumerate(lines) if ln.strip() == "```"]
    assert len(fence_lines) == 2, (
        "expected the block to open and close on their own lines"
    )
    open_i, close_i = fence_lines
    after = "\n".join(lines[close_i + 1 :])
    assert "The denominators differ by metric." in after
    assert "### Canonical Filter" in after


def test_glued_uppercase_language_tag_is_split_out():
    # The golden-query shape: ```sqlSELECT … — the uppercase S after ``sql`` is a
    # clear word boundary, so ``sql`` is peeled and _SQL_BLOCK_RE can still match.
    md = "```sqlSELECT a FROM t WHERE b = 1```"
    out = sanitize_datahub_markdown(md).strip()
    assert out == "```sql\nSELECT a FROM t WHERE b = 1\n```"


def test_language_tag_followed_by_space_is_recognized():
    # ```sql SELECT … (space after the tag) must keep ``sql`` on the opener,
    # otherwise _SQL_BLOCK_RE (which needs ```sql\b) would drop the query.
    md = "```sql SELECT a FROM t```"
    out = sanitize_datahub_markdown(md).strip()
    assert out == "```sql\nSELECT a FROM t\n```"


def test_sqlite_tag_is_not_mistaken_for_glued_sql():
    # ```sqlite must stay ```sqlite, not be split into ``sql`` + ``ite…``.
    md = "```sqlite\nSELECT 1\n```"
    out = sanitize_datahub_markdown(md).strip()
    assert out == "```sqlite\nSELECT 1\n```"


def test_lowercase_glued_prefix_is_left_as_content_not_split_midword():
    # ```sqlis_eviction — a lowercase continuation is ambiguous, so ``sql`` is NOT
    # peeled (avoids corrupting a real longer tag); it stays as block content.
    md = "```sqlis_eviction = false```"
    out = sanitize_datahub_markdown(md).strip()
    assert out == "```\nsqlis_eviction = false\n```"


def test_does_not_touch_inline_code_spans():
    md = "Use `schema.table-name` here- and here"
    result = sanitize_datahub_markdown(md)
    assert "`schema.table-name`" in result


def test_does_not_split_hyphenated_word():
    md = "- the automatic-discount agreement flag (`has_discount_agreement`)"
    assert sanitize_datahub_markdown(md) == md
