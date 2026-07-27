#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#

import gzip as gz
import json
import os
import shutil
import sys
from abc import ABC, abstractmethod
from datetime import date, datetime, timedelta
from decimal import Decimal
from tempfile import NamedTemporaryFile

import unicodecsv as csv
from airflow.hooks.mysql_hook import MySqlHook
from airflow.hooks.postgres_hook import PostgresHook
from airflow.hooks.S3_hook import S3Hook
from airflow.models import BaseOperator
from airflow.plugins_manager import AirflowPlugin

PY3 = sys.version_info[0] == 3


class QuintoAndarDatabaseToS3Operator(BaseOperator, ABC):
    """
    Copy data from MySQL to S3 in JSON or CSV format.
    The JSON data files generated are newline-delimited

    :param bucket: The bucket to upload to.
    :type bucket: str
    :param filename: The filename to use as the object name when uploading
        to S3. A {} should be specified in the filename to allow the operator
        to inject file numbers in cases where the file is split due to size.
    :type filename: str
    :param s3_file_path: The S3 file path to save the object. The key(s) of
        the uploaded object(s) would be s3_file_path + filename(s)
    :type s3_file_path: str
    :param sql: The SQL to execute on the MySQL table. If this param is empty,
     the table param need to be set.
    :type sql: str
    :param table: The table to be extracted in the MySQL table. If this
    param is empty, the sql param need to be set. The sql param has takes precedence
    over this param.
    :type table: str
    :param approx_max_file_size_bytes: This operator supports the ability
        to split large table dumps into multiple files (see notes in the
        filename param docs above). This param allows developers to specify the
        file size of the splits.
    :type approx_max_file_size_bytes: long
    :param database_conn_id: Reference to a specific database connection.
    :type database_conn_id: str
    :param s3_conn_id: Reference to a specific S3 connection.
    :type s3_conn_id: str
    :param export_format: Desired format of files to be exported (json or csv).
    :type export_format: str
    :param gzip: If true, compact the file with gzip.
    :type gzip: bool
    :param retries: the number of retries that should be performed before
        failing the task
    :type retries: int
    :param retry_delay: delay between retries
    :type retry_delay: datetime.timedelta
    :param max_retry_delay: maximum delay interval between retries
    :type max_retry_delay: datetime.timedelta
    :param s3_acl_policy: String specifying the canned ACL policy for the file
        being uploaded to S3. If None, then the default policy is used. For a list
        of possible canned ACL policies, refer to the S3 developer documentation.
    :type s3_acl_policy: str
    """

    template_fields = ("bucket", "filename", "s3_file_path", "sql", "table")
    template_ext = (".sql",)
    ui_color = "#a0e08c"

    def __init__(
        self,
        bucket,
        filename,
        s3_file_path,
        sql=None,
        table=None,
        approx_max_file_size_bytes=1900000000,
        database_conn_id="mysql_default",
        s3_conn_id="aws_default",
        export_format="json",
        gzip=False,
        retries=3,
        retry_delay=timedelta(minutes=3),
        max_retry_delay=timedelta(minutes=3),
        s3_acl_policy=None,
        *args,
        **kwargs,
    ):
        if not sql and not table:
            raise ValueError(
                "m=__init__, msg=Both params `sql` and `table` are empty. You need to"
                "set one of them."
            )
        if not sql and table:
            sql = f"SELECT * FROM {table}"

        kwargs = {
            **kwargs,
            "retries": retries,
            "retry_delay": retry_delay,
            "max_retry_delay": max_retry_delay,
        }
        super().__init__(*args, **kwargs)

        self.sql = sql
        self.table = table
        self.bucket = bucket
        self.filename = filename
        self.s3_file_path = s3_file_path
        self.approx_max_file_size_bytes = approx_max_file_size_bytes
        self.database_conn_id = database_conn_id
        self.s3_conn_id = s3_conn_id
        self.export_format = export_format.lower()
        self.gzip = gzip
        self.s3_acl_policy = s3_acl_policy

    def execute(self, context):
        cursor = self._query()
        files_to_upload = self._write_local_data_files(cursor)

        for tmp_file in files_to_upload:
            tmp_file_handle = tmp_file.get("file_handle")
            tmp_file_handle.flush()

        if self.gzip:
            gzipped_files = self._compact_files_with_gzip(files_to_upload)
            self._upload_to_s3(gzipped_files)
            for file in gzipped_files:
                os.remove(file.get("file_name"))
        else:
            self._upload_to_s3(files_to_upload)

        # Close all temp file handles.
        for tmp_file in files_to_upload:
            tmp_file_handle = tmp_file.get("file_handle")
            tmp_file_handle.close()

    @abstractmethod
    def _query(self):
        """
        Queries the database and returns a cursor to the results.
        """

    def _write_local_data_files(self, cursor):
        """
        Takes a cursor, and writes results to local(s) file.

        :return: A dictionary where keys are file names to be used as object
            names in S3, and values are file handles to local files that
            contain the data for the S3 objects.
        """
        schema = list(map(lambda schema_tuple: schema_tuple[0], cursor.description))
        self.log.info(
            f"m=_write_local_data_files, schema={schema}, msg=got schema of the query"
            "result."
        )
        file_no = 0
        tmp_file_handle = NamedTemporaryFile(delete=True)
        if self.export_format == "csv":
            file_mime_type = "text/csv"
        else:
            file_mime_type = "application/json"
        files_to_upload = [
            {
                "file_name": self.filename.format(file_no),
                "file_handle": tmp_file_handle,
                "file_mime_type": file_mime_type,
            }
        ]

        if self.export_format == "csv":
            csv_writer = self._configure_csv_file(tmp_file_handle, schema)

        count = 0
        for row in cursor:
            count += 1
            # cast all data types to string
            row = self._convert_types(schema, row)

            if self.export_format == "csv":
                csv_writer.writerow(row)
            else:
                row_dict = dict(zip(schema, row))

                s = json.dumps(row_dict, sort_keys=True)
                if PY3:
                    s = s.encode("utf-8")
                tmp_file_handle.write(s)

                tmp_file_handle.write(b"\n")

            # Stop if the file exceeds the file size limit.
            if tmp_file_handle.tell() >= self.approx_max_file_size_bytes:
                file_no += 1
                tmp_file_handle = NamedTemporaryFile(delete=True)
                files_to_upload.append(
                    {
                        "file_name": self.filename.format(file_no),
                        "file_handle": tmp_file_handle,
                        "file_mime_type": file_mime_type,
                    }
                )

                if self.export_format == "csv":
                    csv_writer = self._configure_csv_file(tmp_file_handle, schema)

        self.log.info(f"m=_write_local_data_files, msg=the query returned {count} rows")

        return files_to_upload

    def _configure_csv_file(self, file_handle, schema):
        """Configure a csv writer with the file_handle and write schema
        as headers for the new file.
        """
        csv_writer = csv.writer(file_handle, encoding="utf-8", delimiter=",")
        csv_writer.writerow(schema)
        return csv_writer

    def _compact_files_with_gzip(self, files_to_upload):
        """
        Compact files with gzip
        """
        new_files = []
        for tmp_file in files_to_upload:
            new_file_name = tmp_file.get("file_name") + ".gz"

            with open(tmp_file.get("file_handle").name, "rb") as f_in:
                with gz.open(new_file_name, "wb") as f_out:
                    shutil.copyfileobj(f_in, f_out)
            new_files.append(
                {
                    "file_name": new_file_name,
                    "file_handle": f_out,
                    "file_mime_type": tmp_file.get("file_mime_type"),
                }
            )

        return new_files

    def _upload_to_s3(self, files_to_upload):
        """
        Upload all file splits to S3.
        """

        hook = S3Hook(aws_conn_id=self.s3_conn_id)
        for tmp_file in files_to_upload:
            hook.load_file(
                filename=tmp_file.get("file_handle").name,
                key="{}/{}".format(self.s3_file_path, tmp_file.get("file_name")),
                bucket_name=self.bucket,
                replace=True,
                acl_policy=self.s3_acl_policy,
            )

    @staticmethod
    def _convert_types(schema, row):
        """
        Takes a value from db, and converts it to a value that's safe for
        JSON/S3.
        """
        converted_row = []
        for col_name, col_val in zip(schema, row):
            if type(col_val) in (datetime, date):
                col_val = str(col_val)
            elif type(col_val) is Decimal:
                col_val = float(col_val)
            elif type(col_val) in (bytearray, bytes):
                col_val = str(col_val)
            converted_row.append(col_val)
        return converted_row


class QuintoAndarMySqlToS3Operator(QuintoAndarDatabaseToS3Operator):
    def _query(self):
        """
        Queries mysql and returns a cursor to the results.
        """
        mysql = MySqlHook(mysql_conn_id=self.database_conn_id)
        conn = mysql.get_conn()
        cursor = conn.cursor()
        cursor.execute(self.sql)
        return cursor


class QuintoAndarPostgresToS3Operator(QuintoAndarDatabaseToS3Operator):
    def _query(self):
        """
        Queries PostgreSQL and returns a cursor to the results.
        """
        postgresql = PostgresHook(postgres_conn_id=self.database_conn_id)
        conn = postgresql.get_conn()
        cursor = conn.cursor()
        cursor.execute(self.sql)
        return cursor


class QuintoAndarTransferDataPlugin(AirflowPlugin):
    name = "quintoandar_transfer_data"
    operators = [QuintoAndarMySqlToS3Operator, QuintoAndarPostgresToS3Operator]
