# -*- coding: latin1 -*-
import os
import sys
import petl
import json
from datetime import datetime, date, timedelta
from jobs.base.base_etl import BaseETL, EnumDb
import tempfile
import string
from openpyxl import load_workbook

def get_inside_sales_workbook(fiscal_year, file_path='/tmp', name='income_statement', data_only=True):
    # TODO: download workbook to a temp path
    file_name='{}/{}_{}.xlsm'.format(file_path, name, fiscal_year)
    return load_workbook(filename=file_name, data_only=data_only)


def get_photo_costs_table(sheet):
    return get_values_from_income_statement_workbook(
        sheet,
        'Listing Photos',
        'listing_photos'
    )


def get_inside_sales_costs_table(sheet):
    return get_values_from_income_statement_workbook(
        sheet,
        'Inside Sales for Sourcing Properties',
        'inside_sales'
    )


def get_values_from_income_statement_workbook(sheet, cell_search_value, reference_cost_name):
    income_stat_values = list()
    income_stat_values.append(('cost_name', 'date', 'value'))
    for r in sheet.rows:
        if r[1].value == cell_search_value:
            for c in range(3, 15):  # JAN to DEC
                value = r[c].value
                income_stat_values.append(
                    (reference_cost_name, sheet['{}2'.format(string.uppercase[c:c + 1])].value, value)
                )
                print value
            break
    return income_stat_values


if __name__ == '__main__':
    args = sys.argv
    if len(args)>1:
        fiscal_year_start = args[1]
        fiscal_year_end = args[2] if len(args)>2 else args[1]

        append = False # truncate table - 1st time
        for fiscal_year in range(int(fiscal_year_start), int(fiscal_year_end)+1, 1):
            print 'Extracting Income Statement {} from Excel Worksheet...'.format(fiscal_year)
            wb = get_inside_sales_workbook(fiscal_year)
            sheet = wb['Income Statement']

            inside_sales_table = get_inside_sales_costs_table(sheet)
            photo_table = get_photo_costs_table(sheet)

            income_statement = petl.cat(inside_sales_table, photo_table)

            print 'Loading Income Statement {} on ODS...'.format(fiscal_year)
            BaseETL.to_db(db_enum=EnumDb.BI_ODS,
                          data_table=income_statement,
                          table_name='income_statement',
                          append=append)
            append = True  # append data on the next steps
