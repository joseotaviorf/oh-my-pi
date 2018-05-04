import requests
import re
from time import sleep
from datetime import datetime, timedelta

url_base = 'http://capiroto.quintoandar.com.br/admin/airflow/run?task_id=dump_chat_data_to_raw_s3_bucket&dag_id=bi-zendesk-api&force=true&deps=true&execution_date={}T00:00:00&origin=http%3A%2F%2Fcapiroto.quintoandar.com.br%2Fadmin%2Fairflow%2Ftree%3Fbase_date%3D2017-08-13%2B03%253A00%253A00%26num_runs%3D365%26root%3D%26dag_id%3Dbi-zendesk-api%26_csrf_token%3D1502749294%2523%25237c100f15367862a969e58c9f611b41deac53f9eb'

s = requests.Session()
url_login = 'http://capiroto.quintoandar.com.br/admin/airflow/login'
r = s.get(url_login)
csrf = re.search('_csrf.*value=\"(.*)\"', r.text).groups()[0]
cred = {'username': 'felipe.tancredo', 'password': '5@123', '_csrf_token': csrf}

response_login = s.post(url=url_login, data=cred)

dt = datetime(2017, 1, 3)
while dt < datetime.today():
    url = url_base.format(dt.strftime('%Y-%m-%d'))
    print('RUN {}'.format(dt.strftime('%Y-%m-%d')))
    response = s.get(url=url)
    print(response)
    dt += timedelta(days=1)
    sleep(120)
