from datetime import datetime

from jobs.etl import amplitude_sqs as amp_sqs

if __name__ == '__main__':
    amp_sqs.execute(queue_name='DevAmplitudeDataQueue', start_date=datetime(2016,9,16), end_date=datetime(2016,10,10))