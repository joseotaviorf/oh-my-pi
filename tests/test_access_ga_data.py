import sys
import os
import petl
from datetime import date, datetime, timedelta
from jobs.base.base_ga import BaseGA
from jobs.base.base_etl import BaseETL, EnumDb

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

    start_date = "6daysAgo"
    end_date = "today"
    start_date_query = str(date.today() - timedelta(days=6))
    end_date_query = str(date.today())

    # First GA query, views by page
    result_schedule_view, contains_sampling_data = ga.get(start_date, end_date)
    print('{} - Sampling Data: {}'.format(ga.ga.property_name, contains_sampling_data))

    # Second GA query, slot0, slot1, pageview (example: if slot0 = 3 -> 3 slots were seen as available on day 0 )
    result_schedule_view_d0_d1, contains_sampling_data = ga2.get(start_date, end_date)
    print('{} - Sampling Data: {}'.format(ga2.ga.property_name, contains_sampling_data))

    # Map (imovelId -> Number of views)
    imovelIds = []
    mapImovelIdViews = {}
    for row in result_schedule_view[1:]:
        imovelId = str(row[0].split('=')[1])
        views = int(row[1])
        imovelIds.append(imovelId)
        mapImovelIdViews[imovelId] = views

    # Map (imovelId -> Number of views where (slots available on d0 + slots available on d1) >= 3)
    # Note: 'if row[0] != "pagePath"' is necessary because if a GA query returns more than 5000
    # rows, it will repeat a row with the columns names
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

            if slotNumberD0 + slotNumberD1 >= 1:
                if not imovelId in mapImovelIdViewsD0D1_01PlusSlots:
                    mapImovelIdViewsD0D1_01PlusSlots[imovelId] = views
                else:
                    mapImovelIdViewsD0D1_01PlusSlots[imovelId] += views

            if slotNumberD0 + slotNumberD1 >= 3:
                if not imovelId in mapImovelIdViewsD0D1_03PlusSlots:
                    mapImovelIdViewsD0D1_03PlusSlots[imovelId] = views
                else:
                    mapImovelIdViewsD0D1_03PlusSlots[imovelId] += views

            if slotNumberD0 + slotNumberD1 >= 5:
                if not imovelId in mapImovelIdViewsD0D1_05PlusSlots:
                    mapImovelIdViewsD0D1_05PlusSlots[imovelId] = views
                else:
                    mapImovelIdViewsD0D1_05PlusSlots[imovelId] += views

            if slotNumberD0 + slotNumberD1 >= 7:
                if not imovelId in mapImovelIdViewsD0D1_07PlusSlots:
                    mapImovelIdViewsD0D1_07PlusSlots[imovelId] = views
                else:
                    mapImovelIdViewsD0D1_07PlusSlots[imovelId] += views

            if slotNumberD0 + slotNumberD1 >= 9:
                if not imovelId in mapImovelIdViewsD0D1_09PlusSlots:
                    mapImovelIdViewsD0D1_09PlusSlots[imovelId] = views
                else:
                    mapImovelIdViewsD0D1_09PlusSlots[imovelId] += views

            if slotNumberD0 + slotNumberD1 >= 11:
                if not imovelId in mapImovelIdViewsD0D1_11PlusSlots:
                    mapImovelIdViewsD0D1_11PlusSlots[imovelId] = views
                else:
                    mapImovelIdViewsD0D1_11PlusSlots[imovelId] += views

    #SELECT r3.nome,r.nome,i.bairro,i.id
    #FROM Imovel i
    #LEFT JOIN Regiao r on (i.regiao_id = r.id)
    #LEFT JOIN Regiao r2 on (r.regiaoPai_id = r2.id)
    #LEFT JOIN Regiao r3 on (r2.regiaoPai_id = r3.id)
    #WHERE i.id IN (%s);

    placeholders=','.join(['%s']*len(imovelIds))
    query="""
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
            """ % (placeholders,start_date_query,end_date_query)

    db = BaseETL.get_connection(db_enum=EnumDb.QuintoAndar_ebdb,encoding='UTF8')
    cursor = db.cursor()
    cursor.execute(query,imovelIds)

    finalData = [["Date Start","Date End","Cidade", "Regiao",
                  "Bairro","Imovel Id","Views","Agendamentos",
                  "Views com 1+ slots em d0 e d1","Views com 3+ slots em d0 e d1",
                  "Views com 5+ slots em d0 e d1","Views com 7+ slots em d0 e d1",
                  "Views com 9+ slots em d0 e d1","Views com 11+ slots em d0 e d1"]]
                  
    for row in cursor.fetchall():
        finalData.append([start_date_query,end_date_query,
                          row[0].decode('utf-8'),
                          row[1].decode('utf-8'),
                          row[2].decode('utf-8'),
                          row[3],
                          mapImovelIdViews[str(row[3])],
                          row[4],
                          mapImovelIdViewsD0D1_01PlusSlots.get(str(row[3]),0),
                          mapImovelIdViewsD0D1_03PlusSlots.get(str(row[3]),0),
                          mapImovelIdViewsD0D1_05PlusSlots.get(str(row[3]),0),
                          mapImovelIdViewsD0D1_07PlusSlots.get(str(row[3]),0),
                          mapImovelIdViewsD0D1_09PlusSlots.get(str(row[3]),0),
                          mapImovelIdViewsD0D1_11PlusSlots.get(str(row[3]),0)])

    db.close()

    petl.tocsv(finalData, sys.path[0] + '/tmp/testing.csv', encoding='utf8')

if __name__ == "__main__":

    print('START - {}'.format(datetime.now()))

    load_data()

    print('END - {}'.format(datetime.today()))
