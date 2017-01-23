# -*- coding: utf-8 -*-
import httplib2
from googleapiclient import discovery
from oauth2client.service_account import ServiceAccountCredentials
import json
import os


class GoogleDriveApi(object):

    def __init__(self):
        self.service = self._create_drive_service()

    @classmethod
    def _create_drive_service(cls):
        scope = ['https://www.googleapis.com/auth/drive']
        analytics_json = json.loads(os.environ['ANALYTICS_KEY_JSON'])
        credentials = ServiceAccountCredentials.from_json_keyfile_dict(analytics_json, scopes=scope)
        return discovery.build('drive', 'v3', http=credentials.authorize(httplib2.Http()))

    @classmethod
    def convert_mime_type(cls, mime_type):
        mime_dict = {
            'application/vnd.google-apps.spreadsheet' : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'application/vnd.google-apps.document' : 'vnd.openxmlformats - officedocument.wordprocessingml.document'
        }
        return mime_dict.get(mime_type, None)

    def list_filenames(self):
        query = "mimeType != 'application/vnd.google-apps.folder'"
        results = self.service.files().list(q=query).execute()
        return results.get('files', [])

    def get_file_info(self, file_id):
        """
        Return the info for a file, containing id, name, description, etc
        """
        return self.service.files().get(fileId=file_id).execute()

    def get_file_media(self, file_id, mime_type=None):
        """
        Get the file content, to download the file
        """
        if not mime_type:
            return self.service.files().get_media(fileId=file_id).execute()
        else:
            return self.service.files().export_media(
                fileId=file_id,
                mimeType=self.convert_mime_type(mime_type)
            ).execute()

    def download_file(self, file_id, path, mime_type=None):
        """
        Downloads a file from google drive
        """
        if not path or not file_id:
            return

        mime_type = mime_type if "google-apps" in mime_type else None
        data = self.get_file_media(file_id, mime_type)
        file_info = self.get_file_info(file_id)

        with open(os.path.join(path, file_info['name']), 'wb') as download_file:
            download_file.write(data)
