from collections import OrderedDict
from qa_python_utils import QuintoAndarLogger
from bietlejuice.jobs.etl.asterisk.asterisk import Asterisk
from bietlejuice.jobs.etl.asterisk.asterisk_table_enum import AsteriskTableEnum

logger = QuintoAndarLogger('AsteriskEvents')


class AsteriskEvents(Asterisk):
    CLASS_ENUM = AsteriskTableEnum.EVENTS

    EVENTS = ['call_started', 'hung_up', 'ura_started', 'queue_started', 'queue_num_set', 'attendance_started',
              'crm_destination_set', 'agent_answered', 'key_typed', 'audio_message_started', 'queue_join_time_set',
              'crm_source_set', 'queue_hung_up', 'queue_spawned_extension']

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(AsteriskEvents, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger(exclude=['r_cols', 'c_cols'])
    def _move_to_clean_partitioned_event(self, class_, r_cols, c_cols, event):
        key = "clean/asterisk/{class_value}/event={event}/" \
              "dt={partition_date}/{event}_{partition_date}.parq".format(class_value=class_.value,
                                                                         partition_date=self.partition_date,
                                                                         event=event)
        self._move_to_clean(
            class_=class_,
            key=key,
            r_cols=r_cols,
            c_cols=c_cols,
            partition_date=self.partition_date,
            event=event
        )

    @logger
    def mount_partitions(self, class_, bucket_type):

        for event in AsteriskEvents.EVENTS:
            self._upsert_partitions(
                class_=class_,
                bucket_type=bucket_type,
                partitions_list_dicts=[
                    {'partition_name': 'event', 'partition_value': event},
                    {'partition_name': 'dt', 'partition_value': self.partition_date}
                ]
            )

    @logger
    def move_to_clean(self):
        r_cols = OrderedDict([
            ('id_call', str),
            ('sk_call', str),
            ('id_phase', str),
            ('phase', str),
            ('name', str),
            ('params', str),
            ('ts_created', str),
            ('ts_load', str)
        ])

        for event in AsteriskEvents.EVENTS:
            self._move_to_clean_partitioned_event(
                class_=AsteriskEvents.CLASS_ENUM,
                r_cols=r_cols,
                c_cols=r_cols,
                event=event
            )
