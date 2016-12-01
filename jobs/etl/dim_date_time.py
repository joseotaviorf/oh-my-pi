from jobs.base.base_etl import BaseETL, EnumDb

BaseETL.move_table('dim_date', EnumDb.BI_ODS, EnumDb.BI_DW)
print ('Dim Date Loaded!')

BaseETL.move_table('dim_time', EnumDb.BI_ODS, EnumDb.BI_DW)
print ('Dim Time Loaded!')

