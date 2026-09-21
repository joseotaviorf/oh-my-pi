"""Unit tests for validate_emr_runtime_clients helpers."""

import sys
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from scripts.ci_cd.validate_emr_runtime_clients import (  # noqa: E402
    RELEVANT_STATUSES,
    RULE_BARE_DBUTILS,
    RULE_BARE_SPARK,
    RULE_BASE_SPARK_CONTEXT,
    RULE_DIRECT_METASTORE,
    RULE_SPARK_BUILDER,
    added_spark_jobs,
    check_source,
    collect_violations,
    is_scanned_path,
)


def rules(source: str):
    return [v.rule for v in check_source("dags/d/x/spark_jobs/job.py", source)]


class TestBareSpark:
    def test_unbound_module_global_is_flagged(self):
        source = "def run():\n    return spark.table('t')\n"
        assert rules(source) == [RULE_BARE_SPARK]

    def test_module_level_binding_from_spark_client_is_clean(self):
        source = (
            "from bietlejuice.clients.db_clients import SparkClient\n"
            "spark_client = SparkClient(app_name='j')\n"
            "spark = spark_client.conn\n"
            "def run():\n"
            "    return spark.table('t')\n"
        )
        assert rules(source) == []

    def test_function_parameter_is_clean(self):
        """Core-model jobs receive ``spark`` as a parameter -- not a bypass."""
        source = (
            "def create_core_model(self, spark, args):\n    return spark.sql('x')\n"
        )
        assert rules(source) == []

    def test_local_assignment_is_clean(self):
        source = (
            "def run(client):\n    spark = client.conn\n    return spark.table('t')\n"
        )
        assert rules(source) == []

    def test_global_declaration_binds_at_module_scope(self):
        source = (
            "def setup(client):\n"
            "    global spark\n"
            "    spark = client.conn\n"
            "def run():\n"
            "    return spark.table('t')\n"
        )
        assert rules(source) == []

    def test_store_context_is_not_a_read(self):
        source = "spark = None\n"
        assert rules(source) == []

    def test_reports_every_occurrence(self):
        source = "def run():\n    spark.table('a')\n    spark.table('b')\n"
        assert rules(source) == [RULE_BARE_SPARK, RULE_BARE_SPARK]


class TestBareDbutils:
    def test_unbound_dbutils_is_flagged(self):
        source = "def run(path):\n    return dbutils.fs.ls(path)\n"
        assert rules(source) == [RULE_BARE_DBUTILS]

    def test_base_dbutils_binding_is_clean(self):
        source = (
            "from bietlejuice.base.spark import BaseDBUtils\n"
            "dbutils = BaseDBUtils().get_dbutils()\n"
            "def run(path):\n"
            "    return dbutils.fs.ls(path)\n"
        )
        assert rules(source) == []

    def test_locally_derived_dbutils_is_clean(self):
        source = (
            "from bietlejuice.base.spark import BaseDBUtils\n"
            "def run(path):\n"
            "    dbutils = BaseDBUtils().get_dbutils()\n"
            "    return dbutils.fs.ls(path)\n"
        )
        assert rules(source) == []


class TestSparkBuilder:
    def test_builder_get_or_create_is_flagged(self):
        source = (
            "from pyspark.sql import SparkSession\n"
            "spark = SparkSession.builder.getOrCreate()\n"
        )
        assert rules(source) == [RULE_SPARK_BUILDER]

    def test_dotted_spark_session_is_flagged(self):
        source = (
            "import pyspark\nspark = pyspark.sql.SparkSession.builder.getOrCreate()\n"
        )
        assert rules(source) == [RULE_SPARK_BUILDER]

    def test_spark_session_type_annotation_is_clean(self):
        source = (
            "from pyspark.sql import SparkSession\n"
            "def run(spark: SparkSession):\n"
            "    return spark.sql('x')\n"
        )
        assert rules(source) == []


