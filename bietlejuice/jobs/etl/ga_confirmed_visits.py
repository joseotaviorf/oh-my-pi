# -*- coding: latin1 -*-
import sys
from datetime import datetime, timedelta

from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb
from bietlejuice.jobs.base.base_ga import BaseGA


class GAConfirmedVisits(BaseGA):

    def __init__(self, account_name, property_name, profile_name):
        super(GAConfirmedVisits, self).__init__(account_name, property_name, profile_name)
        self.table_name = 'ga_confirmed_visits'

    def get(self, start_date, end_date):
        return self.execute_query(
            {
                "start_date": start_date,
                "end_date": end_date,
                "metrics": "ga:goal2Starts,ga:goal10Starts,ga:goal2Completions,ga:goal10Completions,ga:goal2Value,ga:goal10Value,ga:goal2ConversionRate,ga:goal10ConversionRate,ga:searchGoal2ConversionRate,ga:searchGoal10ConversionRate",
                "dimensions": "ga:campaign,ga:sourceMedium,ga:operatingSystem,ga:mobileDeviceModel,ga:mobileDeviceMarketingName,ga:deviceCategory,ga:date",
                "samplingLevel": "HIGHER_PRECISION",
                "sort": "ga:date,ga:sourceMedium,ga:campaign,ga:deviceCategory"
            }
        )


def load_ods():
    min_date = (datetime.today() - timedelta(days=7)).strftime('%Y%m%d')
    ga = GAConfirmedVisits(
        'QuintoAndar',
        'QuintoAndar - Tracking GTM',
        '1- Prod (Tracking GTM)'
    )

    create_table = ga.get_flag_create_table(EnumDb.BI_ODS, ga.table_name)

    count = 0
    if not create_table:
        count = BaseETL.get_table_count(EnumDb.BI_ODS, ga.table_name)
        BaseETL.execute_command(
            command="DELETE from {} where date >= '{}'".format(ga.table_name, min_date),
            db_enum=EnumDb.BI_ODS,
            commit=True
        )

    initial = count == 0
    start_date = "2016-01-01" if initial else "7daysAgo"
    end_date = GAConfirmedVisits.add_date_str(start_date, 7) if initial else "today"

    while end_date:
        result, contains_sampling_data = ga.get(start_date, end_date)
        print('{} - Sampling Data: {}'.format(ga.ga.property_name, contains_sampling_data))
        BaseETL.to_db(
            db_enum=EnumDb.BI_ODS,
            data_table=result,
            table_name=ga.table_name,
            append=True,
            create=create_table,
            encoding='utf8'
        )
        create_table = False

        if initial:
            start_date = GAConfirmedVisits.add_date_str(end_date, 1)
            end_date = GAConfirmedVisits.add_date_str(start_date, 7)

        if end_date == "today" or datetime.strptime(end_date, "%Y-%m-%d") > datetime.today():
            end_date = None

    BaseETL.execute_command(
        command="delete from {} where date = 'date'".format(ga.table_name),
        db_enum=EnumDb.BI_ODS,
        commit=True
    )

    BaseETL.execute_command(
        command=""" update {}
                        set campaign = 'Trazer proprietários de volta'
                    where
                        campaign like 'Trazer proprietÃ%'
                """.format(ga.table_name),
        db_enum=EnumDb.BI_ODS,
        commit=True
    )
    return ga.table_name


def load_dw():
    now = datetime.now()
    min_date = (datetime.today() - timedelta(days=7)).strftime('%Y%m%d')
    fact_table = 'fact_liquidity_ga_confirmed_visits'

    BaseETL.execute_command(
        command="DELETE from {} where sk_date >= '{}'".format(fact_table, min_date),
        db_enum=EnumDb.BI_DW,
        commit=True
    )

    BaseETL.move_table_to_dw(
        table_name='vw_fact_liquidity_ga_confirmed_visits',
        table_name_dest=fact_table,
        enum_db_source=EnumDb.BI_ODS,
        enum_db_dest=EnumDb.BI_DW,
        append=True,
        encoding='UTF8'
    )
    BaseETL.execute_command(
        command="update ga_confirmed_visits set processed_date = '{}' where processed_date is null".format(now),
        db_enum=EnumDb.BI_ODS,
        commit=True
    )

    # criar dump


if __name__ == "__main__":
    args = sys.argv

    print('START - {}'.format(datetime.now()))

    if len(args) > 1:
        if args[1] == 'ODS':
            table_name = load_ods()
            BaseETL.dump_ODS_to_datalake(table_name)

        elif args[1] == 'DW':
            load_dw()
    else:
        load_ods()

    print('END - {}'.format(datetime.today()))
