# -*- coding: latin1 -*-
import petl
from jobs.base.base_etl import BaseETL, EnumDb
import openpyxl


if __name__ == '__main__':

    emp_area = petl.fromxlsx(filename='/tmp/employees_area.xlsx')

    print ('Loading File on ODS...')
    BaseETL.to_db(db_enum=EnumDb.BI_ODS,
                  data_table=emp_area,
                  table_name='employees_area',
                  append=False)
