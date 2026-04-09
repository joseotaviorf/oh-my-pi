"""
Fixtures for dw_devlake fact_pull_requests tests.

All fixture data is derived from real DevLake production data (anonymised IDs).
Each fixture exercises a different business scenario the new commit/comment
columns must handle correctly.
"""

import datetime as dt

import pytest
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    BooleanType,
    IntegerType,
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)


@pytest.fixture(scope="session")
def spark(tmp_path_factory):
    warehouse = str(tmp_path_factory.mktemp("spark-warehouse"))
    spark = (
        SparkSession.builder.appName("dw_devlake_tests")
        .master("local[1]")
        .config("spark.sql.warehouse.dir", warehouse)
        .config("spark.sql.shuffle.partitions", "1")
        .config("spark.default.parallelism", "1")
        .config("spark.driver.bindAddress", "127.0.0.1")
        .getOrCreate()
    )
    yield spark
    spark.stop()


# ---------- schemas (matching datalake_devlake_clean) ----------

PR_SCHEMA = StructType(
    [
        StructField("id_pr", StringType(), False),
        StructField("id_repo", StringType(), False),
        StructField("pr_key", IntegerType(), False),
        StructField("pr_title", StringType(), True),
        StructField("pr_status", StringType(), False),
        StructField("pr_base_branch", StringType(), True),
        StructField("pr_type", StringType(), True),
        StructField("is_merged", BooleanType(), True),
        StructField("is_draft", BooleanType(), True),
        StructField("pr_additions", IntegerType(), True),
        StructField("pr_deletions", IntegerType(), True),
        StructField("id_author_user", StringType(), True),
        StructField("id_merged_by_user", StringType(), True),
        StructField("ts_created", TimestampType(), False),
        StructField("ts_merged", TimestampType(), True),
    ]
)

PR_CUSTOM_METRICS_SCHEMA = StructType(
    [
        StructField("id_pr", StringType(), False),
        StructField("pr_release_time_seconds", LongType(), True),
        StructField("pr_deploy_time_seconds", LongType(), True),
        StructField("ts_released", TimestampType(), True),
    ]
)

PR_TEAM_SCHEMA = StructType(
    [
        StructField("id_repo", StringType(), False),
        StructField("pr_key", IntegerType(), False),
        StructField("id_team", StringType(), False),
    ]
)

PR_COMMITS_SCHEMA = StructType(
    [
        StructField("commit_sha", StringType(), False),
        StructField("id_pr", StringType(), False),
        StructField("commit_author_name", StringType(), True),
        StructField("commit_author_email", StringType(), True),
        StructField("commit_authored_date", TimestampType(), True),
    ]
)

PR_COMMENTS_SCHEMA = StructType(
    [
        StructField("id", StringType(), False),
        StructField("id_pr", StringType(), False),
        StructField("account_id", StringType(), True),
        StructField("type", StringType(), True),
        StructField("status", StringType(), True),
        StructField("body", StringType(), True),
        StructField("created_date", TimestampType(), True),
    ]
)


# ---------- fixture data ----------

_ts = dt.datetime


