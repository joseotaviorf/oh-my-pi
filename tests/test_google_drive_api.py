from jobs.wrappers.GoogleDrive.google_drive_api import GoogleDriveApi
from pprint import pprint

api = GoogleDriveApi()
files = api.list_filenames()
if not files:
    print('No files found.')
else:
    print('Files:')
    for file in files:
        pprint('{0} ({1})'.format(file['name'], file['id']))
        try:
            api.download_file(file['id'], '/tmp', file['mimeType'])
        except Exception as ex:
            print ex
