from jobs.base.base_etl import BaseETL, EnumDb, petl


list_users = BaseETL.from_db_query(
    db_enum=EnumDb.QuintoAndar_ebdb,
    query='call ebdb.list_usuario();')

BaseETL.to_db(
    db_enum=EnumDb.BI_ODS,
    data_table=list_users,
    table_name='usuario',
    append=False,
    create=False
)
