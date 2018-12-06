from datetime import datetime

import petl
from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB

logger = QuintoAndarLogger('HouseStatusHistory')


class HouseStatusHistory(object):
    """
    Class responsible for extracting only significant status change history of houses; plus, applying some rules in
    the
    extraction.
    After getting data from EBDB, tables in ODS and data lake are populated.

    Note: The table name will follow the Data naming convention only when the code logic is updated
    """
    TABLE_NAME = 'imovel_status_history'

    EXTRACT_QUERY = """
            select
                *,
                now()
            from v_ImovelStatusHistory
            where id in (
                select distinct id
                from v_Imovel_AUD  a
                where a.date_status_changed >= '{}'
                  and a.date_status_changed < '{}'
            )
        """

    @staticmethod
    @logger
    def __get_max_loaded_date():
        max_date = BaseETL.from_db_query(
            db_enum=EnumDB.BI_ODS,
            query="select max(date_status_changed) from {}".format(HouseStatusHistory.TABLE_NAME)
        )

        if len(max_date) < 1:
            raise Exception('m=__get_max_loaded_date, msg=max_date is invalid')

        if len(max_date[1]) == 0:
            raise Exception('m=__get_max_loaded_date, msg=max_date[1] is empty')

        return max_date[1][0]

    @logger
    def load_data_into_ods_stg(self):
        max_loaded_date = HouseStatusHistory.__get_max_loaded_date()
        query_extract = HouseStatusHistory.EXTRACT_QUERY.format(
            max_loaded_date if max_loaded_date else '2012-01-01',
            datetime.today().date()
        )

        houses = self.__extract_houses_data(query_extract)

        logger.info(
            'm=load_data_into_ods, table_name={}, msg=bulk inserting into ODS'.format(HouseStatusHistory.TABLE_NAME))
        BaseETL.bulk_insert(
            table=houses,
            table_name='stg.{}'.format(HouseStatusHistory.TABLE_NAME),
            db_enum=EnumDB.BI_ODS,
            encoding='utf-8',
            append=False,
            commit=True
        )

    @logger
    def __extract_houses_data(self, query):
        logger.info('m=__extract_houses_data, msg=querying ebdb database')
        houses = BaseETL.from_db_query(
            db_enum=EnumDB.QuintoAndar_ebdb,
            query=query
        )

        logger.info('m=__extract_houses_data, msg=decoding table from latin-1')
        return BaseETL.decode_table(houses, 'latin-1')

    @logger
    def delete_duplicated_entries(self):
        delete_query = 'delete from {} where id in {}'.format(
            HouseStatusHistory.TABLE_NAME,
            list(petl.aggregate(HouseStatusHistory.TABLE_NAME, 'id')['id'])
        ).replace('[', '(').replace(']', ')')

        logger.info('m=delete_duplicated_entries, msg=deleting duplicated entries')
        BaseETL.execute_command(
            command=delete_query,
            db_enum=EnumDB.BI_ODS,
            encoding='utf-8',
            commit=True
        )

    @logger
    def load_data_into_ods(self):
        logger.info('m=load_data_into_ods, msg=moving data from stg to public table')
        BaseETL.execute_command(
            command='insert into public.{0} select * from stg.{0}'.format(HouseStatusHistory.TABLE_NAME),
            db_enum=EnumDB.BI_ODS,
            encoding='utf-8',
            commit=True
        )

    @logger
    def load_data_into_data_lake(self):
        logger.info('m=load_data_into_data_lake, msg=dumping data from ods to data lake')
        BaseETL.dump_ODS_to_datalake(
            table_name=HouseStatusHistory.TABLE_NAME,
            filename='property_status_history'
        )
