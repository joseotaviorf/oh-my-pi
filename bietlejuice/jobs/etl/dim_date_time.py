from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb

BaseETL.move_table_to_dw('dim_date', EnumDb.BI_ODS, EnumDb.BI_DW, append=False)
print ('Dim Date Loaded!')


BaseETL.move_table_to_dw('dim_time', EnumDb.BI_ODS, EnumDb.BI_DW, append=False)
print ('Dim Time Loaded!')
