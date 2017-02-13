import sys
import os
import petl
from datetime import datetime, timedelta
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
                "metrics": "ga:pageviews",
                "dimensions": "ga:date,ga:pagePath",
                "filters": "ga:pagePath=~^\/lista\-de\-visitas\/agendar\?imoveis\=[0-9]+$",
                "samplingLevel": "HIGHER_PRECISION",
                "sort": "ga:pagePath"
            }
        )

def getIdFromUrl(str):
    return str.split('=')[1]

def load_data():
    ga = GAScheduleView(
        'QuintoAndar',
        'Quinto Andar',
        'All Web Site Data'
    )

    start_date = "2017-02-09"
    end_date = "2017-02-09"

    result, contains_sampling_data = ga.get(start_date, end_date)
    print('{} - Sampling Data: {}'.format(ga.ga.property_name, contains_sampling_data))

    imovelIds = []
    mapImovelIdViews = {}
    for row in result[1:]:
        url = row[1]
        views = row[2]
        imovelIds.append(getIdFromUrl(url))
        mapImovelIdViews[getIdFromUrl(url)] = views
        #print(getIdFromUrl(url) + ' - ' + views)

        #data = BaseETL.from_db_query(
        #    EnumDb.QuintoAndar_ebdb,
        #    query="select id,regiao_id,bairro from Imovel i where i.id = {};".format(getIdFromUrl(url))
        #)

    print(mapImovelIdViews)

    listImovelIds = ','.join(map(str,imovelIds))
    data = BaseETL.from_db_query(
        EnumDb.QuintoAndar_ebdb,
        query="select regiao_id,bairro,group_concat(distinct id separator ',') from Imovel where id in ({}) group by regiao_id,bairro;".format(listImovelIds),
    )

    for row in data[1:]:
        print "{} - {} - {}".format(row[0],row[1],row[2])

    print("======")

    petl.tocsv(result, os.getcwd() + '/tmp/testing.csv', encoding='utf8')
    print(os.getcwd() + "\n")

if __name__ == "__main__":

    print('START - {}'.format(datetime.now()))

    load_data()

    print('END - {}'.format(datetime.today()))
