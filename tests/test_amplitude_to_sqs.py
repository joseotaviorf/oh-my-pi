from datetime import datetime
from jobs.etl.amplitude_events import AmplitudeEventsETL, EnumDb

if __name__ == '__main__':
    a = AmplitudeEventsETL()

    a.run_source_to_sns(topic_arn='arn:aws:sns:us-east-1:632540934959:AmplitudeData', start_date=datetime(2016, 9, 1), end_date=datetime(2016, 11, 9, 23))

    a.run_sqs_to_ods(sqs_queue_name='BIAmplitudeDataQueue', db_enum=EnumDb.BI_ODS, table_name='amplitude_event')
