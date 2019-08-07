import logging
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.airflow.environment import Environment
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents

JOB_NAME = "events_raw_to_clean"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_s3_clean_path(environment):
    if not Environment.is_valid_environment(environment):
        raise RuntimeError(
            "msg=environment %s invalid. Environments allowed are: " % ', '.join(
                Environment.get_valid_environments())
        )
    return "s3://5a-datalake-{}/clean/amplitude/".format(environment)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("execution_date")
    parser.add_argument("env")
    args = parser.parse_args()
    execution_date = args.execution_date
    environment = args.env

    date = datetime.strptime(execution_date, "%Y-%m-%d")
    db_raw = "datalake_amplitude_raw"
    db_clean = "datalake_amplitude_clean"
    s3_clean_path = get_s3_clean_path(environment)

    amplitude_events = AmplitudeEvents(environment=environment,
                                       db_raw=db_raw, db_clean=db_clean, s3_clean_path=s3_clean_path
                                       )

    amplitude_events.update_clean_amplitude_events(date=date)

    event_types = [
        "listing_page_viewed",
        "schedule_page_viewed",
        "landing_page_viewed",
        "lead_form_submitted",
        "visit_schedule_confirmed",
        "visit_intent_clicked",
        "login_confirmation_viewed",
        "home_page_viewed",
        "signup_user_created",
    ]
    for event_type in event_types:
        amplitude_events.update_filtered_events_table(date=date, event_type=event_type)
