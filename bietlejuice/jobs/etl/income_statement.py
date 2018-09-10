# -*- coding: latin1 -*-
import string
import sys

import petl
from openpyxl import load_workbook

from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.wrappers.GoogleDrive.google_drive_api import GoogleDriveApi


def dowload_income_statement_workbook(file_name, file_path_destination='/tmp'):
    return GoogleDriveApi().download_file(file_name=file_name, file_path_destination=file_path_destination)


def get_inside_sales_workbook(file_name, file_path='/tmp', data_only=True):
    file_name = '{}/{}'.format(file_path, file_name)
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
    from datetime import datetime
    from dateutil.relativedelta import relativedelta

    args = sys.argv
    if len(args) > 1:
        start = args[1]
        end = args[2] if len(args) > 2 else args[1]

        date_start = datetime.strptime(start, '%Y%m')
        date_end = datetime.strptime(end, '%Y%m')

        append = False  # truncate table - 1st time
        date = date_start
        while date <= date_end:
            print 'Extracting Income Statement {} from Excel Worksheet...'.format(date)
            file_name, file_path_destination = dowload_income_statement_workbook(
                file_name='Financial Reports - {}{}.xlsx'.format(date.year, date.month),
                file_path_destination='/tmp'
            )
            if file_name and file_path_destination:
                wb = get_inside_sales_workbook(file_name=file_name, file_path=file_path_destination)
                sheet = wb['Income Statement']

                inside_sales_table = get_inside_sales_costs_table(sheet)
                photo_table = get_photo_costs_table(sheet)

                income_statement = petl.cat(inside_sales_table, photo_table)

                print 'Loading Income Statement {} on ODS...'.format(date)
                BaseETL.to_db(db_enum=EnumDB.BI_ODS,
                              data_table=income_statement,
                              table_name='income_statement',
                              append=append)
                print 'Income Statement {} loaded on ODS! - {}'.format(file_name, datetime.now())
                append = True  # append data on the next steps
            date += relativedelta(months=1)

    # move to lake
    BaseETL.dump_ODS_to_datalake('income_statement')
