"""
Tests for fact_pull_requests — validating the new commit/comment-derived columns
against real-world fixture data.

Each test class maps to a business question the new data enables:

  BQ1  Coding Time           How long from first commit to PR creation?
  BQ2  Review Wait Time      How long do PRs wait for first review?
  BQ3  Time to Approval      How long from PR open to first approval?
  BQ4  Merge Lag             After approval, how long until merge?
  BQ5  Cycle Time Breakdown  What % of total time is coding vs. review vs. merge?
  BQ6  Review Depth          How many inline (DIFF) comments per PR?
  BQ7  Revision Cycles       How many CHANGES_REQUESTED events before approval?
  BQ8  Commit Patterns       How many commits per PR?
  BQ9  Self-Merging          What % of PRs merge without approval?
  BQ10 Review Participation  How many distinct reviewers per PR?
  BQ11 Human Review Wait     How long for first HUMAN review (excluding bots)?
  BQ12 Human Approval Wait   How long for first HUMAN approval?
  BQ13 Bot vs Human Split    What fraction of comments are from bots?
  BQ14 Bot-Only Approval     Are there PRs with only bot approvals?
  BQ15 Human Reviewer Count  How many human reviewers engage per PR?
  BQ16 Code Suggestions      How many PRs receive concrete code suggestions?
  BQ17 Actionable Comments   What fraction of inline comments are actionable?
  BQ18 Question Comments     How many inline comments are context-seeking questions?
  BQ19 PR Size Category      How does review quality vary by PR size?
  BQ20 Review Quality Index  Can we measure review quality per team/engineer?
  BQ21 Dismissed Reviews     How many review cycles get dismissed (rework signal)?
"""

import pytest


CLEAN_DB = "datalake_devlake_clean"


@pytest.fixture(autouse=True)
def register_source_tables(
    spark,
    pull_requests_df,
    pr_custom_metrics_df,
    pull_request_team_df,
    pull_request_commits_df,
    pull_request_comments_df,
):
    """Register fixture DataFrames as temp views matching the SQL's source tables."""
    pull_requests_df.createOrReplaceTempView(f"{CLEAN_DB}.pull_requests")
    pr_custom_metrics_df.createOrReplaceTempView(f"{CLEAN_DB}.pr_custom_metrics")
    pull_request_team_df.createOrReplaceTempView(f"{CLEAN_DB}.pull_request_team")
    pull_request_commits_df.createOrReplaceTempView(f"{CLEAN_DB}.pull_request_commits")
    pull_request_comments_df.createOrReplaceTempView(f"{CLEAN_DB}.pull_request_comments")


@pytest.fixture
def fact_df(spark, register_source_tables):
    """Execute the fact SQL and return the result DataFrame."""
    import pathlib

    sql_path = (
        pathlib.Path(__file__).resolve().parents[4]
        / "dags"
        / "tech_platform"
        / "dw_devlake"
        / "queries"
        / "dw"
        / "fact_pull_requests.sql"
    )
    sql = sql_path.read_text()
    return spark.sql(sql)


def _row(fact_df, pr_id):
    """Helper: get a single fact row by PR natural key."""
    rows = fact_df.filter(f"id_pr = '{pr_id}'").collect()
    assert len(rows) == 1, f"Expected 1 row for {pr_id}, got {len(rows)}"
    return rows[0]


# ────────────────────────────────────────────────────────────────
# BQ1 — Coding Time
# ────────────────────────────────────────────────────────────────
class TestCodingTime:
    """How long from first commit to PR creation?"""

    def test_positive_coding_time(self, fact_df):
        """PR-F: first commit 8 min 25 sec before PR created → positive coding_time."""
        row = _row(fact_df, "pr-F")
        assert row["coding_time_seconds"] == 505  # 19:33:38 - 19:25:13 = 505s

    def test_near_zero_coding_time(self, fact_df):
        """PR-B (bot): commit 1 sec before PR → coding_time ≈ 1."""
        row = _row(fact_df, "pr-B")
        assert row["coding_time_seconds"] == 1  # 19:51:39 - 19:51:38

    def test_coding_time_null_when_no_commits(self, fact_df):
        """PR-J (open, no commits in fixture) → coding_time is NULL."""
        row = _row(fact_df, "pr-J")
        assert row["coding_time_seconds"] is None

    def test_first_commit_date_populated(self, fact_df):
        """PR-A: first commit date should be 2026-02-24."""
        from datetime import date

        row = _row(fact_df, "pr-A")
        assert row["dt_first_commit"] == date(2026, 2, 24)


