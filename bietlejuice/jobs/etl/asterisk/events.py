from collections import OrderedDict
from qa_python_utils import QuintoAndarLogger
from bietlejuice.jobs.etl.asterisk.asterisk import Asterisk
from bietlejuice.jobs.etl.asterisk.asterisk_table_enum import AsteriskTableEnum

logger = QuintoAndarLogger('AsteriskEvents')


class AsteriskEvents(Asterisk):
    CLASS_ENUM = AsteriskTableEnum.EVENTS
    events = ['call_started', 'call_ended', 'ura_started', 'queue_started', 'queue_num_set',
              'crm_destination_set', 'agent_aswered', 'key_typed', 'audio_message_started']

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(AsteriskEvents, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger(exclude=['r_cols', 'c_cols'])
    def _move_to_clean_partitioned_event(self, class_, r_cols, c_cols, event):
        key = "clean/asterisk/{CLASS_VALUE}/dt={PARTITION_DATE}/" \
              "event={EVENT}/{PARTITION_DATE}.parq".format(CLASS_VALUE=class_.value,
                                                           PARTITION_DATE=self.partition_date,
                                                           EVENT=event)
        self._move_to_clean(
            class_=class_,
            key=key,
            r_cols=r_cols,
            c_cols=c_cols,
            partition_date=self.partition_date,
            event=event
        )

    @logger
    def move_to_clean(self):
        r_cols = OrderedDict([
            ('id_call', str),
            ('id_phase', str),
            ('phase', str),
            ('name', str),
            ('params', str),
            ('ts_created', str),
            ('ts_load', str)
        ])

        for event in AsteriskEvents.events:
            self._move_to_clean_partitioned_event(
                class_=AsteriskEvents.CLASS_ENUM,
                r_cols=r_cols,
                c_cols=r_cols,
                event=event
            )
