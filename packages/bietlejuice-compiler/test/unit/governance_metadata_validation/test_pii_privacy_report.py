import sys
from pathlib import Path

_COMPILER_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(_COMPILER_ROOT))

from scripts.governance_metadata_validation.pii_privacy_report import (  # noqa: E402
    humanize_warning,
    relative_repo_path,
)


class TestRelativeRepoPath:
    def test_strips_woodpecker_absolute_prefix(self):
        path = (
            "/woodpecker/src/github.com/quintoandar/bi-etl-ejuice/"
            "dags/agents/airtable/metadata/clean/activated.yml"
        )
        assert (
            relative_repo_path(path)
            == "dags/agents/airtable/metadata/clean/activated.yml"
        )


class TestHumanizeWarning:
    def test_pending_upstream_is_actionable(self):
        raw = (
            "/woodpecker/src/foo/dags/agents/x.yml column 'email': pending_upstream "
            "(datalake_raw.table.email has no privacy classification yet)"
        )
        text = humanize_warning(raw)
        assert "dags/agents/x.yml" in text
        assert "email" in text
        assert "Upstream" in text
        assert "RAE" in text

    def test_jsonpaths_unvalidated_is_actionable(self):
        raw = (
            "/woodpecker/src/foo/dags/agents/x.yml column 'payload': "
            "jsonPaths lineage is not validated yet"
        )
        text = humanize_warning(raw)
        assert "dags/agents/x.yml" in text
        assert "payload" in text
        assert "jsonPaths" in text