# ────────────────────────────────────────────────────────────────
# BQ2 — Review Wait Time
# ────────────────────────────────────────────────────────────────
class TestReviewWaitTime:
    """How long do PRs wait for the first comment/review after opening?"""

    def test_fast_bot_comment(self, fact_df):
        """PR-A: bot commented 25 sec after PR opened."""
        row = _row(fact_df, "pr-A")
        assert row["review_wait_seconds"] == 25  # 14:40:32 - 14:40:07

    def test_review_wait_null_when_no_comments(self, fact_df):
        """PR-J has no comments → review_wait is NULL."""
        row = _row(fact_df, "pr-J")
        assert row["review_wait_seconds"] is None

    def test_first_comment_date_populated(self, fact_df):
        """PR-G: first comment is on 2026-01-12."""
        from datetime import date

        row = _row(fact_df, "pr-G")
        assert row["dt_first_comment"] == date(2026, 1, 12)


# ────────────────────────────────────────────────────────────────
# BQ3 — Time to First Approval
# ────────────────────────────────────────────────────────────────
class TestTimeToFirstApproval:
    """How long from PR creation to first APPROVED review?"""

    def test_quick_approval(self, fact_df):
        """PR-D: approved 916 sec (≈15 min) after creation."""
        row = _row(fact_df, "pr-D")
        assert row["first_approval_seconds"] == 916  # 17:23:13 - 17:07:57

    def test_slow_approval(self, fact_df):
        """PR-A: 10 days to first approval → large value."""
        row = _row(fact_df, "pr-A")
        expected = int(
            (1741286062 - 1740404407)  # 2026-03-06 18:34:22 - 2026-02-24 14:40:07
        )
        assert row["first_approval_seconds"] == expected

    def test_no_approval_null(self, fact_df):
        """PR-C: self-merged with no approval → first_approval_seconds is NULL."""
        row = _row(fact_df, "pr-C")
        assert row["first_approval_seconds"] is None
        assert row["approval_count"] == 0

    def test_first_approval_date(self, fact_df):
        """PR-G: first approval on 2026-01-21."""
        from datetime import date

        row = _row(fact_df, "pr-G")
        assert row["dt_first_approval"] == date(2026, 1, 21)


# ────────────────────────────────────────────────────────────────
# BQ4 — Merge Lag (after approval)
# ────────────────────────────────────────────────────────────────
class TestMergeLag:
    """After first approval, how long until the PR is merged?"""

    def test_merge_lag_positive(self, fact_df):
        """PR-D: merged 5 min 37 sec after first approval."""
        row = _row(fact_df, "pr-D")
        assert row["merge_after_approval_seconds"] == 337  # 17:28:50 - 17:23:13

    def test_merge_lag_null_without_approval(self, fact_df):
        """PR-C: no approval → merge_after_approval is NULL."""
        row = _row(fact_df, "pr-C")
        assert row["merge_after_approval_seconds"] is None

    def test_merge_lag_null_when_not_merged(self, fact_df):
        """PR-J (open): not merged → merge_after_approval is NULL."""
        row = _row(fact_df, "pr-J")
        assert row["merge_after_approval_seconds"] is None


