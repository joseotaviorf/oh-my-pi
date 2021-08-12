import re
from datetime import datetime
from io import BytesIO

import petl
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.base.data_frame_service import DataFrameJsonService
from bietlejuice.jobs.composer.formatters.string_formatter import StringFormatter
from bietlejuice.jobs.etl import DATALAKE_QUERIES_DIR
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.google.google_sheets import GoogleSheetsClient

logger = QuintoAndarLogger("GoogleSheets")


class GoogleSheets(object):
    def __init__(self, s3_bucket, google_s_a_credentials, google_api_scope):
        self.s3_bucket = s3_bucket
        self.google_s_a_credentials = google_s_a_credentials
        self.google_api_scope = google_api_scope

    @logger(exclude=["google_sheets_file"])
    def move_sheets_data_to_destination(
        self,
        google_sheets_file,
        enumdb_destination,
        athena_client=None,
        csv=False,
        date_versioning=False,
        drop_table=True,
    ):
        if not google_sheets_file:
            raise ValueError("m=move_sheets_data_to_destination, msg=no files set.")

        gsheets = GoogleSheetsClient(self.google_s_a_credentials, self.google_api_scope)

        df_gsheets_raw = gsheets.get_dataframe_from_sheet(
            sheet_name=google_sheets_file["sheetName"],
            sheet_id=google_sheets_file["sheetId"],
        )
        if df_gsheets_raw is None:
            raise ValueError(
                "m=move_sheets_data_to_destination, sheet_id={}, sheet_name={}, "
                "msg=no data found in google sheets.".format(
                    google_sheets_file["sheetId"], google_sheets_file["sheetName"]
                )
            )

        snake_case_columns = StringFormatter.set_alphanumeric_snake_case(
            df_gsheets_raw.columns
        )
        df_gsheets_raw.rename(columns=snake_case_columns, inplace=True)

        df_gsheets = self._exclude_empty_column_labels(df_gsheets_raw)

        if enumdb_destination == EnumDB.QuintoAndar_datalake:
            self._move_df_to_datalake(
                df=df_gsheets,
                table_name=google_sheets_file["s3_path"]
                if "full_s3_path" not in google_sheets_file
                else google_sheets_file["fileName"],
                csv=csv,
                file_path=google_sheets_file["full_s3_path"]
                if "full_s3_path" in google_sheets_file
                else None,
                date_versioning=date_versioning,
            )

            if athena_client:
                GoogleSheets._create_athena_table(
                    df=df_gsheets,
                    schema_name="datalake_raw",
                    schema_folder="raw",
                    table_name=google_sheets_file["s3_path"],
                    bucket=self.s3_bucket,
                    athena_client=athena_client,
                )

        if enumdb_destination == EnumDB.BI_ODS:
            GoogleSheets._move_df_to_ods(
                df=df_gsheets,
                table_name=google_sheets_file["s3_path"],
                schema="gsheets",
                drop_table=drop_table,
            )

    @staticmethod
    @logger(exclude="old_columns")
    def _to_snake_case_columns(old_columns):
        _underscorer1 = re.compile(r"(\S)([A-Z][a-z]+)")
        _underscorer2 = re.compile("([a-z0-9])([A-Z])")

        new_columns = {}

        for old_column in old_columns:
            subbed = _underscorer1.sub(r"\1_\2", old_column)
            new_column = _underscorer2.sub(r"\1_\2", subbed).lower()
            new_column = new_column.replace(" ", "_")
            new_columns.update({old_column: new_column})

        return new_columns

    @staticmethod
    @logger(exclude="df")
    def _exclude_empty_column_labels(df):
        """
        Exclude columns with empty labels
        """
        select_labels_not_empty = list(
            filter(lambda column: column.strip() != "", df.columns)
        )
        return df[select_labels_not_empty]

    @logger(exclude="df")
    def _move_df_to_datalake(
        self, df, table_name, file_path=None, csv=False, date_versioning=False
    ):
        if csv:
            object_ = GoogleSheets.get_csv_io_object(df=df)
        else:
            object_ = GoogleSheets.get_json_io_object(df=df)

        full_file_path = (
            "{0}/gsheets/{1}/{1}.gz".format("raw", table_name)
            if not file_path
            else file_path
        )
        full_file_path = (
            full_file_path.format(date=datetime.now().strftime("%d-%m-%Y"))
            if date_versioning
            else full_file_path
        )

        BaseETL.obj_to_s3(
            obj_io=object_, bucket=self.s3_bucket, file_path=full_file_path
        )

        # clear obj allocation
        # only flushing does not clear the buffer
        object_.seek(0)
        object_.flush()

    @staticmethod
    @logger(exclude="df")
    def get_json_io_object(df):
        df_json_service = DataFrameJsonService(df=df)
        object_ = df_json_service.to_json_bytes()
        return object_

    @staticmethod
    @logger(exclude="df")
    def get_csv_io_object(df):
        object_ = BytesIO()
        df.to_csv(object_, index=False, sep=",", encoding="utf-8", header=True)
        return object_

    @staticmethod
    @logger(exclude="df")
    def _create_table_in_ods(df, table_name, schema):
        logger.info(
            "m=_create_table_in_ods, table_name={0}, schema={1}, msg=Creating table".format(
                table_name, schema
            )
        )
        BaseETL.create_table(
            conn=BaseETL.get_connection(db_enum=EnumDB.BI_ODS),
            table=petl.fromdataframe(df),
            tablename=table_name,
            schema=schema,
            sample=0,
        )

    @staticmethod
    @logger(exclude="df")
    def _move_df_to_ods(df, table_name, schema, drop_table):
        exists = BaseETL.table_exists(
            db_enum=EnumDB.BI_ODS, table_name=table_name, schema=schema
        )
        if not exists:
            GoogleSheets._create_table_in_ods(df, table_name, schema)
        else:
            if drop_table:
                logger.info(
                    "m=_move_df_to_ods, table_name={0}, schema={1}, msg=Dropping table".format(
                        table_name, schema
                    )
                )
                BaseETL.drop_table(
                    db_enum=EnumDB.BI_ODS, table_name=table_name, schema=schema
                )
                GoogleSheets._create_table_in_ods(df, table_name, schema)
            else:
                logger.info(
                    "m=_move_df_to_ods, table_name={0}, schema={1}, msg=Truncating table".format(
                        table_name, schema
                    )
                )
                BaseETL.truncate_table(
                    db_enum=EnumDB.BI_ODS, table_name=table_name, schema=schema
                )

        try:
            logger.info(
                "m=_move_df_to_ods, table_name={0},schema={1}, msg=Sending df to ods".format(
                    table_name, schema
                )
            )
            BaseETL.dataframe_to_ods(
                df=df,
                table_name='{}."{}"'.format(schema, table_name),
                append=False,
                encoding="UTF-8",
            )
        except Exception as e:
            raise RuntimeError(
                "m=_move_df_to_ods, table_name={0}, schema={1}, error={2}, "
                "msg=Problem in send df to ods".format(
                    table_name, schema, str(e.message)
                )
            )

    @staticmethod
    @logger(exclude="df")
    def _create_athena_table(
        df, schema_name, schema_folder, table_name, bucket, athena_client
    ):
        columns_definition = GoogleSheets._get_df_columns_definition(df)

        logger.info(
            "m=_create_athena_table, schema={0}, table_name={1}, msg=dropping table".format(
                schema_name, table_name
            )
        )
        athena_client.execute_query_and_wait_for_results(
            sql="drop table if exists {0}.{1}_{2};".format(
                schema_name, "gsheets", table_name
            )
        )

        logger.info(
            "m=_create_athena_table, schema={0}, table_name={1}, msg=creating table".format(
                schema_name, table_name
            )
        )
        athena_client.execute_file_query_and_wait_for_results(
            filename="{0}/gsheets/base_create_table.sql".format(DATALAKE_QUERIES_DIR),
            query_params={
                "schema_name": schema_name,
                "schema_folder": schema_folder,
                "table_name": table_name,
                "columns": columns_definition,
                "bucket": bucket,
            },
        )

        logger.info(
            "m=_create_athena_table, schema={0}, table_name=gsheets_{1}, msg=table created".format(
                schema_name, table_name
            )
        )

    @staticmethod
    @logger(exclude="df")
    def _get_df_columns_definition(df):
        column_list = df.columns.values.tolist()
        logger.info(
            "m=_get_df_columns_definition, column_list={0}".format(
                ", ".join(map(str, column_list))
            )
        )
        return " string,".join(map(str, column_list)) + " string"

