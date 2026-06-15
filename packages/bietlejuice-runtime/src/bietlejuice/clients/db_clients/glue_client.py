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
        self._assumed_creds = None

    @property
    def conn(self):
        """Return a ready-to-use ``boto3`` Glue client."""
        if self._glue is None:
            self._glue = self._build_glue_client()
        return self._glue

    @property
    def s3_client(self):
        """Return a ``boto3`` S3 client using the same credentials as Glue."""
        if self._s3 is None:
            self._s3 = self._build_s3_client()
        return self._s3

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

    def _build_glue_client(self):
        creds = self._get_assumed_credentials()
        if creds:
            return boto3.client(
                "glue",
                region_name=self._region,
                aws_access_key_id=creds["AccessKeyId"],
                aws_secret_access_key=creds["SecretAccessKey"],
                aws_session_token=creds["SessionToken"],
            )
        return boto3.client("glue", region_name=self._region)

    def _build_s3_client(self):
        creds = self._get_assumed_credentials()
        if creds:
            return boto3.client(
                "s3",
                region_name=self._region,
                aws_access_key_id=creds["AccessKeyId"],
                aws_secret_access_key=creds["SecretAccessKey"],
                aws_session_token=creds["SessionToken"],
            )
        return boto3.client("s3", region_name=self._region)

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

    def update_table(self, database_name: str, table_input: Dict) -> None:
        """Update an existing table in the Glue Data Catalog."""
        self.conn.update_table(DatabaseName=database_name, TableInput=table_input)

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