# ────────────────────────────────────────────────────────────────
# BQ5 — Cycle Time Breakdown
# ────────────────────────────────────────────────────────────────
class TestCycleTimeBreakdown:
    """Can we decompose total cycle time into coding + review + merge?"""

    def test_full_breakdown_available(self, fact_df):
        """PR-D: all 3 components available for a clean breakdown."""
        row = _row(fact_df, "pr-D")
        assert row["coding_time_seconds"] is not None
        assert row["first_approval_seconds"] is not None
        assert row["merge_after_approval_seconds"] is not None
        total = row["coding_time_seconds"] + row["first_approval_seconds"] + row["merge_after_approval_seconds"]
        assert total > 0

    def test_partial_breakdown_when_no_approval(self, fact_df):
        """PR-C: no approval → only coding_time and review_wait available."""
        row = _row(fact_df, "pr-C")
        assert row["coding_time_seconds"] is not None
        assert row["review_wait_seconds"] is not None
        assert row["first_approval_seconds"] is None


# ────────────────────────────────────────────────────────────────
# BQ6 — Review Depth
# ────────────────────────────────────────────────────────────────
class TestReviewDepth:
    """How many inline code review comments (DIFF) does each PR receive?"""

    def test_high_diff_comments(self, fact_df):
        """PR-I: 4 DIFF comments from engaged reviewers."""
        row = _row(fact_df, "pr-I")
        assert row["diff_comment_count"] == 4

    def test_no_diff_comments(self, fact_df):
        """PR-D: only REVIEW approvals, no inline comments."""
        row = _row(fact_df, "pr-D")
        assert row["diff_comment_count"] == 0

    def test_zero_when_no_comments(self, fact_df):
        """PR-J: no comments at all → diff_comment_count = 0."""
        row = _row(fact_df, "pr-J")
        assert row["diff_comment_count"] == 0


# ────────────────────────────────────────────────────────────────
# BQ7 — Revision Cycles (Changes Requested)
# ────────────────────────────────────────────────────────────────
class TestRevisionCycles:
    """How many CHANGES_REQUESTED events does each PR receive?"""

    def test_no_changes_requested(self, fact_df):
        """Most PRs should have 0 changes_requested (98% in prod)."""
        row = _row(fact_df, "pr-D")
        assert row["changes_requested_count"] == 0

    def test_all_original_fixture_prs_zero_cr(self, fact_df):
        """Original fixture PRs have 0 changes_requested (mirrors 98% prod rate)."""
        rows = fact_df.filter("id_pr <> 'pr-L'").collect()
        for row in rows:
            assert row["changes_requested_count"] == 0

    def test_changes_requested_in_rework_pr(self, fact_df):
        """PR-L: 1 CHANGES_REQUESTED from human reviewer."""
        row = _row(fact_df, "pr-L")
        assert row["changes_requested_count"] == 1


# ────────────────────────────────────────────────────────────────
# BQ8 — Commit Patterns
# ────────────────────────────────────────────────────────────────
class TestCommitPatterns:
    """How many commits per PR?"""

    def test_single_commit_pr(self, fact_df):
        """PR-B: bot release with exactly 1 commit."""
        row = _row(fact_df, "pr-B")
        assert row["commit_count"] == 1

    def test_multi_commit_pr(self, fact_df):
        """PR-A: 3 commits across 10 days."""
        row = _row(fact_df, "pr-A")
        assert row["commit_count"] == 3

    def test_zero_commits_when_missing(self, fact_df):
        """PR-J: no commit records → commit_count = 0."""
        row = _row(fact_df, "pr-J")
        assert row["commit_count"] == 0


# ────────────────────────────────────────────────────────────────
# BQ9 — Self-Merging (no approval)
# ────────────────────────────────────────────────────────────────
class TestSelfMerging:
    """Identify PRs merged without any approval."""

    def test_self_merged_pr(self, fact_df):
        """PR-C: merged with 0 approvals → self-merged."""
        row = _row(fact_df, "pr-C")
        assert row["approval_count"] == 0
        assert row["is_merged"] is True

    def test_approved_pr(self, fact_df):
        """PR-D: 2 approvals → not self-merged."""
        row = _row(fact_df, "pr-D")
        assert row["approval_count"] == 2

    def test_self_merge_rate_calculable(self, fact_df):
        """Can compute self-merge rate from the fact table."""
        merged = fact_df.filter("is_merged = TRUE")
        no_approval = merged.filter("approval_count = 0").count()
        total = merged.count()
        rate = no_approval / total
        assert 0 <= rate <= 1


