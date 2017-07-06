from jobs.base.base_etl import BaseETL, EnumDb
import os
import petl
from qa_python_utils.aws.athena import AthenaClient
import sys


def move_to_datalake(schema_name, table_name):
    now = BaseETL.now()
    db = EnumDb.QuintoAndar_ebdb

    print("Start query: {}".format(now))

    # get data from table
    table = BaseETL.from_db_table(
        db_enum=db,
        table_name=table_name,
        generator=True
    ).addfield('dt_timestamp', now)

    print("To ODS: {}".format(now))

    table = BaseETL.decode_table(table, 'LATIN-1') # decode table from LATIN-1
    table = petl.convertall(table, unicode) # convert all fields to unicode

    # get all columns declared as BIT because we have a bug converting BIT columns on mysql
    bit_columns = petl.select(BaseETL.get_columns_schema(EnumDb.QuintoAndar_ebdb, table_name, schema_name, False),
                              lambda rec: rec.DATA_TYPE == 'bit')
    table = petl.convert(table, tuple(bit_columns['COLUMN_NAME']), {u'\x00': u'0', u'\x01': u'1'})

    # compact all table values into a gzip
    df_table = petl.todataframe(table)
    gz = BaseETL.convert_dataframe_to_json_gzip(df_table)

    # move to s3
    file_path = 'raw/{0}/{1}/{1}.gz'.format(schema_name, table_name)
    BaseETL.obj_to_s3(
        obj_io=gz,
        bucket=bucket_datalake,
        file_path=file_path
    )
    print ("{} moved to Datalake!".format(table_name))


def get_type_conversion_dict():
    conversions_table = BaseETL.from_db_query(
        db_enum=EnumDb.QuintoAndar_ebdb,
        query="""
            select 
                distinct	DATA_TYPE,
                case  
                    when DATA_TYPE in ('bigint', 'smallint', 'double', 'timestamp', 'int') then DATA_TYPE
                    when DATA_TYPE in ('datetime', 'time') then 'timestamp'
                    when DATA_TYPE in ('bit', 'tinyint') then 'smallint'
                    when DATA_TYPE in ('float', 'decimal', 'numeric') then 'double'
                    else 'string' 
                end as ret
            from information_schema.COLUMNS
        """
    )
    conversions_table.pop(0)
    conversions = {}
    for k, v in conversions_table:
        conversions[k] = v
    return conversions


def create_external_table(bucket_datalake, database_name, schema_name, table_name, conv):
    columns = BaseETL.get_columns_schema(EnumDb.QuintoAndar_ebdb, table_name, schema_name)
    c = AthenaClient(bucket_datalake)
    c.execute_query_and_wait_for_results('drop table if exists {}.{}_{};'.format(database_name, schema_name, table_name))

    command = 'CREATE EXTERNAL TABLE {}.{}_{}(\n'.format(database_name ,schema_name, table_name)
    for column, original_type in columns:
        command += '\t{} {},\n'.format(column, conv[original_type])
    command = command[:-2] #remove last comma
    command += """) row format serde 'org.openx.data.jsonserde.JsonSerDe' location
    's3://{}/raw/{}/{}/';""".format(bucket_datalake, schema_name, table_name)

    c.execute_query_and_wait_for_results(command)


def get_table_names(skip_header=True):
    sql_tables = """
    select TABLE_NAME
    from information_schema.TABLES
    where TABLE_SCHEMA = '{}'
    and TABLE_TYPE = 'BASE TABLE'    
""".format(schema_name)
    table_names = BaseETL.from_db_query(
        db_enum=EnumDb.QuintoAndar_ebdb,
        query=sql_tables
    )
    if skip_header:
        table_names.pop(0)  # remove header
    return table_names


if __name__ == "__main__":
    args = sys.argv
    schema_name = 'ebdb'
    athena_db = 'datalake_raw'
    bucket_datalake = os.environ['bi-datalake-s3-bucket']
    table_names = get_table_names()

    if len(args) > 1:
        if args[1] == 'MOVE':
            for table_name in table_names:
                move_to_datalake(schema_name, table_name[0])
        elif args[1] == 'CREATE_TABLES':
            conversions = get_type_conversion_dict()
            for table_name in table_names:
                create_external_table(bucket_datalake, athena_db, schema_name, table_name[0], conversions)
