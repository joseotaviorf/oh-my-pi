from argparse import ArgumentParser

import pytest

from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)


def _parse(argv):
    parser = ArgumentParser()
    parser.add_argument("env")
    add_validation_target_args(parser)
    return parser.parse_args(argv)


class TestAddValidationTargetArgs:
    def test_defaults_to_none_without_flags(self):
        args = _parse(["prod"])

        assert args.target_database_name is None
        assert args.target_table_name is None

    def test_accepts_validation_flags(self):
        args = _parse(
            [
                "prod",
                "--target-database-name",
                "cluster_validation",
                "--target-table-name",
                "datalake_foo___bar",
            ]
        )

        assert args.target_database_name == "cluster_validation"
        assert args.target_table_name == "datalake_foo___bar"


class TestResolveDatalakeWriteTarget:
    def test_prod_path_when_no_validation_target(self):
        database, table, location = resolve_datalake_write_target(
            prod_database="datalake_foo",
            prod_table="bar",
            prod_location="s3a://bucket/enrich/foo/",
            bucket="bucket",
            target_database=None,
            target_table=None,
        )

        assert database == "datalake_foo"
        assert table == "bar"
        assert location == "s3a://bucket/enrich/foo/"

    def test_validation_path_when_flags_set(self):
        database, table, location = resolve_datalake_write_target(
            prod_database="datalake_foo",
            prod_table="bar",
            prod_location="s3a://bucket/enrich/foo/",
            bucket="prod-datalake",
            target_database="cluster_validation",
            target_table="datalake_foo___bar",
        )

        assert database == "cluster_validation"
        assert table == "datalake_foo___bar"
        assert (
            location
            == "s3a://prod-datalake/validation/cluster_validation/datalake_foo/"
        )

    @pytest.mark.parametrize(
        "target_database,target_table", [("", "t"), ("db", ""), ("", "")]
    )
    def test_empty_strings_treated_as_prod(self, target_database, target_table):
        database, table, location = resolve_datalake_write_target(
            prod_database="datalake_foo",
            prod_table="bar",
            prod_location="s3a://bucket/enrich/foo/",
            bucket="bucket",
            target_database=target_database or None,
            target_table=target_table or None,
        )

        assert database == "datalake_foo"
        assert table == "bar"
        assert location == "s3a://bucket/enrich/foo/"