@pytest.fixture
def pull_requests_df(spark):
    """10 PRs covering diverse scenarios from real production data."""
    rows = [
        # PR-A: multi-commit, multi-reviewer, with changes_requested, 10-day cycle
        ("pr-A", "repo-1", 3150, "chore/spark admin backend integration", "MERGED",
         "main", "type/feature", True, False, 2964, 1796,
         "user-1", "user-1", _ts(2026, 2, 24, 14, 40, 7), _ts(2026, 3, 6, 20, 48, 27)),
        # PR-B: single-commit, auto-approved bot release, 5 min cycle
        ("pr-B", "repo-2", 767, "chore(master): release 1.16.1", "MERGED",
         "main", "", True, False, 11, 4,
         "user-bot", "user-2", _ts(2026, 3, 9, 19, 51, 39), _ts(2026, 3, 9, 19, 56, 19)),
        # PR-C: no approval, self-merged, 19 hour cycle
        ("pr-C", "repo-3", 6581, "feat: add tracing plugin", "MERGED",
         "main", "", True, False, 481, 3,
         "user-3", "user-3", _ts(2026, 2, 12, 3, 47, 49), _ts(2026, 2, 12, 23, 14, 8)),
        # PR-D: fast single-commit PR, 2 approvals, 20 min cycle
        ("pr-D", "repo-3", 6174, "refactor: remove VisitAgentV2", "MERGED",
         "main", "", True, False, 9, 28,
         "user-4", "user-4", _ts(2026, 1, 20, 17, 7, 57), _ts(2026, 1, 20, 17, 28, 50)),
        # PR-E: 3-day cycle with diff comments (inline code review)
        ("pr-E", "repo-4", 23100, "feat(agents-api): enable vault", "MERGED",
         "main", "", True, False, 4, 0,
         "user-5", "user-5", _ts(2026, 3, 2, 13, 18, 46), _ts(2026, 3, 5, 18, 32, 54)),
        # PR-F: quick fix with 2 reviewers, 5-hour cycle
        ("pr-F", "repo-5", 13793, "fix: dead-end in close button", "MERGED",
         "main", "", True, False, 120, 18,
         "user-6", "user-6", _ts(2026, 1, 23, 19, 33, 38), _ts(2026, 1, 24, 1, 2, 38)),
        # PR-G: 10-day cycle, 2 commits, revisions with diff comments
        ("pr-G", "repo-6", 1359, "feat: add metric for fetch chat", "MERGED",
         "main", "", True, False, 16, 0,
         "user-7", "user-7", _ts(2026, 1, 12, 19, 18, 8), _ts(2026, 1, 22, 13, 49, 32)),
        # PR-H: quick merge, 2 approvals, 53 min cycle
        ("pr-H", "repo-7", 22479, "feat(sync-flow): log HTTP status", "MERGED",
         "main", "", True, False, 77, 1,
         "user-8", "user-8", _ts(2026, 3, 24, 13, 35, 23), _ts(2026, 3, 24, 14, 28, 8)),
        # PR-I: 6 reviewers (high engagement), 20-hour cycle
        ("pr-I", "repo-7", 21391, "fix: map photo rejection reasons", "MERGED",
         "main", "", True, False, 85, 37,
         "user-9", "user-9", _ts(2026, 3, 10, 16, 27, 31), _ts(2026, 3, 11, 12, 43, 56)),
        # PR-J: OPEN (not merged), no approval, 0 comments
        ("pr-J", "repo-1", 9999, "wip: experimental feature", "OPEN",
         "main", "type/feature", False, True, 10, 0,
         "user-1", None, _ts(2026, 3, 15, 10, 0, 0), None),
        # PR-K: merged with ONLY homesbot approval (no human approval)
        ("pr-K", "repo-1", 8888, "chore: config update", "MERGED",
         "main", "", True, False, 2, 0,
         "user-1", "user-1", _ts(2026, 3, 20, 10, 0, 0), _ts(2026, 3, 20, 10, 5, 0)),
        # PR-L: rework cycle — homesbot dismissed, human CR dismissed, then human approved
        ("pr-L", "repo-4", 23200, "refactor: update auth middleware", "MERGED",
         "main", "", True, False, 300, 50,
         "user-5", "user-5", _ts(2026, 3, 10, 10, 0, 0), _ts(2026, 3, 13, 14, 0, 0)),
    ]
    return spark.createDataFrame(rows, PR_SCHEMA)


@pytest.fixture
def pr_custom_metrics_df(spark):
    rows = [
        ("pr-A", 864000, 43200, _ts(2026, 3, 7, 8, 48, 27)),
        ("pr-B", 300, 60, _ts(2026, 3, 9, 19, 57, 19)),
        ("pr-D", 7200, 1800, _ts(2026, 1, 20, 18, 28, 50)),
    ]
    return spark.createDataFrame(rows, PR_CUSTOM_METRICS_SCHEMA)


@pytest.fixture
def pull_request_team_df(spark):
    rows = [
        ("repo-1", 3150, "team-growth"),
        ("repo-1", 3150, "team-platform"),
        ("repo-2", 767, "team-platform"),
        ("repo-3", 6581, "team-platform"),
        ("repo-3", 6174, "team-supply"),
        ("repo-4", 23100, "team-infra"),
        ("repo-5", 13793, "team-demand"),
        ("repo-6", 1359, "team-supply"),
        ("repo-7", 22479, "team-supply"),
        ("repo-7", 21391, "team-supply"),
        ("repo-1", 9999, "team-growth"),
        ("repo-1", 8888, "team-growth"),
        ("repo-4", 23200, "team-infra"),
    ]
    return spark.createDataFrame(rows, PR_TEAM_SCHEMA)


