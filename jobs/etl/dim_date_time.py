from jobs.base.base_etl import BaseETL, EnumDb

BaseETL.move_table('dim_date', EnumDb.LOCAL_DW, EnumDb.BI_DW)
print ('Dim Date Loaded!')

BaseETL.move_table('dim_time', EnumDb.LOCAL_DW, EnumDb.BI_DW)
print ('Dim Time Loaded!')

