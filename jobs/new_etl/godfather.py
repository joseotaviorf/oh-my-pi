from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger


class GodFather(object):
    SCHEMA = 'business'

    @staticmethod
    @logger
    def __get_table(table_name):
        return BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_godfather,
            query='select * from {};'.format(GodFather.SCHEMA, table_name)
        )

    @staticmethod
    @logger
    def to_s3(s3_bucket, table_name):
        table_data = GodFather.__get_table(table_name)
        BaseETL.to_s3(
            filename='{}_{}.csv'.format(GodFather.SCHEMA, table_name),
            data_table=table_data,
            bucket_folder_path='{}/raw/godfather/{}/{}'.format(s3_bucket, GodFather.SCHEMA, table_name),
            write_header=False
        )

    @staticmethod
    @logger
    def to_ods(table_name):
        athena_client = AthenaClient(s3_bucket='5a-datalake')
        a_df = athena_client.execute_query_and_return_dataframe("""
                                                                    select distinct
                                                                        eo.*,
                                                                        go.type,
                                                                        go.first_sent_at,
                                                                        go.last_sent_at,
                                                                        gt.type as topic_type
                                                                    from datalake_raw.ebdb_offer eo
                                                                    join datalake_raw.godfather_offer go
                                                                        on eo.godfatherid = go.id
                                                                    left join datalake_raw.godfather_topic gt
                                                                        on gt.offer_id = go.id
                                                                    ;
                                                                """
                                                                )

        BaseETL.dataframe_to_db(
            df=a_df,
            table_name=table_name,
            enum_db=EnumDb.BI_ODS,
            append=False
        )
