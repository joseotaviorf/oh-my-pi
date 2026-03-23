"""
Client for the AWS Glue Data Catalog.

Wraps ``boto3.client('glue')`` with STS assume-role support for
cross-account access.  Adapted from the UC-Glue sync script.
"""

from __future__ import annotations

import os
from typing import Dict, List, Optional

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

    @property
    def conn(self):
        """Return a ready-to-use ``boto3`` Glue client."""
        if self._glue is None:
            self._glue = self._build_glue_client()
        return self._glue

    def _build_glue_client(self):
        if self._role_arn:
            logger.info(f"m=_build_glue_client, msg=Assuming role {self._role_arn}")
            sts = boto3.client("sts", region_name=self._region)
            creds = sts.assume_role(
                RoleArn=self._role_arn,
                RoleSessionName="bietlejuice-glue-sync",
            )["Credentials"]
            return boto3.client(
                "glue",
                region_name=self._region,
                aws_access_key_id=creds["AccessKeyId"],
                aws_secret_access_key=creds["SecretAccessKey"],
                aws_session_token=creds["SessionToken"],
            )
        return boto3.client("glue", region_name=self._region)

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

    def batch_create_partition(
        self,
        database_name: str,
        table_name: str,
        partition_input_list: List[Dict],
    ) -> None:
        """Add partitions to a Glue table in batches of 100."""
        batch_size = 100
        for i in range(0, len(partition_input_list), batch_size):
            batch = partition_input_list[i : i + batch_size]
            self.conn.batch_create_partition(
                DatabaseName=database_name,
                TableName=table_name,
                PartitionInputList=batch,
            )