# ────────────────────────────────────────────────────────────────
# BQ10 — Review Participation
# ────────────────────────────────────────────────────────────────
class TestReviewParticipation:
    """How many distinct reviewers engage per PR?"""

    def test_high_reviewer_count(self, fact_df):
        """PR-I: 6 distinct reviewers (rev-13 through rev-18)."""
        row = _row(fact_df, "pr-I")
        assert row["reviewer_count"] == 6

    def test_single_reviewer(self, fact_df):
        """PR-E: 1 reviewer (rev-6)."""
        row = _row(fact_df, "pr-E")
        assert row["reviewer_count"] == 1

    def test_zero_reviewers(self, fact_df):
        """PR-J: no comments → 0 reviewers."""
        row = _row(fact_df, "pr-J")
        assert row["reviewer_count"] == 0

    def test_no_bot_counted_as_reviewer(self, fact_df):
        """PR-C: only bot NORMAL comments → 0 reviewers (bots excluded by type filter)."""
        row = _row(fact_df, "pr-C")
        assert row["reviewer_count"] == 0


# ────────────────────────────────────────────────────────────────
# Cross-cutting: grain and key integrity
# ────────────────────────────────────────────────────────────────
class TestGrainAndKeys:
    """Validate fact table grain and surrogate key behaviour."""

    def test_one_row_per_pr(self, fact_df):
        """Fact should maintain 1 row per PR grain despite M:N team and N commits/comments."""
        assert fact_df.count() == 12  # 10 original + PR-K + PR-L
        assert fact_df.select("sk_pr").distinct().count() == 12

    def test_sk_pr_not_null(self, fact_df):
        assert fact_df.filter("sk_pr IS NULL").count() == 0

    def test_date_keys_format(self, fact_df):
        """Date keys should be YYYYMMDD integers."""
        row = _row(fact_df, "pr-D")
        assert row["sk_created_date"] == 20260120
        assert row["sk_first_commit_date"] == 20260120

    def test_new_date_keys_null_when_no_data(self, fact_df):
        """PR-J: no commits, no approvals → new date keys are NULL."""
        row = _row(fact_df, "pr-J")
        assert row["sk_first_commit_date"] is None
        assert row["sk_first_approval_date"] is None

    def test_counts_default_to_zero(self, fact_df):
        """PR-J: no commits/comments → counts default to 0, not NULL."""
        row = _row(fact_df, "pr-J")
        assert row["commit_count"] == 0
        assert row["comment_count"] == 0
        assert row["review_comment_count"] == 0
        assert row["diff_comment_count"] == 0
        assert row["approval_count"] == 0
        assert row["changes_requested_count"] == 0
        assert row["reviewer_count"] == 0
        assert row["bot_comment_count"] == 0
        assert row["human_comment_count"] == 0
        assert row["human_approval_count"] == 0
        assert row["human_reviewer_count"] == 0
        assert row["dismissed_review_count"] == 0
        assert row["human_diff_comment_count"] == 0
        assert row["suggestion_count"] == 0
        assert row["actionable_comment_count"] == 0
        assert row["question_comment_count"] == 0


