import boto3
import json
import os

from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils import QuintoAndarLogger
from botocore.exceptions import ClientError
from collections import OrderedDict
from pymongo import MongoClient
from abc import abstractmethod
from gzip import GzipFile
from io import BytesIO

from bietlejuice.jobs.etl.crm.tasks.unidecode_handler import UnidecodeHandler
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.base.new_base_etl import BaseETL
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR, DW_QUERIES_DIR

logger = QuintoAndarLogger("CRMTaskStatusHistories")


class CRMTaskStatusHistories(object):
    BUCKET_FOLDER_SUFFIXES = {
        "task_status": "crm/task_status_histories",
        "resolution": "crm/task_resolution_history"
    }
    S3_FILE_NAME = "data"
    TABLE_PARTITION_PARAM = "__PARTITION_DATE__"
    SCHEMA_NAMES = {"staging": "staging", "prod": "crm"}

    @logger
    def __init__(self, s3_bucket, execution_date, mongo_client_uri=None):
        self.s3_bucket = s3_bucket
        self.mongo_client = MongoClient(mongo_client_uri)
        self.execution_date_from = execution_date.replace(
            hour=0, minute=0, second=0, microsecond=0
        )
        self.partition_date = self.execution_date_from.strftime("%Y-%m-%d")
        self.execution_date_to = execution_date.replace(
            hour=23, minute=59, second=59, microsecond=59
        )

        data_acc_aws_access_key_id = os.environ.get("DATA_ACC_AWS_ACCESS_KEY_ID")
        data_acc_aws_secret_access_key = os.environ.get(
            "DATA_ACC_AWS_SECRET_ACCESS_KEY"
        )
        self.athena_client = AthenaClient(
            self.s3_bucket, data_acc_aws_access_key_id, data_acc_aws_secret_access_key
        )
        if data_acc_aws_access_key_id and data_acc_aws_secret_access_key:
            self.s3_resource = boto3.resource(
                "s3",
                aws_access_key_id=data_acc_aws_access_key_id,
                aws_secret_access_key=data_acc_aws_secret_access_key,
            )
        else:
            self.s3_resource = boto3.resource("s3")

    @abstractmethod
    def move_fact_to_staging(self):
        raise NotImplementedError("m=move_fact_to_staging, msg=method not implemented")

    @abstractmethod
    def move_dim_to_staging(self):
        raise NotImplementedError("m=move_dim_to_staging, msg=method not implemented")

    @abstractmethod
    def append_fact_to_dw(self):
        raise NotImplementedError("m=append_fact_to_dw, msg=method not implemented")

    @abstractmethod
    def append_dim_to_dw(self):
        raise NotImplementedError("m=append_dim_to_dw, msg=method not implemented")

    @abstractmethod
    def delete_staging_fact_entries(self):
        raise NotImplementedError(
            "m=delete_staging_fact_entries, msg=method not implemented"
        )

    @abstractmethod
    def delete_staging_dim_entries(self):
        raise NotImplementedError(
            "m=delete_staging_dim_entries, msg=method not implemented"
        )

    @logger
    def extract_and_load_data(self, batch_size=10000, **kwargs):
        incremental_filter = self.__add_incremental_constraints()

        db = self.mongo_client.tasks
        collection_gen = db.taskstatushistories.find(
            filter=incremental_filter
        ).batch_size(
            batch_size
        )

        total_count = collection_gen.count()
        logger.info(
            "m=extract_and_load_data, msg=processing {} rows".format(total_count)
        )

        self._save_to_s3(
            json_list=collection_gen,
            total_count=total_count
        )

    @logger
    def data_existence_check(self, bucket_type, **kwargs):
        if bucket_type not in ("raw", "clean"):
            logger.error(
                "m=data_existence_check, bucket_type={}, msg=invalid bucket type".format(
                    bucket_type
                )
            )
            raise ValueError

        file_path = "{}/{}/dt={}/{}.gz".format(
            bucket_type,
            CRMTaskStatusHistories.BUCKET_FOLDER_SUFFIXES["task_status"],
            self.partition_date,
            CRMTaskStatusHistories.S3_FILE_NAME
        )

        try:
            self.s3_resource.Object(self.s3_bucket, file_path).load()
            logger.info("m=data_existence_check, m=checked data")
        except ClientError as e:
            if e.response["Error"]["Code"] == "404":
                return False  # file does not exist
            raise  # something else had gone wrong

        return True

    @logger
    def upsert_partition(self, bucket_type, **kwargs):
        self._upsert_partition(
            bucket_type=bucket_type,
            bucket_folder_suffix=CRMTaskStatusHistories.BUCKET_FOLDER_SUFFIXES["task_status"],
            table_name="crm_task_status_histories",
        )

    @logger
    def move_to_clean(self, sql_file_name="create_task_status_histories_table.sql", **kwargs):
        _cols = OrderedDict(
            [
                ("id", str),
                ("v", str),
                ("histories", str)
            ]
        )

        self._move_to_clean(
            bucket_folder_suffix=CRMTaskStatusHistories.BUCKET_FOLDER_SUFFIXES["task_status"],
            sql_file_name=sql_file_name,
            r_cols=_cols,
            c_cols=_cols
        )

    @logger
    def move_tasks_resolution_history_to_clean(
            self, sql_file_name="create_task_resolution_history_table.sql", **kwargs
    ):
        _cols = OrderedDict(
            [
                ("id_task", str),
                ("id_action", str),
                ("id_assignee", str),
                ("id_user_action", str),
                ("id_house", str),
                ("id_rent_flow", str),
                ("id_origin", str),
                ("id_opened_by", str),
                ("id_tenant", str),
                ("id_negotiation", str),
                ("id_manager", str),
                ("id_owner", str),
                ("id_receiver", str),
                ("type", str),
                ("action_user_name", str),
                ("action_type", str),
                ("action_reason", str),
                ("task_status", str),
                ("resolved", str),
                ("tags", str),
                ("metadata", str),
                ("score_factor", str),
                ("receiver_name", str),
                ("comment", str),
                ("score", str),
                ("origin", str),
                ("receiver_type", str),
                ("description", str),
                ("phase", str),
                ("analyst_started_list", str),
                ("subject", str),
                ("visit_fup", str),
                ("v", str),
                ("task_user_resolve_hours", str),
                ("ts_action", str),
                ("ts_previous_action", str),
                ("ts_next_action", str),
                ("ts_created", str),
                ("ts_start", str),
                ("ts_completed", str),
                ("ts_visit", str),
                ("ts_silenced_until", str),
                ("ts_origin", str),
                ("ts_fup", str),
            ]
        )

        self._move_to_clean(
            bucket_folder_suffix=CRMTaskStatusHistories.BUCKET_FOLDER_SUFFIXES["resolution"],
            queries_folder_suffix=CRMTaskStatusHistories.BUCKET_FOLDER_SUFFIXES["task_status"],
            sql_file_name=sql_file_name,
            r_cols=_cols,
            c_cols=_cols,
            row_group_offsets=200
        )

    @logger
    def upsert_tasks_resolution_history_partition(self, bucket_type, **kwargs):
        self._upsert_partition(
            bucket_type=bucket_type,
            bucket_folder_suffix=CRMTaskStatusHistories.BUCKET_FOLDER_SUFFIXES["resolution"],
            table_name="crm_task_resolution_history",
        )

    @logger
    def __add_incremental_constraints(self):
        return{
            "history": {
                "$elemMatch": {
                    "date": {
                        "$lte": self.execution_date_to,
                        "$gte": self.execution_date_from,
                    }
                }
            }
        }

    @logger(exclude="json_list")
    def _save_to_s3(self, json_list, total_count):
        if not json_list or total_count == 0:
            logger.info("m=_save_to_s3, msg=no results")
            return

        gz_body = BytesIO()
        for _json in json_list:
            with GzipFile(fileobj=gz_body, mode="w") as fp:
                fp.write(
                    (
                        json.dumps(_json, ensure_ascii=False, cls=UnidecodeHandler)
                    ).encode("utf-8")
                )
                fp.write("\n")

        file_suffix = "raw/{}/dt={}/{}.gz".format(
            CRMTaskStatusHistories.BUCKET_FOLDER_SUFFIXES["task_status"],
            self.partition_date,
            CRMTaskStatusHistories.S3_FILE_NAME,
        )

        logger.info(
            "m=_save_to_s3, file_suffix={}, msg=sending to s3".format(file_suffix)
        )

        BaseETL.obj_to_s3(obj_io=gz_body, bucket=self.s3_bucket, file_path=file_suffix)
        logger.info("m=_save_to_s3, file_suffix={}, msg=sent to s3".format(file_suffix))

        gz_body.seek(0)
        gz_body.flush()

        logger.info("m=_save_to_s3, msg={} rows saved".format(total_count))

    @logger
    def _upsert_partition(
            self,
            bucket_type,
            bucket_folder_suffix,
            table_name,
            database_prefix="datalake",
            partition_name="dt",
    ):
        if bucket_type not in ("raw", "clean"):
            logger.error(
                "m=_upsert_partition, bucket_type={}, msg=invalid bucket type".format(
                    bucket_type
                )
            )
            raise ValueError

        self.athena_client.upsert_single_partition(
            bucket_folder_path="{}/{}/{}".format(
                self.s3_bucket, bucket_type, bucket_folder_suffix
            ),
            database="{}_{}".format(database_prefix, bucket_type),
            table=table_name,
            partition_name=partition_name,
            partition_value=self.partition_date,
        )

    @logger
    def _move_to_clean(
            self,
            bucket_folder_suffix,
            sql_file_name,
            r_cols,
            c_cols,
            queries_folder_suffix=None,
            row_group_offsets=500000
    ):
        key = "clean/{}/dt={}/{}.parq".format(
            bucket_folder_suffix, self.partition_date, CRMTaskStatusHistories.S3_FILE_NAME
        )

        query = BaseETL.get_query_from_file_name(
            "{}/{}/{}".format(
                DATALAKE_QUERIES_DIR,
                bucket_folder_suffix
                if queries_folder_suffix is None
                else queries_folder_suffix,
                sql_file_name
            )
        )

        self.athena_client.create_parquet_from_query(
            key=key,
            query=query.replace(CRMTaskStatusHistories.TABLE_PARTITION_PARAM, self.partition_date),
            raw_columns=r_cols,
            clean_columns=c_cols,
            row_group_offsets=row_group_offsets
        )

    def _move_dim_to_staging(
            self,
            table_name,
            queues=None,
            query_filename="create_staging_dim_history_table.sql",
            manual_task_workgroups=None,
            append_query_filename="append_dim_default_info.sql",
    ):
        self._move_to_staging(
            table_name=table_name,
            queues=queues,
            query_filename=query_filename,
            manual_task_workgroups=manual_task_workgroups,
            append_query_filename=append_query_filename,
        )

    @logger
    def _move_fact_to_staging(
            self,
            table_name,
            queues=None,
            query_filename="create_staging_fact_history_table.sql",
            manual_task_workgroups=None,
            append_query_filename="append_fact_default_info.sql",
    ):
        self._move_to_staging(
            table_name=table_name,
            queues=queues,
            query_filename=query_filename,
            manual_task_workgroups=manual_task_workgroups,
            append_query_filename=append_query_filename,
        )

    @logger
    def _move_to_staging(
            self,
            table_name,
            queues,
            query_filename,
            manual_task_workgroups,
            append_query_filename=None,
    ):
        query = BaseETL.get_query_from_file_name(
            "{}/{}/{}".format(
                DATALAKE_QUERIES_DIR,
                CRMTaskStatusHistories.BUCKET_FOLDER_SUFFIXES["task_status"],
                query_filename,
            )
        )

        # This section appends a series of filters on the types of tasks, considering if they are manual or not
        if queues is None:
            where_clause = """(trim(ct.type) = 'Manual' """

            if manual_task_workgroups:
                where_clause += """and regexp_extract(ct.metadata, 'workgroupId":"([^"]+)', 1) in ('{manual_workgroups}'))""".format(
                    manual_workgroups="', '".join(
                        workgroup for workgroup in manual_task_workgroups
                    )
                )
            else:
                where_clause += """and ct.metadata not like '%workgroupId%')"""
        else:
            where_clause = "trim(ct.type) in ('{types}')".format(
                types="', '".join(queue for queue in queues)
            )

            if manual_task_workgroups:
                where_clause = """({previous_clause} or (trim(ct.type) = 'Manual' and regexp_extract(ct.metadata, 'workgroupId":"([^"]+)', 1) in ('{manual_workgroups}')))""".format(
                    previous_clause=where_clause,
                    manual_workgroups="', '".join(
                        workgroup for workgroup in manual_task_workgroups
                    ),
                )

        empty = CRMTaskStatusHistories._is_table_empty(
            schema=CRMTaskStatusHistories.SCHEMA_NAMES["prod"], table_name=table_name
        )
        if not empty:
            where_clause = """{previous_clause} and dt = '{dt_partition}'""".format(
                previous_clause=where_clause, dt_partition=self.partition_date
            )

        final_query = query.replace("__WHERE_CLAUSE__", where_clause)

        if append_query_filename is not None:
            append_query = BaseETL.get_query_from_file_name(
                "{}/{}/{}".format(
                    DATALAKE_QUERIES_DIR,
                    CRMTaskStatusHistories.BUCKET_FOLDER_SUFFIXES["task_status"],
                    append_query_filename,
                )
            )
            final_query = "{}\n{}".format(final_query, append_query)

        df = self.athena_client.execute_query_and_return_dataframe(final_query)

        logger.info(
            "m=_move_to_staging, table_name={}, msg=sending df to DW staging".format(
                table_name
            )
        )
        BaseETL.dataframe_to_db(
            df=df,
            table_name="{}.{}".format(CRMTaskStatusHistories.SCHEMA_NAMES["staging"], table_name),
            enum_db=EnumDB.BI_DW,
            encoding="utf-8",
            append=False,
        )

    @logger
    def _append_dim_to_dw(self, table_name, query_filename="append_dim_table.sql"):
        self.__append_to_dw(
            schema=CRMTaskStatusHistories.SCHEMA_NAMES["prod"],
            table_name=table_name,
            query_filename=query_filename,
        )

    @logger
    def _append_fact_to_dw(
            self, table_name, query_filename="append_fact_default_table.sql"
    ):
        self.__append_to_dw(
            schema=CRMTaskStatusHistories.SCHEMA_NAMES["prod"],
            table_name=table_name,
            query_filename=query_filename,
        )

    @logger
    def __append_to_dw(self, schema, table_name, query_filename):
        upsert_query = BaseETL.get_query_from_file_name(
            "{}/staging/crm/{}".format(DW_QUERIES_DIR, query_filename)
        )

        empty = CRMTaskStatusHistories._is_table_empty(
            schema=CRMTaskStatusHistories.SCHEMA_NAMES["prod"], table_name=table_name
        )
        if empty:
            logger.info(
                "m=__append_to_dw, schema={}, table_name={}, msg=table already empty".format(
                    CRMTaskStatusHistories.SCHEMA_NAMES["prod"], table_name
                )
            )
        else:
            deletion_query = BaseETL.get_query_from_file_name(
                file_name="{}/crm/delete_old_entries.sql".format(DW_QUERIES_DIR)
            )

            logger.info(
                "m=__append_to_dw, schema={}, table_name={}, msg=deleting old entries".format(
                    CRMTaskStatusHistories.SCHEMA_NAMES["prod"], table_name
                )
            )
            BaseETL.execute_command(
                command=deletion_query.format(
                    table_name=table_name, partition_date=self.partition_date
                ),
                db_enum=EnumDB.BI_DW,
                encoding="utf-8",
                commit=True,
            )

            upsert_query = "{}\n where dt_partition = '{}';".format(
                upsert_query, self.partition_date
            )

        self.__append_into_dw(
            upsert_query=upsert_query.format(table_name=table_name),
            schema=schema,
            table_name=table_name,
        )

    @logger
    def __append_into_dw(self, upsert_query, schema, table_name):
        logger.info(
            "m=__append_into_dw, schema={}, table_name={}, msg=getting data from DW".format(
                schema, table_name
            )
        )
        table_data = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW, query=upsert_query, encoding="utf-8",
        )

        logger.info(
            "__upsert_into_dw, schema={}, table_name={}, msg=bulk inserting...".format(
                schema, table_name
            )
        )

        BaseETL.bulk_insert(
            table=table_data,
            table_name="{}.{}".format(schema, table_name),
            db_enum=EnumDB.BI_DW,
            encoding="utf-8",
        )

    @staticmethod
    @logger
    def _is_table_empty(schema, table_name):
        result = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW,
            query="select 1 from {}.{} limit 1".format(schema, table_name),
        )
        return len(result) == 1

    @logger
    def _delete_staging_entries(self, table_name):
        BaseETL.truncate_table(
            db_enum=EnumDB.BI_DW,
            schema=CRMTaskStatusHistories.SCHEMA_NAMES["staging"],
            table_name=table_name,
        )
