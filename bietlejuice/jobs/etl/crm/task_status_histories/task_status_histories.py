import boto3
import json
import os

from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils import QuintoAndarLogger
from botocore.exceptions import ClientError
from pymongo import MongoClient
from gzip import GzipFile
from io import BytesIO

from bietlejuice.jobs.etl.crm.tasks.unidecode_handler import UnidecodeHandler
from bietlejuice.jobs.base.new_base_etl import BaseETL

logger = QuintoAndarLogger("CRMTaskStatusHistories")


class CRMTaskStatusHistories(object):
    BUCKET_FOLDER_SUFFIXES = "crm/task_status_histories"
    S3_FILE_NAME = "data"

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

    @logger
    def extract_and_load_data(self, batch_size=10000):
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
    def data_existence_check(self, bucket_type):
        if bucket_type not in ("raw", "clean"):
            logger.error(
                "m=data_existence_check, bucket_type={}, msg=invalid bucket type".format(
                    bucket_type
                )
            )
            raise ValueError

        file_path = "{}/{}/dt={}/{}.gz".format(
            bucket_type,
            CRMTaskStatusHistories.BUCKET_FOLDER_SUFFIXES,
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
    def upsert_task_status_histories_partition(self, bucket_type):
        self._upsert_partition(
            bucket_type=bucket_type,
            bucket_folder_suffix=CRMTaskStatusHistories.BUCKET_FOLDER_SUFFIXES,
            table_name="crm_task_status_histories",
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
            CRMTaskStatusHistories.BUCKET_FOLDER_SUFFIXES,
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