class TestBaseSparkContext:
    def test_session_attribute_is_flagged(self):
        source = (
            "from bietlejuice.base.spark import BaseSparkContext\n"
            "df = BaseSparkContext.spark.table('t')\n"
        )
        assert rules(source) == [RULE_BASE_SPARK_CONTEXT]

    def test_spark_context_attribute_is_flagged(self):
        source = (
            "from bietlejuice.base.spark import BaseSparkContext\n"
            "rdd = BaseSparkContext.sc.parallelize([1])\n"
        )
        assert rules(source) == [RULE_BASE_SPARK_CONTEXT]

    def test_base_dbutils_is_not_flagged(self):
        """``BaseDBUtils`` already dispatches to an EMR facade -- leave it alone."""
        source = (
            "from bietlejuice.base.spark import BaseDBUtils\n"
            "dbutils = BaseDBUtils().get_dbutils()\n"
        )
        assert rules(source) == []


class TestDirectMetastoreService:
    def test_direct_construction_is_flagged(self):
        source = (
            "from bietlejuice.services.metastore_services import SparkMetastoreService\n"
            "service = SparkMetastoreService(spark_client)\n"
        )
        assert rules(source) == [RULE_DIRECT_METASTORE]

    def test_service_factory_is_clean(self):
        source = (
            "service = MetastoreServiceFactory."
            "create_loader_metastore_service(spark_client)\n"
        )
        assert rules(source) == []

    def test_factory_wrapping_a_spark_service_is_exempt(self):
        """The sanctioned composite wiring passes the Spark service to the factory."""
        source = (
            "service = MetastoreServiceFactory."
            "create(SparkMetastoreService(spark_client))\n"
        )
        assert rules(source) == []

    def test_exemption_does_not_depend_on_visit_order(self):
        source = (
            "def build(client):\n"
            "    return MetastoreServiceFactory.create(SparkMetastoreService(client))\n"
            "other = SparkMetastoreService(client)\n"
        )
        assert rules(source) == [RULE_DIRECT_METASTORE]


class TestSyntaxErrors:
    def test_unparseable_file_is_skipped_not_crashed(self):
        assert check_source("dags/d/x/spark_jobs/job.py", "def broken(:\n") == []


class TestIsScannedPath:
    def test_spark_job_is_scanned(self):
        assert is_scanned_path("dags/growth/hubspot/spark_jobs/load_hubspot_raw.py")

    def test_init_is_skipped(self):
        assert not is_scanned_path("dags/growth/hubspot/spark_jobs/__init__.py")

    def test_dag_file_is_skipped(self):
        assert not is_scanned_path("dags/growth/hubspot/hubspot_dag.py")

    def test_package_file_is_skipped(self):
        assert not is_scanned_path(
            "packages/bietlejuice-runtime/src/bietlejuice/base/spark/base_spark.py"
        )

    def test_nested_subdirectory_is_skipped(self):
        assert not is_scanned_path("dags/growth/hubspot/spark_jobs/helpers/util.py")

    def test_non_python_is_skipped(self):
        assert not is_scanned_path("dags/growth/hubspot/spark_jobs/prod_conf.yml")


class TestAddedSparkJobs:
    def test_only_added_files_are_returned(self):
        """Modified files must not be gated -- that is what keeps legacy debt green."""
        changed = {
            "dags/a/b/spark_jobs/new.py": "A",
            "dags/a/b/spark_jobs/edited.py": "M",
            "dags/a/b/spark_jobs/gone.py": "D",
        }
        assert added_spark_jobs(changed) == ["dags/a/b/spark_jobs/new.py"]

    def test_added_non_spark_job_is_ignored(self):
        changed = {"dags/a/b/queries/raw/t.sql": "A", "dags/a/b/b_dag.py": "A"}
        assert added_spark_jobs(changed) == []

    def test_relevant_statuses_is_added_only(self):
        assert RELEVANT_STATUSES == frozenset({"A"})


@mock.patch("scripts.ci_cd.validate_emr_runtime_clients.GitService")
@mock.patch(
    "scripts.ci_cd.validate_emr_runtime_clients.resolve_diff_from_ref",
    return_value="origin/development",
)
def test_collect_violations_uses_resolved_base(mock_resolve, mock_git_service):
    git_service = mock_git_service.return_value
    git_service.get_modified_files_from_diff.return_value = {}

    assert collect_violations("feature-branch") == []

    mock_resolve.assert_called_once_with("feature-branch")
    git_service.get_modified_files_from_diff.assert_called_once_with(
        "origin/development", "HEAD"
    )
