import decimal
import json

import petl
from qa_python_utils import QuintoAndarLogger
from shapely import wkt
from shapely.geometry import Point

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.new_etl import SOURCE_QUERIES_DIR

logger = QuintoAndarLogger('LeadsProcessor')


def decimal_default(obj):
    if isinstance(obj, decimal.Decimal):
        return float(obj)
    raise TypeError


class LeadsProcessor(object):
    QUEUE = 'CrawlerLeads'

    def __init__(self):
        self.__poly = None
        self.__unit_d = None

    @logger
    def get_polygons(self):
        if self.__poly is None:
            q = BaseETL.get_query_from_file_name('{}/ebdb/leads/get_polygons.sql'.format(SOURCE_QUERIES_DIR))
            poly = BaseETL.from_db_query(db_enum=EnumDB.QuintoAndar_ebdb, query=q, encoding='utf8mb4')
            poly = petl.todataframe(poly)

            poly.polygon = poly.polygon.apply(wkt.loads)
            self.__poly = poly

        return self.__poly

    @logger
    def get_unit_divisor(self, unit=None):
        if unit is not None:
            unit_d = {'week': 7.0, 'day': 1.0, 'year': 365.25, 'month': 30.0}
            self.__unit_d = unit_d.get(unit)

        return self.__unit_d

    @logger
    def check_coverage(self, lat, lng):
        try:
            p = Point((float(lng), float(lat)))
        except Exception:
            return -1

        poly = self.get_polygons()

        for _, row in poly.iterrows():
            if row.polygon.contains(p):
                return row.region_id

        return -1

    @staticmethod
    @logger
    def get_reprocessed():
        q = BaseETL.get_query_from_file_name('{}/ebdb/leads/get_reprocessed.sql'.format(SOURCE_QUERIES_DIR))
        reprocessed = BaseETL.from_db_query(db_enum=EnumDB.QuintoAndar_ebdb, query=q, encoding='utf8mb4')

        return petl.todataframe(reprocessed)

    @staticmethod
    @logger
    def get_contacts(week_interval, status_in, reason_in, statuses, reasons):
        q = BaseETL.get_query_from_file_name('{}/ebdb/leads/get_contacts.sql'.format(SOURCE_QUERIES_DIR))

        status_in = '' if status_in else 'not'
        reason_in = '' if reason_in else 'not'

        status_rule = ''
        if isinstance(statuses, list):
            status_rule = "', '".join(statuses)

        reason_rule = ''
        if isinstance(reasons, list):
            reason_rule = "', '".join(reasons)

        q = q.format(
            status_in=status_in,
            status_rule=status_rule,
            reason_in=reason_in,
            reason_rule=reason_rule,
            week_interval=week_interval
        )

        contacts = BaseETL.from_db_query(db_enum=EnumDB.QuintoAndar_ebdb, query=q, encoding='utf8mb4')

        return petl.todataframe(contacts)

    @staticmethod
    def __build_categorical_filter(column, categories):
        if categories is None or not isinstance(categories, list):
            return None

        return """{} in ('{}')\n""".format(column, "', '".join(categories))

    def __build_time_interval_filter(self, column, interval, unit):
        u = self.get_unit_divisor(unit)
        if u is None:
            return None

        if interval is None or not any(isinstance(interval, t) for t in [list, tuple]):
            return None

        return """floor(datediff(utc_timestamp(), {0})/{1:.2f}) between {2} and {3}\n""".format(
            column, u, interval[0], interval[1])

    @logger
    def read_leads(self, origin, status, reason, interval, unit):
        q = """select * from Lead\n"""

        filters = [
            self.__build_categorical_filter('origem', origin),
            self.__build_categorical_filter('status', status),
            self.__build_categorical_filter('reason', reason),
            self.__build_time_interval_filter('atualizadoEm', interval, unit)
        ]

        where = 'and '.join(filter(lambda x: x is not None, filters))
        if where:
            q += """where {}""".format(where)

        leads = BaseETL.from_db_query(db_enum=EnumDB.QuintoAndar_ebdb, query=q, encoding='utf8mb4')

        return petl.todataframe(leads)

    @staticmethod
    def __build_leads_list(leads):
        columns = ['origem', 'tipo', 'cep', 'cidade', 'bairro', 'endereco', 'numero', 'complemento', 'lat', 'lng',
                   'valor', 'nomeAnunciante', 'telefoneAnunciante', 'telefoneAnuncianteDois', 'telefoneAnuncianteTres',
                   'email', 'infosExtras', 'referencia']
        df = leads.loc[:, columns].to_dict(orient='records')
        json_list = [json.dumps(row, default=decimal_default, ensure_ascii=False, encoding='utf-8') for row in df]

        return json_list

    @logger(exclude=['leads'])
    def send_leads(self, leads):
        json_list = self.__build_leads_list(leads)
        BaseETL.publish_messages(
            messages=json_list,
            queue_name=self.QUEUE
        )
