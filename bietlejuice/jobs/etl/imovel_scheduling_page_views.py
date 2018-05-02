import sys
import os
import petl
from datetime import date, datetime, timedelta
from bietlejuice.jobs.base.base_ga import BaseGA
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb


class GAScheduleView(BaseGA):

    def __init__(self, account_name, property_name, profile_name):
        super(GAScheduleView, self).__init__(account_name, property_name, profile_name)
        self.table_name = 'ga_schedule_view'

    def get(self, start_date, end_date):
        return self.execute_query(
            {
                "start_date": start_date,
                "end_date": end_date,
                "metrics": "ga:uniquePageviews",
                "dimensions": "ga:pagePath",
                "filters": "ga:pagePath=~^\/lista\-de\-visitas\/agendar\?imoveis\=[0-9]+$",
                "samplingLevel": "HIGHER_PRECISION",
            }
        )


class GASlotViewInScheduleViewD0D1(BaseGA):

    def __init__(self, account_name, property_name, profile_name):
        super(GASlotViewInScheduleViewD0D1, self).__init__(account_name, property_name, profile_name)
        self.table_name = 'ga_slot_view_in_schedule_view'

    def get(self, start_date, end_date):
        return self.execute_query(
            {
                "start_date": start_date,
                "end_date": end_date,
                "metrics": "ga:uniqueEvents",
                "dimensions": "ga:pagePath,ga:dimension8,ga:dimension9",
                "filters": "ga:pagePath=~^\/lista\-de\-visitas\/agendar\?imoveis\=[0-9]+$",
                "samplingLevel": "HIGHER_PRECISION",
            }
        )


def addViewsToMap(imovelId, slotNum, sumSeenSlots, views, map):
    if sumSeenSlots >= slotNum:
        if imovelId not in map:
            map[imovelId] = views
        else:
            map[imovelId] += views


