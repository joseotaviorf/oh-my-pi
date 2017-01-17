# -*- coding: utf-8 -*-
import httplib2
import pprint
import StringIO
from googleapiclient import discovery
from googleapiclient.http import MediaFileUpload
from oauth2client.service_account import ServiceAccountCredentials
import json
import os


def createDriveService():
    scope = ['https://www.googleapis.com/auth/analytics.readonly']
    analytics_json = json.loads(os.environ['ANALYTICS_KEY_JSON'])
    credentials = ServiceAccountCredentials.from_json_keyfile_dict(analytics_json, scopes=scope)
    return discovery.build('drive', 'v3', http=credentials.authorize(httplib2.Http()))

service = createDriveService()

results = service.files().list(pageSize=10, fields="nextPageToken, files(id, name)").execute()
items = results.get('files', [])
if not items:
    print('No files found.')
else:
    print('Files:')
    for item in items:
        print('{0} ({1})'.format(item['name'], item['id']))



#     def create_dummy_file(self):
#         # Create GoogleDriveFile instance with title 'Hello.txt'.
#         file1 = self.drive.CreateFile({'title': 'TESTE.txt'})
#         file1.Upload() # Upload the file.
#         print('title: %s, id: %s' % (file1['title'], file1['id']))