# ────────────────────────────────────────────────────────────────
# BQ11 — Human Review Wait Time (excluding bots)
# ────────────────────────────────────────────────────────────────
class TestHumanReviewWait:
    """How long for first HUMAN review, excluding bot comments?"""

    def test_human_wait_longer_than_total(self, fact_df):
        """PR-A: bot commented at +25s, first human at +69593s (next day) → human wait > total wait."""
        row = _row(fact_df, "pr-A")
        assert row["review_wait_seconds"] == 25  # bot comment
        assert row["human_review_wait_seconds"] > row["review_wait_seconds"]

    def test_human_wait_null_when_only_bots(self, fact_df):
        """PR-C: only bot comments → human_review_wait is NULL."""
        row = _row(fact_df, "pr-C")
        assert row["human_review_wait_seconds"] is None
        assert row["review_wait_seconds"] is not None  # bot comment exists

    def test_human_wait_null_when_no_comments(self, fact_df):
        """PR-J: no comments at all → human_review_wait is NULL."""
        row = _row(fact_df, "pr-J")
        assert row["human_review_wait_seconds"] is None

    def test_first_human_comment_date(self, fact_df):
        """PR-G: first human comment is rev-9 DIFF on 2026-01-13."""
        from datetime import date

        row = _row(fact_df, "pr-G")
        assert row["dt_first_human_comment"] == date(2026, 1, 13)


# ────────────────────────────────────────────────────────────────
# BQ12 — Human Approval Wait Time
# ────────────────────────────────────────────────────────────────
class TestHumanApprovalWait:
    """How long for first HUMAN approval (excluding homesbot auto-approvals)?"""

    def test_human_approval_wait(self, fact_df):
        """PR-D: first human approval at 17:23:13, PR created at 17:07:57 → 916s."""
        row = _row(fact_df, "pr-D")
        assert row["human_first_approval_seconds"] == 916

    def test_bot_only_approval_has_null_human(self, fact_df):
        """PR-K: only homesbot approved → human_first_approval is NULL."""
        row = _row(fact_df, "pr-K")
        assert row["approval_count"] == 1
        assert row["human_approval_count"] == 0
        assert row["human_first_approval_seconds"] is None

    def test_human_approval_date(self, fact_df):
        """PR-E: first human approval on 2026-03-03."""
        from datetime import date

        row = _row(fact_df, "pr-E")
        assert row["dt_first_human_approval"] == date(2026, 3, 3)


# ────────────────────────────────────────────────────────────────
# BQ13 — Bot vs Human Comment Split
# ────────────────────────────────────────────────────────────────
class TestBotHumanSplit:
    """What fraction of comments are from bots?"""

    def test_bot_plus_human_equals_total(self, fact_df):
        """For every PR, bot_count + human_count = comment_count."""
        rows = fact_df.collect()
        for row in rows:
            assert row["bot_comment_count"] + row["human_comment_count"] == row["comment_count"], \
                f"Mismatch for {row['id_pr']}"

    def test_all_bot_pr(self, fact_df):
        """PR-C: 3 bot comments, 0 human comments."""
        row = _row(fact_df, "pr-C")
        assert row["bot_comment_count"] == 3
        assert row["human_comment_count"] == 0

    def test_mixed_pr(self, fact_df):
        """PR-A: 1 bot + 3 human comments."""
        row = _row(fact_df, "pr-A")
        assert row["bot_comment_count"] == 1
        assert row["human_comment_count"] == 3

    def test_no_comments_pr(self, fact_df):
        """PR-J: 0 bot, 0 human."""
        row = _row(fact_df, "pr-J")
        assert row["bot_comment_count"] == 0
        assert row["human_comment_count"] == 0


# ────────────────────────────────────────────────────────────────
# BQ14 — Bot-Only Approval Detection
# ────────────────────────────────────────────────────────────────
class TestBotOnlyApproval:
    """Can we identify PRs approved only by bots (no human approval)?"""

    def test_bot_only_approval_detected(self, fact_df):
        """PR-K: approval_count=1 (homesbot), human_approval_count=0."""
        row = _row(fact_df, "pr-K")
        assert row["approval_count"] == 1
        assert row["human_approval_count"] == 0
        assert row["is_merged"] is True

    def test_human_approval_counted(self, fact_df):
        """PR-D: 2 human approvals → human_approval_count=2."""
        row = _row(fact_df, "pr-D")
        assert row["human_approval_count"] == 2

    def test_real_no_human_approval_rate(self, fact_df):
        """Can compute the REAL no-human-approval rate (including bot-only approved)."""
        merged = fact_df.filter("is_merged = TRUE")
        no_human_approval = merged.filter("human_approval_count = 0").count()
        total = merged.count()
        rate = no_human_approval / total
        assert rate > 0  # At least PR-C and PR-K have no human approval


