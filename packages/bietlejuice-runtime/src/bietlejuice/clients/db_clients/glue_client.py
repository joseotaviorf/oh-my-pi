"""
Client for the AWS Glue Data Catalog.

Wraps ``boto3.client('glue')`` with STS assume-role support for
cross-account access.  Adapted from the UC-Glue sync script.
"""

from __future__ import annotations

import os
from typing import Dict, List, Optional, Set

import boto3
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.clients.db_clients.db_client import DBClient

logger = QuintoAndarLogger("GlueClient")

_DEFAULT_REGION = "us-east-1"


class GlueClient(DBClient):
    """Thin wrapper around the boto3 Glue client.

    Supports cross-account access via STS ``AssumeRole``.  The role ARN
    is read from the ``GLUE_ASSUME_ROLE_ARN`` environment variable (set
    by Databricks cluster env vars or Airflow Variables).
    """

    def __init__(
        self,
        role_arn: Optional[str] = None,
        region: str = _DEFAULT_REGION,
    ):
        self._role_arn = role_arn or os.environ.get("GLUE_ASSUME_ROLE_ARN")
        self._region = region
        self._glue = None
        self._s3 = None
        self._lf = None
        self._assumed_creds = None

    @property
    def conn(self):
        """Return a ready-to-use ``boto3`` Glue client."""
        if self._glue is None:
            self._glue = self._build_client("glue")
        return self._glue

    @property
    def s3_client(self):
        """Return a ``boto3`` S3 client using the same credentials as Glue."""
        if self._s3 is None:
            self._s3 = self._build_client("s3")
        return self._s3

    @property
    def lakeformation(self):
        """Return a ``boto3`` Lake Formation client using the same credentials."""
        if self._lf is None:
            self._lf = self._build_client("lakeformation")
        return self._lf

    def _get_assumed_credentials(self) -> Optional[Dict]:
        """Return assumed-role credentials, caching across Glue/S3 clients."""
        if self._assumed_creds is not None:
            return self._assumed_creds
        if self._role_arn:
            logger.info(
                f"m=_get_assumed_credentials, msg=Assuming role {self._role_arn}"
            )
            sts = boto3.client("sts", region_name=self._region)
            self._assumed_creds = sts.assume_role(
                RoleArn=self._role_arn,
                RoleSessionName="bietlejuice-glue-sync",
            )["Credentials"]
        return self._assumed_creds

    def _build_client(self, service_name: str):
        creds = self._get_assumed_credentials()
        if creds:
            return boto3.client(
                service_name,
                region_name=self._region,
                aws_access_key_id=creds["AccessKeyId"],
                aws_secret_access_key=creds["SecretAccessKey"],
                aws_session_token=creds["SessionToken"],
            )
        return boto3.client(service_name, region_name=self._region)

    # -- DBClient interface --------------------------------------------------

    def get_records(self, query, parameters=None):
        raise NotImplementedError(
            "GlueClient does not support SQL queries. "
            "Use the dedicated methods instead."
        )

    def run(self, command, autocommit=False, parameters=None):
        raise NotImplementedError(
            "GlueClient does not support raw SQL commands. "
            "Use the dedicated methods instead."
        )

    # -- Lake Formation tag operations ---------------------------------------

    def database_has_data_contract_tag(self, database_name: str) -> bool:
        """Return True if the database has a ``data_contract_managed`` LF-tag."""
        response = self.lakeformation.get_resource_lf_tags(
            Resource={"Database": {"Name": database_name}},
            ShowAssignedLFTags=True,
        )
        for tag in response.get("LFTagOnDatabase", []):
            if tag.get("TagKey") == "data_contract_managed":
                return True
        return False

    def add_database_data_contract_tag(
        self, database_name: str, value: str = "unknown"
    ) -> None:
        """Apply ``data_contract_managed`` LF-tag to a Glue database.

        Raises ``RuntimeError`` when the Lake Formation response includes
        ``Failures`` so callers do not treat a rejected stamp as success.
        """
        response = self.lakeformation.add_lf_tags_to_resource(
            Resource={"Database": {"Name": database_name}},
            LFTags=[{"TagKey": "data_contract_managed", "TagValues": [value]}],
        )
        failures = (response or {}).get("Failures") or []
        if failures:
            raise RuntimeError(
                f"Lake Formation add_lf_tags_to_resource failed for "
                f"database={database_name}, tag=data_contract_managed, "
                f"value={value}, failures={failures}"
            )

    # -- Glue-specific operations --------------------------------------------

    def ensure_database(
        self,
        database_name: str,
        description: str = "",
    ) -> None:
        """Create a Glue database if it does not already exist."""
        try:
            self.conn.get_database(Name=database_name)
            logger.info(
                f"m=ensure_database, database={database_name}, "
                "msg=database already exists in Glue"
            )
        except self.conn.exceptions.EntityNotFoundException:
            logger.info(
                f"m=ensure_database, database={database_name}, "
                "msg=creating database in Glue"
            )
            self.conn.create_database(
                DatabaseInput={"Name": database_name, "Description": description}
            )

    def create_table(self, database_name: str, table_input: Dict) -> None:
        """Create a table in the Glue Data Catalog."""
        self.conn.create_table(DatabaseName=database_name, TableInput=table_input)

    def update_table(
        self,
        database_name: str,
        table_input: Dict,
        *,
        skip_archive: bool = True,
    ) -> None:
        """Update an existing table in the Glue Data Catalog.

        By default ``SkipArchive=True`` so Glue does not create a new
        TABLE_VERSION on every metadata update (see AWS Glue quotas).
        """
        self.conn.update_table(
            DatabaseName=database_name,
            TableInput=table_input,
            SkipArchive=skip_archive,
        )

    def delete_table(self, database_name: str, table_name: str) -> None:
        """Delete a table from the Glue Data Catalog."""
        try:
            self.conn.delete_table(DatabaseName=database_name, Name=table_name)
        except self.conn.exceptions.EntityNotFoundException:
            logger.info(
                f"m=delete_table, database={database_name}, "
                f"table={table_name}, msg=table not found in Glue, skipping"
            )

    def get_table(self, database_name: str, table_name: str) -> Optional[Dict]:
        """Retrieve a table from the Glue Data Catalog.

        Returns ``None`` if the table does not exist.
        """
        try:
            resp = self.conn.get_table(DatabaseName=database_name, Name=table_name)
            return resp.get("Table")
        except self.conn.exceptions.EntityNotFoundException:
            return None

    def get_table_names(self, database_name: str) -> List[str]:
        """List all table names in a Glue database."""
        names: List[str] = []
        paginator = self.conn.get_paginator("get_tables")
        for page in paginator.paginate(DatabaseName=database_name):
            for table in page.get("TableList", []):
                names.append(table["Name"])
        return names

    def list_table_version_ids(self, database_name: str, table_name: str) -> List[str]:
        """Return all Glue table version IDs for a table (oldest to newest)."""
        version_ids: List[str] = []
        paginator = self.conn.get_paginator("get_table_versions")
        for page in paginator.paginate(
            DatabaseName=database_name, TableName=table_name
        ):
            for version in page.get("TableVersions", []):
                version_ids.append(version["VersionId"])
        return sorted(version_ids, key=lambda version_id: int(version_id))

    def batch_delete_table_versions(
        self,
        database_name: str,
        table_name: str,
        version_ids: List[str],
    ) -> int:
        """Delete Glue table versions in batches of 100.

        Returns the number of versions successfully deleted.
        """
        if not version_ids:
            return 0

        batch_size = 100
        deleted_count = 0
        failures: List[Dict] = []
        for i in range(0, len(version_ids), batch_size):
            batch = version_ids[i : i + batch_size]
            response = self.conn.batch_delete_table_version(
                DatabaseName=database_name,
                TableName=table_name,
                VersionIds=batch,
            )
            errors = response.get("Errors", [])
            for err in errors:
                error_detail = err.get("ErrorDetail", {})
                logger.error(
                    f"m=batch_delete_table_versions, "
                    f"table={database_name}.{table_name}, "
                    f"version_id={err.get('VersionId')}, "
                    f"error_code={error_detail.get('ErrorCode')}, "
                    f"error_message={error_detail.get('ErrorMessage')}, "
                    "msg=table version deletion failed in Glue"
                )
            failures.extend(errors)
            deleted_count += len(batch) - len(errors)

        if failures:
            raise RuntimeError(
                f"Glue batch_delete_table_version failed for "
                f"{len(failures)} version(s) in "
                f"{database_name}.{table_name} "
                f"({deleted_count} deleted): "
                f"{[e.get('ErrorDetail', {}).get('ErrorCode') for e in failures]}"
            )

        return deleted_count

    def get_partition(
        self, database_name: str, table_name: str, values: List[str]
    ) -> Optional[Dict]:
        """Return a Glue partition if it exists, else ``None``."""
        try:
            resp = self.conn.get_partition(
                DatabaseName=database_name,
                TableName=table_name,
                PartitionValues=values,
            )
            return resp.get("Partition")
        except self.conn.exceptions.EntityNotFoundException:
            return None

    def get_partition_value_tuples(
        self, database_name: str, table_name: str
    ) -> Set[tuple]:
        """Return existing Glue partition values as hashable tuples."""
        values: Set[tuple] = set()
        paginator = self.conn.get_paginator("get_partitions")
        for page in paginator.paginate(
            DatabaseName=database_name, TableName=table_name
        ):
            for partition in page.get("Partitions", []):
                values.add(tuple(partition.get("Values", [])))
        return values

    def get_partitions(self, database_name: str, table_name: str) -> List[Dict]:
        """Return all Glue partitions for a table (full partition dicts)."""
        partitions: List[Dict] = []
        paginator = self.conn.get_paginator("get_partitions")
        for page in paginator.paginate(
            DatabaseName=database_name, TableName=table_name
        ):
            partitions.extend(page.get("Partitions", []))
        return partitions

    def get_database_names(self) -> List[str]:
        """List all Glue database names."""
        names: List[str] = []
        paginator = self.conn.get_paginator("get_databases")
        for page in paginator.paginate():
            for database in page.get("DatabaseList", []):
                names.append(database["Name"])
        return names

    def create_partition(
        self,
        database_name: str,
        table_name: str,
        partition_input: Dict,
    ) -> None:
        """Create a single Glue partition, skipping if it already exists."""
        try:
            self.conn.create_partition(
                DatabaseName=database_name,
                TableName=table_name,
                PartitionInput=partition_input,
            )
        except self.conn.exceptions.AlreadyExistsException:
            logger.info(
                f"m=create_partition, table={database_name}.{table_name}, "
                f"values={partition_input.get('Values')}, "
                "msg=partition already exists in Glue, skipping"
            )

    def batch_create_partition(
        self,
        database_name: str,
        table_name: str,
        partition_input_list: List[Dict],
    ) -> int:
        """Add partitions to a Glue table in batches of 100 (idempotent).

        Returns the number of partitions successfully created.
        """
        if not partition_input_list:
            return 0

        batch_size = 100
        created_count = 0
        for i in range(0, len(partition_input_list), batch_size):
            batch = partition_input_list[i : i + batch_size]
            try:
                response = self.conn.batch_create_partition(
                    DatabaseName=database_name,
                    TableName=table_name,
                    PartitionInputList=batch,
                )
                errors = response.get("Errors", [])
                if errors:
                    already_exists_count = 0
                    other_errors: List[Dict] = []
                    for err in errors:
                        error_detail = err.get("ErrorDetail", {})
                        if error_detail.get("ErrorCode") == "AlreadyExistsException":
                            already_exists_count += 1
                        else:
                            other_errors.append(err)

                    if already_exists_count > 0:
                        logger.info(
                            f"m=batch_create_partition, "
                            f"table={database_name}.{table_name}, "
                            f"already_exists_count={already_exists_count}, "
                            "msg=some partitions already existed in Glue"
                        )

                    if other_errors:
                        for err in other_errors:
                            partition_values = err.get("PartitionValues", [])
                            error_detail = err.get("ErrorDetail", {})
                            logger.error(
                                f"m=batch_create_partition, "
                                f"table={database_name}.{table_name}, "
                                f"partition_values={partition_values}, "
                                f"error_code={error_detail.get('ErrorCode')}, "
                                f"error_message={error_detail.get('ErrorMessage')}, "
                                "msg=partition creation failed in Glue"
                            )
                        raise RuntimeError(
                            f"Glue batch_create_partition failed for "
                            f"{len(other_errors)} partition(s) in "
                            f"{database_name}.{table_name}: "
                            f"{[e.get('ErrorDetail', {}).get('ErrorCode') for e in other_errors]}"
                        )

                    created_count += len(batch) - len(errors)
                else:
                    created_count += len(batch)

            except self.conn.exceptions.AlreadyExistsException:
                logger.info(
                    f"m=batch_create_partition, table={database_name}.{table_name}, "
                    "msg=batch contained existing partitions, falling back to singles"
                )
                for partition_input in batch:
                    self.create_partition(database_name, table_name, partition_input)
                    created_count += 1

        return created_count

    def batch_update_partition(
        self,
        database_name: str,
        table_name: str,
        entries: List[Dict],
    ) -> int:
        """Update Glue partitions in batches of 100.

        Each entry must match the Glue ``BatchUpdatePartition`` shape::

            {
                "PartitionValueList": [...],
                "PartitionInput": {...},
            }

        Every batch is attempted even when an earlier one reports errors: Glue
        applies the successful entries of a partially-failing batch, so aborting
        early would leave the remaining partitions untouched until a full retry.
        Failures are collected and raised once at the end, so the caller still
        fails loudly and sees every bad partition in a single run.

        Returns the number of partitions successfully updated.
        """
        if not entries:
            return 0

        batch_size = 100
        updated_count = 0
        failures: List[Dict] = []
        for i in range(0, len(entries), batch_size):
            batch = entries[i : i + batch_size]
            response = self.conn.batch_update_partition(
                DatabaseName=database_name,
                TableName=table_name,
                Entries=batch,
            )
            errors = response.get("Errors", [])
            for err in errors:
                partition_values = err.get("PartitionValues", [])
                error_detail = err.get("ErrorDetail", {})
                logger.error(
                    f"m=batch_update_partition, "
                    f"table={database_name}.{table_name}, "
                    f"partition_values={partition_values}, "
                    f"error_code={error_detail.get('ErrorCode')}, "
                    f"error_message={error_detail.get('ErrorMessage')}, "
                    "msg=partition update failed in Glue"
                )
            failures.extend(errors)
            updated_count += len(batch) - len(errors)

        if failures:
            raise RuntimeError(
                f"Glue batch_update_partition failed for "
                f"{len(failures)} partition(s) in "
                f"{database_name}.{table_name} "
                f"({updated_count} updated): "
                f"{[e.get('ErrorDetail', {}).get('ErrorCode') for e in failures]}"
            )

        return updated_count
