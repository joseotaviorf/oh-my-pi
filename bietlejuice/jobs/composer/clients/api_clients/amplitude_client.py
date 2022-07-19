import io

import requests
from quintoandar_logger import QuintoAndarLogger

EXPORT_ENDPOINT = "https://amplitude.com/api/2/export"


class AmplitudeClient:
    def __init__(self, api_key, secret_key):
        self.api_key = api_key
        self.secret_key = secret_key

    def get_event_data_files(self, start_time, end_time):
        logger = QuintoAndarLogger("AmplitudeAPIClient")

        file_stream = None

        try:
            logger.info(
                "m=get_event_data_files, msg=receiving events from Amplitude API "
                f"from {start_time} to {end_time}..."
            )
            r = requests.get(
                EXPORT_ENDPOINT,
                auth=(self.api_key, self.secret_key),
                params={"start": start_time, "end": end_time},
            )
            r.raise_for_status()
            file_stream = io.BytesIO(r.content)

        except requests.exceptions.RequestException as e:
            if e.response.status_code == 404:
                logger.error(
                    "m=get_event_data_files, response={0}, status_code={1}, "
                    "msg=no data received from this account for this day.".format(
                        e.response.content, e.response.status_code
                    )
                )
            else:
                raise Exception(
                    "m=get_event_data_files, response={0}, status_code={1}, "
                    "msg=an exception occurred".format(
                        e.response.content, e.response.status_code
                    )
                )

        return file_stream