# ────────────────────────────────────────────────────────────────
# BQ15 — Human Reviewer Count
# ────────────────────────────────────────────────────────────────
class TestHumanReviewerCount:
    """How many distinct HUMAN reviewers engage per PR?"""

    def test_high_human_reviewer_count(self, fact_df):
        """PR-I: 6 human reviewers (all reviewers are human)."""
        row = _row(fact_df, "pr-I")
        assert row["human_reviewer_count"] == 6
        assert row["reviewer_count"] == 6  # same since no bot left REVIEW/DIFF

    def test_zero_human_reviewers_bot_only(self, fact_df):
        """PR-C: only bot NORMAL comments → 0 human reviewers."""
        row = _row(fact_df, "pr-C")
        assert row["human_reviewer_count"] == 0

    def test_bot_approval_not_counted_as_reviewer(self, fact_df):
        """PR-K: homesbot REVIEW/APPROVED should not count as human reviewer."""
        row = _row(fact_df, "pr-K")
        assert row["human_reviewer_count"] == 0


# ────────────────────────────────────────────────────────────────
# BQ16 — Code Suggestions (```suggestion blocks)
# ────────────────────────────────────────────────────────────────
class TestCodeSuggestions:
    """How many PRs receive concrete GitHub code suggestions?"""

    def test_suggestion_block_counted(self, fact_df):
        """PR-A: 1 DIFF comment with ```suggestion → suggestion_count=1."""
        row = _row(fact_df, "pr-A")
        assert row["suggestion_count"] == 1

    def test_suggestion_in_high_engagement_pr(self, fact_df):
        """PR-I: 1 suggestion block out of 4 DIFF comments."""
        row = _row(fact_df, "pr-I")
        assert row["suggestion_count"] == 1

    def test_no_suggestions_when_verbal_only(self, fact_df):
        """PR-F: verbal suggestion ("should consider") but no ```suggestion block."""
        row = _row(fact_df, "pr-F")
        assert row["suggestion_count"] == 0

    def test_zero_suggestions_no_diff(self, fact_df):
        """PR-D: only REVIEW approvals, no DIFF → suggestion_count=0."""
        row = _row(fact_df, "pr-D")
        assert row["suggestion_count"] == 0

    def test_zero_suggestions_no_comments(self, fact_df):
        """PR-J: no comments → suggestion_count=0."""
        row = _row(fact_df, "pr-J")
        assert row["suggestion_count"] == 0


# ────────────────────────────────────────────────────────────────
# BQ17 — Actionable Comments
# ────────────────────────────────────────────────────────────────
class TestActionableComments:
    """What fraction of DIFF comments contain actionable feedback?"""

    def test_verbal_suggestion_is_actionable(self, fact_df):
        """PR-F: "should consider...instead" → actionable_comment_count=1."""
        row = _row(fact_df, "pr-F")
        assert row["actionable_comment_count"] == 1

    def test_nit_and_bug_are_actionable(self, fact_df):
        """PR-G: 1 nit + 1 bug flag → actionable_comment_count=2."""
        row = _row(fact_df, "pr-G")
        assert row["actionable_comment_count"] == 2

    def test_suggestion_block_is_actionable(self, fact_df):
        """PR-A: suggestion block counts as actionable."""
        row = _row(fact_df, "pr-A")
        assert row["actionable_comment_count"] == 1
        assert row["suggestion_count"] <= row["actionable_comment_count"]

    def test_mixed_actionable_and_non(self, fact_df):
        """PR-I: 2 actionable (suggestion + "could"), 1 question, 1 plain → 2 actionable."""
        row = _row(fact_df, "pr-I")
        assert row["actionable_comment_count"] == 2

    def test_actionable_lte_human_diff(self, fact_df):
        """For every PR, actionable_comment_count <= human_diff_comment_count."""
        rows = fact_df.collect()
        for row in rows:
            assert row["actionable_comment_count"] <= row["human_diff_comment_count"], \
                f"Mismatch for {row['id_pr']}"

    def test_zero_actionable_no_comments(self, fact_df):
        """PR-J: no comments → actionable_comment_count=0."""
        row = _row(fact_df, "pr-J")
        assert row["actionable_comment_count"] == 0


