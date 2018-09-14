from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB

BaseETL.move_table_to_dw('dim_date', EnumDB.BI_ODS, EnumDB.BI_DW, append=False)
print ('Dim Date Loaded!')

BaseETL.move_table_to_dw('dim_time', EnumDB.BI_ODS, EnumDB.BI_DW, append=False)
print ('Dim Time Loaded!')