@pytest.fixture
def pull_request_commits_df(spark):
    """Commits linked to PRs. PR-J (open/draft) has no commits."""
    rows = [
        # PR-A: 3 commits over 10 days (truncated from 53 for test speed)
        ("sha-a1", "pr-A", "Dev One", "dev1@qa.com", _ts(2026, 2, 24, 14, 32, 41)),
        ("sha-a2", "pr-A", "Dev One", "dev1@qa.com", _ts(2026, 2, 28, 10, 0, 0)),
        ("sha-a3", "pr-A", "Dev One", "dev1@qa.com", _ts(2026, 3, 6, 16, 51, 45)),
        # PR-B: 1 commit, same second as PR creation (bot)
        ("sha-b1", "pr-B", "Bot", "bot@qa.com", _ts(2026, 3, 9, 19, 51, 38)),
        # PR-C: 2 commits
        ("sha-c1", "pr-C", "Dev Three", "dev3@qa.com", _ts(2026, 2, 12, 3, 44, 30)),
        ("sha-c2", "pr-C", "Dev Three", "dev3@qa.com", _ts(2026, 2, 12, 23, 1, 41)),
        # PR-D: 1 commit
        ("sha-d1", "pr-D", "Dev Four", "dev4@qa.com", _ts(2026, 1, 20, 17, 6, 15)),
        # PR-E: 1 commit
        ("sha-e1", "pr-E", "Dev Five", "dev5@qa.com", _ts(2026, 3, 2, 13, 18, 43)),
        # PR-F: 3 commits
        ("sha-f1", "pr-F", "Dev Six", "dev6@qa.com", _ts(2026, 1, 23, 19, 25, 13)),
        ("sha-f2", "pr-F", "Dev Six", "dev6@qa.com", _ts(2026, 1, 23, 20, 0, 0)),
        ("sha-f3", "pr-F", "Dev Six", "dev6@qa.com", _ts(2026, 1, 23, 21, 18, 40)),
        # PR-G: 2 commits
        ("sha-g1", "pr-G", "Dev Seven", "dev7@qa.com", _ts(2026, 1, 12, 19, 16, 13)),
        ("sha-g2", "pr-G", "Dev Seven", "dev7@qa.com", _ts(2026, 1, 21, 16, 37, 20)),
        # PR-H: 2 commits
        ("sha-h1", "pr-H", "Dev Eight", "dev8@qa.com", _ts(2026, 3, 24, 13, 35, 15)),
        ("sha-h2", "pr-H", "Dev Eight", "dev8@qa.com", _ts(2026, 3, 24, 13, 46, 0)),
        # PR-I: 2 commits (truncated from 6)
        ("sha-i1", "pr-I", "Dev Nine", "dev9@qa.com", _ts(2026, 3, 10, 16, 27, 1)),
        ("sha-i2", "pr-I", "Dev Nine", "dev9@qa.com", _ts(2026, 3, 11, 12, 7, 17)),
        # PR-K: 1 commit
        ("sha-k1", "pr-K", "Dev One", "dev1@qa.com", _ts(2026, 3, 20, 9, 59, 0)),
        # PR-L: 2 commits (rework cycle)
        ("sha-l1", "pr-L", "Dev Five", "dev5@qa.com", _ts(2026, 3, 10, 9, 50, 0)),
        ("sha-l2", "pr-L", "Dev Five", "dev5@qa.com", _ts(2026, 3, 12, 16, 0, 0)),
    ]
    return spark.createDataFrame(rows, PR_COMMITS_SCHEMA)


BOT_ATLANTIS = "github:GithubAccount:4:113528307"    # quintoandar-atlantis-v2[bot]
BOT_SONARQUBE = "github:GithubAccount:4:152914687"   # sonarqube-9-scan[bot]
BOT_HOMESBOT = "github:GithubAccount:4:54044254"     # homesbot (auto-approver)
BOT_ACTIONS = "github:GithubAccount:4:41898282"       # github-actions[bot]