def load_data():
    ga = GAScheduleView(
        'QuintoAndar',
        'Quinto Andar',
        'All Web Site Data'
    )

    ga2 = GASlotViewInScheduleViewD0D1(
        'QuintoAndar',
        'QuintoAndar - Tracking GTM',
        '1- Prod (Tracking GTM)'
    )

    dateRange = 6  # days
    start_date = str(dateRange) + "daysAgo"
    end_date = "today"
    start_date_query = str(date.today() - timedelta(days=dateRange))
    end_date_query = str(date.today())

    # First GA query, views by page
    result_schedule_view, contains_sampling_data = ga.get(start_date, end_date)
    print('{} - Sampling Data: {}'.format(ga.ga.property_name, contains_sampling_data))

    # Second GA query, slot0, slot1, pageview (example: if slot0 = 3 -> 3 slots were seen as available on day 0 )
    result_schedule_view_d0_d1, contains_sampling_data = ga2.get(start_date, end_date)
    print('{} - Sampling Data: {}'.format(ga2.ga.property_name, contains_sampling_data))

    # Map (imovelId -> Number of views)
    # Note: 'if row[0] != "pagePath"' is necessary because if a GA query returns more than 5000
    # rows, it will repeat a row with the columns names
    imovelIds = []
    mapImovelIdViews = {}
    for row in result_schedule_view[1:]:
        if row[0] != "pagePath":
            imovelId = str(row[0].split('=')[1])
            views = int(row[1])
            imovelIds.append(imovelId)
            mapImovelIdViews[imovelId] = views

    # Map (imovelId -> Number of views where (slots available on d0 + slots available on d1) >= 3)
    mapImovelIdViewsD0D1_01PlusSlots = {}
    mapImovelIdViewsD0D1_03PlusSlots = {}
    mapImovelIdViewsD0D1_05PlusSlots = {}
    mapImovelIdViewsD0D1_07PlusSlots = {}
    mapImovelIdViewsD0D1_09PlusSlots = {}
    mapImovelIdViewsD0D1_11PlusSlots = {}
    for row in result_schedule_view_d0_d1[1:]:
        if row[0] != "pagePath":
            imovelId = str(row[0].split('=')[1])
            slotNumberD0 = int(row[1])
            slotNumberD1 = int(row[2])
            views = int(row[3])

            addViewsToMap(imovelId, 1, slotNumberD0 + slotNumberD1, views, mapImovelIdViewsD0D1_01PlusSlots)
            addViewsToMap(imovelId, 3, slotNumberD0 + slotNumberD1, views, mapImovelIdViewsD0D1_03PlusSlots)
            addViewsToMap(imovelId, 5, slotNumberD0 + slotNumberD1, views, mapImovelIdViewsD0D1_05PlusSlots)
            addViewsToMap(imovelId, 7, slotNumberD0 + slotNumberD1, views, mapImovelIdViewsD0D1_07PlusSlots)
            addViewsToMap(imovelId, 9, slotNumberD0 + slotNumberD1, views, mapImovelIdViewsD0D1_09PlusSlots)
            addViewsToMap(imovelId, 11, slotNumberD0 + slotNumberD1, views, mapImovelIdViewsD0D1_11PlusSlots)

    placeholders = ','.join(['%s'] * len(imovelIds))
    query = """
            SELECT t.nomeCidade,t.nomeRegiao,t.nomeBairro,t.imovelId,count(*)
            FROM (
                SELECT r3.nome as nomeCidade,
                       r.nome as nomeRegiao,
                       i.bairro as nomeBairro,
                       i.id as imovelId
                FROM Imovel i
                LEFT JOIN Regiao r on (i.regiao_id = r.id)
                LEFT JOIN Regiao r2 on (r.regiaoPai_id = r2.id)
                LEFT JOIN Regiao r3 on (r2.regiaoPai_id = r3.id)
                WHERE i.id IN (%s)
            ) as t
            LEFT JOIN Agendamento a on (t.imovelId = a.imovel_id)
            WHERE a.criadoEm BETWEEN '%s' AND '%s'
            GROUP BY t.nomeCidade,t.nomeRegiao,t.nomeBairro,t.imovelId
            """ % (placeholders, start_date_query, end_date_query)

    db = BaseETL.get_connection(db_enum=EnumDb.QuintoAndar_ebdb, encoding='UTF8')
    cursor = db.cursor()
    cursor.execute(query, imovelIds)

    finalData = [["Date Start", "Date End", "Cidade", "Regiao",
                  "Bairro", "Imovel Id", "Views", "Agendamentos",
                  "Views com 1+ slots em d0 e d1", "Views com 3+ slots em d0 e d1",
                  "Views com 5+ slots em d0 e d1", "Views com 7+ slots em d0 e d1",
                  "Views com 9+ slots em d0 e d1", "Views com 11+ slots em d0 e d1"]]

    for row in cursor.fetchall():
        finalData.append([start_date_query, end_date_query,
                          row[0].decode('utf-8'),
                          row[1].decode('utf-8'),
                          row[2].decode('utf-8'),
                          row[3],
                          mapImovelIdViews[str(row[3])],
                          row[4],
                          mapImovelIdViewsD0D1_01PlusSlots.get(str(row[3]), 0),
                          mapImovelIdViewsD0D1_03PlusSlots.get(str(row[3]), 0),
                          mapImovelIdViewsD0D1_05PlusSlots.get(str(row[3]), 0),
                          mapImovelIdViewsD0D1_07PlusSlots.get(str(row[3]), 0),
                          mapImovelIdViewsD0D1_09PlusSlots.get(str(row[3]), 0),
                          mapImovelIdViewsD0D1_11PlusSlots.get(str(row[3]), 0)])

    db.close()

    process_name = 'imovel_scheduling_page_views'
    bucket_datalake = os.environ['bi-datalake-s3-bucket']
    BaseETL.bulk_insert(
        table=finalData,
        table_name=process_name,
        db_enum=EnumDb.BI_ODS,
        encoding='UTF8',
        append=True,
        commit=True,
        bucket_name='{}/raw/ods/{}'.format(bucket_datalake, process_name)
    )


if __name__ == "__main__":

    print('START - {}'.format(datetime.now()))

    load_data()

    print('END - {}'.format(datetime.today()))