# ────────────────────────────────────────────────────────────────
# BQ18 — Question Comments
# ────────────────────────────────────────────────────────────────
class TestQuestionComments:
    """How many DIFF comments are context-seeking questions?"""

    def test_short_question_counted(self, fact_df):
        """PR-F: "Why is this needed?" (19 chars, has ?) → question_comment_count=1."""
        row = _row(fact_df, "pr-F")
        assert row["question_comment_count"] == 1

    def test_question_in_mixed_pr(self, fact_df):
        """PR-I: "What does this flag do?" → question_comment_count=1."""
        row = _row(fact_df, "pr-I")
        assert row["question_comment_count"] == 1

    def test_suggestion_block_not_counted_as_question(self, fact_df):
        """PR-A: suggestion block with no ? → question_comment_count=0."""
        row = _row(fact_df, "pr-A")
        assert row["question_comment_count"] == 0

    def test_no_questions_review_only(self, fact_df):
        """PR-D: only REVIEW comments, no DIFF → question_comment_count=0."""
        row = _row(fact_df, "pr-D")
        assert row["question_comment_count"] == 0

    def test_question_disjoint_from_suggestion(self, fact_df):
        """Questions exclude suggestion blocks (no double-counting)."""
        rows = fact_df.collect()
        for row in rows:
            if row["human_diff_comment_count"] > 0:
                assert row["suggestion_count"] + row["question_comment_count"] <= \
                    row["human_diff_comment_count"], f"Double-count in {row['id_pr']}"


# ────────────────────────────────────────────────────────────────
# BQ19 — PR Size Category
# ────────────────────────────────────────────────────────────────
class TestPRSizeCategory:
    """Does pr_size_category correctly bucket PRs by additions+deletions?"""

    def test_xs_pr(self, fact_df):
        """PR-E: 4+0=4 lines → XS."""
        row = _row(fact_df, "pr-E")
        assert row["pr_size_category"] == "XS"

    def test_small_pr(self, fact_df):
        """PR-D: 9+28=37 lines → S."""
        row = _row(fact_df, "pr-D")
        assert row["pr_size_category"] == "S"

    def test_medium_pr(self, fact_df):
        """PR-F: 120+18=138 lines → M."""
        row = _row(fact_df, "pr-F")
        assert row["pr_size_category"] == "M"

    def test_large_pr(self, fact_df):
        """PR-C: 481+3=484 lines → L."""
        row = _row(fact_df, "pr-C")
        assert row["pr_size_category"] == "L"

    def test_xl_pr(self, fact_df):
        """PR-A: 2964+1796=4760 lines → XL."""
        row = _row(fact_df, "pr-A")
        assert row["pr_size_category"] == "XL"

    def test_boundary_xs_10(self, fact_df):
        """PR-J: 10+0=10 → XS (boundary at ≤10)."""
        row = _row(fact_df, "pr-J")
        assert row["pr_size_category"] == "XS"

    def test_all_prs_have_size_category(self, fact_df):
        """Every PR should have a non-null pr_size_category."""
        rows = fact_df.collect()
        for row in rows:
            assert row["pr_size_category"] in ("XS", "S", "M", "L", "XL"), \
                f"Invalid size category for {row['id_pr']}: {row['pr_size_category']}"


