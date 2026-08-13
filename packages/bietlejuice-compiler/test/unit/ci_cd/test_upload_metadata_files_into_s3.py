import yaml

from scripts.ci_cd import upload_metadata_files_into_s3 as u
from scripts.services.metadata_file_info import MetadataFileInfo


def _make_file_info(
    tmp_path, declaration, table="my_table", metadata_domain=None, subdir=None
):
    """Create a fake DAG dir (+ optional declaration) and a MetadataFileInfo whose
    local_path points at <dag_dir>/metadata/<layer>[/<subdir>]/<table>.yml.

    ``dags/`` is part of the path because the DAG-dir regex anchors on it."""
    dag_dir = tmp_path / "dags" / "my_domain" / "my_dag"
    metadata_dir = dag_dir / "metadata" / "layer"
    if subdir is not None:
        metadata_dir = metadata_dir / subdir
    metadata_dir.mkdir(parents=True, exist_ok=True)
    if declaration is not None:
        (dag_dir / "my_dag_declaration.yml").write_text(yaml.safe_dump(declaration))
    local_path = metadata_dir / f"{table}.yml"
    if metadata_domain is not None:
        local_path.write_text(yaml.safe_dump({"domain": metadata_domain}))
    return MetadataFileInfo(
        local_path=str(local_path),
        table_name=table,
        database_name="my_schema",
        has_documentation=True,
    )


class TestResolvePlatformsForFile:
    def test_regular_workflow_includes_trino(self, tmp_path):
        fi = _make_file_info(
            tmp_path, {"workflow": {"type": "enrich", "has_hive_sync": True}}
        )
        assert u.resolve_platforms_for_file(fi) == ["databricks", "glue", "trino"]

    def test_core_model_excludes_trino(self, tmp_path):
        fi = _make_file_info(tmp_path, {"workflow": {"type": "core_model"}})
        assert u.resolve_platforms_for_file(fi) == ["databricks", "glue"]

    def test_table_customization_overrides_workflow(self, tmp_path):
        fi = _make_file_info(
            tmp_path,
            {
                "workflow": {
                    "type": "enrich",
                    "has_hive_sync": True,
                    "tables_customization": {"my_table": {"has_hive_sync": False}},
                }
            },
        )
        assert u.resolve_platforms_for_file(fi) == ["databricks", "glue"]

    def test_query_view_uses_sync(self, tmp_path):
        fi = _make_file_info(
            tmp_path,
            {"workflow": {"type": "query_view", "sync": ["databricks", "trino"]}},
        )
        assert u.resolve_platforms_for_file(fi) == ["databricks", "trino"]

    def test_missing_declaration_returns_none(self, tmp_path):
        fi = _make_file_info(tmp_path, None)
        assert u.resolve_platforms_for_file(fi) is None

    def test_nested_metadata_subdir_still_resolves(self, tmp_path):
        # metadata/<layer>/<subdir>/<table>.yml — the nested form that broke the
        # old dirname()-counting derivation (it landed on metadata/, missing the
        # declaration). The regex anchors on dags/<domain>/<dag>/ regardless.
        fi = _make_file_info(
            tmp_path,
            {"workflow": {"type": "enrich", "has_hive_sync": True}},
            subdir="nested",
        )
        assert u.resolve_platforms_for_file(fi) == ["databricks", "glue", "trino"]


class TestGenerateDocumentationPayload:
    def test_includes_platforms_when_resolved(self, tmp_path):
        fi = _make_file_info(
            tmp_path, {"workflow": {"type": "enrich", "has_hive_sync": True}}
        )
        assert u.generate_documentation_payload(fi) == {
            "vendor": ["datahub"],
            "database_name": "my_schema",
            "table_name": "my_table",
            "platforms": ["databricks", "glue", "trino"],
        }

    def test_omits_platforms_when_no_declaration(self, tmp_path):
        fi = _make_file_info(tmp_path, None)
        payload = u.generate_documentation_payload(fi)
        assert "platforms" not in payload
        assert payload == {
            "vendor": ["datahub"],
            "database_name": "my_schema",
            "table_name": "my_table",
        }

    def test_includes_datahub_domain_urn_when_mapped(self, tmp_path):
        fi = _make_file_info(tmp_path, None, metadata_domain="People")
        payload = u.generate_documentation_payload(fi)
        assert payload["datahub_domain_urn"] == "urn:li:domain:people-domain"

    def test_omits_datahub_domain_urn_when_unmapped(self, tmp_path):
        fi = _make_file_info(tmp_path, None, metadata_domain="Cross")
        payload = u.generate_documentation_payload(fi)
        assert "datahub_domain_urn" not in payload

    def test_includes_subdomain_urn_for_broker_xp(self, tmp_path):
        fi = _make_file_info(tmp_path, None, metadata_domain="Broker XP")
        payload = u.generate_documentation_payload(fi)
        assert (
            payload["datahub_domain_urn"] == "urn:li:domain:growth-brokerxp-subdomain"
        )
