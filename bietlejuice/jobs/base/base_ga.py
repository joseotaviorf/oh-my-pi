from bietlejuice.jobs.wrappers.GA.ga_api import GA_API
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb
from datetime import datetime, timedelta
import petl


class BaseGA(object):

    def __init__(self, account_name, property_name, profile_name):
        self.ga = GA_API(account_name, property_name, profile_name)

    @classmethod
    def add_date_str(cls, dt, days_num=7):
        return (datetime.strptime(dt, "%Y-%m-%d") + timedelta(days=days_num)).strftime("%Y-%m-%d")

    @classmethod
    def get_flag_create_table(cls, db_enum, table_name):
        return not BaseETL.from_db_query(
            query="select count(1)::integer::boolean from pg_class where relkind = 'r' and relname = '{}'".format(
                table_name
            ),
            db_enum=db_enum
        )[1][0]

    def execute_query(self, query):
        result, contains_sampling_data = self.ga.get_query(**query)
        result = petl.addfield(result, 'account_name', self.ga.account_name)
        result = petl.addfield(result, 'property_name', self.ga.property_name)
        result = petl.addfield(result, 'profile_name', self.ga.profile_name)
        return result, contains_sampling_data