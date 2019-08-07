import io

import requests
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("AmplitudeExportApi")


class AmplitudeExportApi:
    def __init__(self, api_key, secret_key):
        self.API_KEY = api_key
        self.SECRET_KEY = secret_key

    def get_files_from_extract_api(self, start_time, end_time):
        url = "https://amplitude.com/api/2/export?start={}&end={}"
        url_full = url.format(start_time, end_time)
        r = requests.get(url_full, auth=(self.API_KEY, self.SECRET_KEY))
        file_stream = None
        logger.info(
            "Keys: {}, {} - URL: {} - STATUS_CODE: {}".format(
                self.API_KEY, self.SECRET_KEY, url_full, r.status_code
            )
        )
        if r.status_code == 200:
            file_stream = io.BytesIO(r.content)
        return file_stream
