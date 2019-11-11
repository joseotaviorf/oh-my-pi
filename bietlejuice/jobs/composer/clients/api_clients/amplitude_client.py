import io

import requests
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("AmplitudeAPIClient")

EXPORT_ENDPOINT = "https://amplitude.com/api/2/export"


class AmplitudeClient:
    def __init__(self, api_key, secret_key):
        self.api_key = api_key
        self.secret_key = secret_key

    @logger
    def get_event_data_files(self, start_time, end_time):
        file_stream = None
        try:
            r = requests.get(
                EXPORT_ENDPOINT,
                auth=(self.api_key, self.secret_key),
                params={"start": start_time, "end": end_time},
            )
            r.raise_for_status()
            file_stream = io.BytesIO(r.content)
        except requests.exceptions.RequestException as e:
            logger.error(
                "m=get_event_data_files, Response: {0}, Status Code: {1}".format(
                    e.response.content, e.response.status_code
                )
            )
            # todo: check if we want to raise an error here
            # raise e

        return file_stream
