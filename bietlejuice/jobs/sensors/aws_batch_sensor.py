from airflow.operators.sensors import BaseSensorOperator
from airflow.utils.decorators import apply_defaults
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.batch import BatchClient

from bietlejuice.jobs.dags.util import xcom as xcom

logger = QuintoAndarLogger('QuintoAndarAWSBatchSensor')


class QuintoAndarAWSBatchSensor(BaseSensorOperator):
    INTERMEDIATE_STATES = ('SUBMITTED', 'PENDING', 'RUNNABLE', 'STARTING', 'RUNNING')
    FAILURE_STATES = ("FAILED",)
    SUCCESS_STATES = ("SUCCEEDED",)

    @apply_defaults
    def __init__(self, job_id=None, xcom_task_id=None, mode='poke', *args, **kwargs):
        if not job_id and not xcom_task_id:
            raise RuntimeError(
                'm=__init__, msg=job_id and xcom_task_id cannot be both None!')

        kwargs['mode'] = mode
        super(QuintoAndarAWSBatchSensor, self).__init__(*args, **kwargs)

        self.job_id = job_id
        self.xcom_task_id = xcom_task_id
        self.batch_client = BatchClient()

    def poke(self, context):
        # check if there is a job to poke
        if not self.job_id:
            self.job_id = xcom.xcom_pull(task_instance=context['ti'],
                                         task_id=self.xcom_task_id)

        job_status = self.batch_client.get_job_status_by_id(job_id=self.job_id)
        logger.info(
            'm=poke, job_id={}, job_status={}, msg=poked job'.format(self.job_id,
                                                                     job_status))

        if job_status is None:
            raise RuntimeError(
                'm=poke, job_id={}, msg=Job not found'.format(self.job_id))
        elif job_status in self.INTERMEDIATE_STATES:
            return False
        elif job_status in self.SUCCESS_STATES:
            return True
        elif job_status in self.FAILURE_STATES:
            raise RuntimeError(
                'm=poke, job_id={}, msg=Job has failed!'.format(self.job_id))
        else:
            raise RuntimeError(
                'm=poke, job_id={}, status={}, msg=status not expected!'.format(
                    self.job_id, job_status))