# ────────────────────────────────────────────────────────────────
# BQ20 — Review Quality Index (cross-cutting)
# ────────────────────────────────────────────────────────────────
class TestReviewQualityIndex:
    """Can we compute a review quality signal from the new columns?"""

    def test_high_quality_review(self, fact_df):
        """PR-G: 2 DIFF comments, both actionable (nit + bug) → high quality signal."""
        row = _row(fact_df, "pr-G")
        assert row["human_diff_comment_count"] == 2
        assert row["actionable_comment_count"] == 2
        actionable_ratio = row["actionable_comment_count"] / row["human_diff_comment_count"]
        assert actionable_ratio == 1.0

    def test_low_quality_review(self, fact_df):
        """PR-I: 4 DIFF comments, 2 actionable → 50% actionable ratio."""
        row = _row(fact_df, "pr-I")
        assert row["human_diff_comment_count"] == 4
        assert row["actionable_comment_count"] == 2
        actionable_ratio = row["actionable_comment_count"] / row["human_diff_comment_count"]
        assert actionable_ratio == 0.5

    def test_rubber_stamp_detection(self, fact_df):
        """PR-H: 2 approvals, 0 DIFF → rubber stamp review."""
        row = _row(fact_df, "pr-H")
        assert row["human_approval_count"] == 2
        assert row["human_diff_comment_count"] == 0

    def test_human_diff_lte_diff_count(self, fact_df):
        """For every PR, human_diff_comment_count <= diff_comment_count."""
        rows = fact_df.collect()
        for row in rows:
            assert row["human_diff_comment_count"] <= row["diff_comment_count"], \
                f"Mismatch for {row['id_pr']}"


# ────────────────────────────────────────────────────────────────
# BQ21 — Dismissed Reviews (rework signal)
# ────────────────────────────────────────────────────────────────
class TestDismissedReviews:
    """How many review cycles get dismissed? Signals rework and review churn."""

    def test_rework_cycle_dismissed_count(self, fact_df):
        """PR-L: 2 DISMISSED reviews (1 homesbot + 1 human CR)."""
        row = _row(fact_df, "pr-L")
        assert row["dismissed_review_count"] == 2

    def test_rework_has_changes_requested(self, fact_df):
        """PR-L: 1 CHANGES_REQUESTED alongside dismissed reviews."""
        row = _row(fact_df, "pr-L")
        assert row["changes_requested_count"] == 1

    def test_rework_cycle_has_human_approval(self, fact_df):
        """PR-L: after rework, human approved → human_approval_count=1."""
        row = _row(fact_df, "pr-L")
        assert row["human_approval_count"] == 1
        assert row["approval_count"] == 2  # homesbot + human

    def test_rework_longer_cycle(self, fact_df):
        """PR-L: rework cycle should have valid first_approval_seconds."""
        row = _row(fact_df, "pr-L")
        assert row["first_approval_seconds"] is not None
        assert row["first_approval_seconds"] > 0

    def test_no_dismissed_for_clean_pr(self, fact_df):
        """PR-D: clean approval without rework → dismissed_review_count=0."""
        row = _row(fact_df, "pr-D")
        assert row["dismissed_review_count"] == 0

    def test_dismissed_not_counted_as_approval(self, fact_df):
        """DISMISSED reviews should NOT inflate approval_count."""
        row = _row(fact_df, "pr-L")
        assert row["dismissed_review_count"] == 2
        assert row["approval_count"] == 2  # only APPROVED, not DISMISSED

    def test_rework_rate_calculable(self, fact_df):
        """Can compute rework rate (% of PRs with dismissed reviews)."""
        merged = fact_df.filter("is_merged = TRUE")
        has_dismissed = merged.filter("dismissed_review_count > 0").count()
        total = merged.count()
        rate = has_dismissed / total
        assert rate > 0  # at least PR-L has dismissed reviews

    def test_rework_comment_breakdown(self, fact_df):
        """PR-L: full comment breakdown including dismissed reviews."""
        row = _row(fact_df, "pr-L")
        assert row["comment_count"] == 7
        assert row["review_comment_count"] == 5
        assert row["diff_comment_count"] == 1
        assert row["bot_comment_count"] == 3
        assert row["human_comment_count"] == 4
        assert row["human_reviewer_count"] == 1
        assert row["pr_size_category"] == "L"
