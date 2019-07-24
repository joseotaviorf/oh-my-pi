from datetime import datetime
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger('events_raw_to_clean')

parser = ArgumentParser(description='events_raw_to_clean')
parser.add_argument('execution_date')
parser.add_argument('env')


def get_s3_clean_path(env):
    if env == 'forno':
        return 's3://5a-datalake-forno/clean_spark/amplitude/'
    elif env == 'prod':
        return 's3://5a-datalake/clean_spark/amplitude/'
    raise ValueError('The environment do not exists: {}'.format(env))


if __name__ == '__main__':
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env

    date = datetime.strptime(execution_date, '%Y-%m-%d')
    db_raw = 'datalake_raw_spark'
    db_clean = 'datalake_clean_spark'
    s3_clean_path = get_s3_clean_path(env)

    amplitude_events = AmplitudeEvents(db_raw=db_raw, db_clean=db_clean, s3_clean_path=s3_clean_path)

    amplitude_events.update_clean_amplitude_events(date=date)

    event_types = ['listing_page_viewed', 'schedule_page_viewed', 'landing_page_viewed', 'lead_form_submitted',
                   'visit_schedule_confirmed', 'visit_intent_clicked', 'login_confirmation_viewed', 'home_page_viewed',
                   'signup_user_created']
    for event_type in event_types:
        amplitude_events.update_filtered_events_table(date=date, event_type=event_type)
