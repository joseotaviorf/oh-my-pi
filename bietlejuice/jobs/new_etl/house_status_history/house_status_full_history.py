from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.new_etl import ODS_QUERIES_DIR

logger = QuintoAndarLogger('HouseStatusFullHistory')


class HouseStatusFullHistory(object):
    """
    Class responsible for extracting the full status change history of houses; plus, applying some rules in the
    extraction.
    After getting data from EBDB, tables in ODS and data lake are populated.

    Note: The table name will follow the Data naming convention only when the code logic is updated
    """

    TABLE_NAME = 'imovel_status_full_history'

    def __truncate_ods_table(self):
        BaseETL.truncate_table(
            db_enum=EnumDB.BI_ODS,
            table_name=HouseStatusFullHistory.TABLE_NAME
        )

    @staticmethod
    @logger
    def __get_ids_count():
        ids_count = BaseETL.from_db_query(
            db_enum=EnumDB.BI_ODS,
            query='select count(distinct id) from imovel_status_history'
        )

        if len(ids_count) < 1:
            raise Exception('m=__get_ids_count, msg=ids_count is invalid')

        if len(ids_count[1]) == 0:
            raise Exception('m=__get_ids_count, msg=ids_count[1] is empty')

        return ids_count[1][0]

    @logger
    def load_data_into_ods(self):
        insert_query = BaseETL.get_query_from_file_name(
            '{}/house_status_history/house_status_full_history_insert.sql'.format(ODS_QUERIES_DIR))

        ids_count = HouseStatusFullHistory.__get_ids_count()

        offset = 0
        offset_inc = 1000
        while offset <= ids_count:
            logger.info('m=load_data_into_ods, offset={}'.format(offset))

            logger.info('m=load_data_into_ods, table_name={}, msg=inserting into ods table'.format(
                HouseStatusFullHistory.TABLE_NAME))
            BaseETL.execute_command(
                db_enum=EnumDB.BI_ODS,
                command=insert_query.format(ods_table_name=HouseStatusFullHistory.TABLE_NAME,
                                            offset=offset,
                                            offset_increment=offset_inc),
                encoding='utf-8',
                commit=True
            )

            logger.info('m=load_data_into_ods, msg=data successfully inserted into ods')
            offset += offset_inc

    @logger
    def load_data_into_data_lake(self, s3_bucket):
        logger.info('m=load_data_into_data_lake, msg=dumping data from ods to data lake')
        BaseETL.dump_ods_to_datalake(
            table_name=HouseStatusFullHistory.TABLE_NAME,
            s3_bucket=s3_bucket,
            filename='property_status_full_history'
        )