@pytest.fixture
def pull_request_comments_df(spark):
    """Comments and reviews linked to PRs.
    Uses real bot account IDs so the SQL's bot_accounts CTE can identify them.
    Body text exercises the comment quality classification patterns:
      - ```suggestion blocks (GitHub code suggestions)
      - "should"/"could"/"consider"/"instead" (verbal suggestions)
      - "bug"/"error"/"fix" (bug flags)
      - "nit:" prefix (nitpicks)
      - Short questions with "?" (context-seeking)
    """
    rows = [
        # PR-A: bot comment, human review, human DIFF with suggestion block, human approval
        ("cmt-a1", "pr-A", BOT_ATLANTIS, "NORMAL", "",
         "Ran Plan for dir: infra/", _ts(2026, 2, 24, 14, 40, 32)),
        ("cmt-a2", "pr-A", "rev-1", "REVIEW", "COMMENTED",
         "", _ts(2026, 2, 25, 10, 0, 0)),
        ("cmt-a3", "pr-A", "rev-2", "DIFF", "",
         "```suggestion\n- val x = foo()\n+ val x = bar()\n```", _ts(2026, 2, 26, 14, 0, 0)),
        ("cmt-a4", "pr-A", "rev-1", "REVIEW", "APPROVED",
         "", _ts(2026, 3, 6, 18, 34, 22)),
        # PR-B: sonarqube bot + human approval (instant)
        ("cmt-b1", "pr-B", BOT_SONARQUBE, "NORMAL", "",
         "SonarQube analysis complete", _ts(2026, 3, 9, 19, 51, 44)),
        ("cmt-b2", "pr-B", "rev-3", "REVIEW", "APPROVED",
         "LGTM", _ts(2026, 3, 9, 19, 51, 44)),
        # PR-C: only bot comments (atlantis + sonarqube), no human review
        ("cmt-c1", "pr-C", BOT_ATLANTIS, "NORMAL", "",
         "Ran Plan for dir: infra/", _ts(2026, 2, 12, 3, 49, 4)),
        ("cmt-c2", "pr-C", BOT_SONARQUBE, "NORMAL", "",
         "SonarQube analysis complete", _ts(2026, 2, 12, 4, 0, 0)),
        ("cmt-c3", "pr-C", BOT_ACTIONS, "NORMAL", "",
         "Build passed", _ts(2026, 2, 12, 23, 10, 0)),
        # PR-D: github-actions bot + 2 human approvals
        ("cmt-d1", "pr-D", BOT_ACTIONS, "NORMAL", "",
         "Build passed", _ts(2026, 1, 20, 17, 9, 15)),
        ("cmt-d2", "pr-D", "rev-4", "REVIEW", "APPROVED",
         "Looks good", _ts(2026, 1, 20, 17, 23, 13)),
        ("cmt-d3", "pr-D", "rev-5", "REVIEW", "APPROVED",
         "", _ts(2026, 1, 20, 17, 25, 0)),
        # PR-E: bot + human approval after 1 day
        ("cmt-e1", "pr-E", BOT_SONARQUBE, "NORMAL", "",
         "SonarQube analysis complete", _ts(2026, 3, 2, 13, 19, 2)),
        ("cmt-e2", "pr-E", "rev-6", "REVIEW", "APPROVED",
         "", _ts(2026, 3, 3, 13, 6, 55)),
        # PR-F: bot + 2 human DIFF (suggestion + question) + 2 approvals
        ("cmt-f1", "pr-F", BOT_ATLANTIS, "NORMAL", "",
         "Ran Plan for dir: infra/", _ts(2026, 1, 23, 19, 34, 10)),
        ("cmt-f2", "pr-F", "rev-7", "DIFF", "",
         "You should consider using a guard clause instead of nesting this deep",
         _ts(2026, 1, 23, 19, 40, 0)),
        ("cmt-f3", "pr-F", "rev-8", "DIFF", "",
         "Why is this needed?", _ts(2026, 1, 23, 19, 45, 0)),
        ("cmt-f4", "pr-F", "rev-7", "REVIEW", "APPROVED",
         "", _ts(2026, 1, 23, 19, 53, 36)),
        ("cmt-f5", "pr-F", "rev-8", "REVIEW", "APPROVED",
         "", _ts(2026, 1, 23, 20, 10, 0)),
        # PR-G: bot + human diffs (nit + bug flag + plain) + reviews + approval
        ("cmt-g1", "pr-G", BOT_ATLANTIS, "NORMAL", "",
         "Ran Plan for dir: infra/", _ts(2026, 1, 12, 19, 18, 27)),
        ("cmt-g2", "pr-G", "rev-9", "DIFF", "",
         "nit: trailing whitespace here", _ts(2026, 1, 13, 10, 0, 0)),
        ("cmt-g3", "pr-G", "rev-9", "DIFF", "",
         "This looks like a bug — the counter resets on every iteration, which would always produce zero",
         _ts(2026, 1, 14, 10, 0, 0)),
        ("cmt-g4", "pr-G", "rev-9", "REVIEW", "COMMENTED",
         "Left a couple of notes", _ts(2026, 1, 15, 10, 0, 0)),
        ("cmt-g5", "pr-G", "rev-10", "REVIEW", "COMMENTED",
         "", _ts(2026, 1, 20, 10, 0, 0)),
        ("cmt-g6", "pr-G", "rev-10", "REVIEW", "APPROVED",
         "", _ts(2026, 1, 21, 17, 45, 23)),
        # PR-H: bot + 2 human approvals (no diff comments)
        ("cmt-h1", "pr-H", BOT_SONARQUBE, "NORMAL", "",
         "SonarQube analysis complete", _ts(2026, 3, 24, 13, 36, 0)),
        ("cmt-h2", "pr-H", "rev-11", "REVIEW", "APPROVED",
         "", _ts(2026, 3, 24, 13, 40, 56)),
        ("cmt-h3", "pr-H", "rev-12", "REVIEW", "APPROVED",
         "", _ts(2026, 3, 24, 13, 41, 0)),
        # PR-I: bot + 4 human DIFFs (suggestion, actionable, question, plain) + reviews + approvals
        ("cmt-i01", "pr-I", BOT_ATLANTIS, "NORMAL", "",
         "Ran Plan for dir: infra/", _ts(2026, 3, 10, 16, 35, 9)),
        ("cmt-i02", "pr-I", "rev-13", "DIFF", "",
         "```suggestion\n- return nil\n+ return fmt.Errorf(\"invalid state\")\n```",
         _ts(2026, 3, 10, 17, 0, 0)),
        ("cmt-i03", "pr-I", "rev-14", "DIFF", "",
         "You could use a constant here instead of this magic number",
         _ts(2026, 3, 10, 17, 30, 0)),
        ("cmt-i04", "pr-I", "rev-15", "DIFF", "",
         "What does this flag do?", _ts(2026, 3, 10, 18, 0, 0)),
        ("cmt-i05", "pr-I", "rev-16", "REVIEW", "COMMENTED",
         "", _ts(2026, 3, 10, 19, 0, 0)),
        ("cmt-i06", "pr-I", "rev-17", "REVIEW", "COMMENTED",
         "", _ts(2026, 3, 11, 10, 0, 0)),
        ("cmt-i07", "pr-I", "rev-18", "DIFF", "",
         "Looks fine to me", _ts(2026, 3, 11, 10, 30, 0)),
        ("cmt-i08", "pr-I", "rev-13", "REVIEW", "APPROVED",
         "", _ts(2026, 3, 11, 12, 15, 53)),
        ("cmt-i09", "pr-I", "rev-14", "REVIEW", "APPROVED",
         "", _ts(2026, 3, 11, 12, 20, 0)),
        # PR-K: homesbot auto-approval ONLY (no human approval)
        ("cmt-k1", "pr-K", BOT_SONARQUBE, "NORMAL", "",
         "SonarQube analysis complete", _ts(2026, 3, 20, 10, 0, 30)),
        ("cmt-k2", "pr-K", BOT_HOMESBOT, "REVIEW", "APPROVED",
         "", _ts(2026, 3, 20, 10, 1, 0)),
        # PR-L: rework cycle — dismissed reviews (most common pattern: 17% of PRs)
        ("cmt-l1", "pr-L", BOT_SONARQUBE, "NORMAL", "",
         "SonarQube analysis complete", _ts(2026, 3, 10, 10, 0, 30)),
        ("cmt-l2", "pr-L", BOT_HOMESBOT, "REVIEW", "APPROVED",
         "", _ts(2026, 3, 10, 10, 1, 0)),
        ("cmt-l3", "pr-L", BOT_HOMESBOT, "REVIEW", "DISMISSED",
         "", _ts(2026, 3, 10, 14, 0, 0)),
        ("cmt-l4", "pr-L", "rev-19", "REVIEW", "CHANGES_REQUESTED",
         "Needs refactoring before merge", _ts(2026, 3, 10, 15, 0, 0)),
        ("cmt-l5", "pr-L", "rev-19", "DIFF", "",
         "You should use the middleware chain instead of wrapping manually",
         _ts(2026, 3, 10, 15, 5, 0)),
        ("cmt-l6", "pr-L", "rev-19", "REVIEW", "DISMISSED",
         "", _ts(2026, 3, 12, 17, 0, 0)),
        ("cmt-l7", "pr-L", "rev-19", "REVIEW", "APPROVED",
         "", _ts(2026, 3, 13, 10, 0, 0)),
        # PR-J (OPEN): no comments
    ]
    return spark.createDataFrame(rows, PR_COMMENTS_SCHEMA)
