from airflow.operators.sensors import BaseSensorOperator
from airflow.utils.decorators import apply_defaults
from bietlejuice.jobs.dags.util import xcom as xcom
from qa_python_utils.aws.batch import BatchClient
from qa_python_utils.default_logger import _logger


class QuintoAndarAWSBatchSensor(BaseSensorOperator):

    @apply_defaults
    def __init__(self, *args, **kwargs):
        super(QuintoAndarAWSBatchSensor, self).__init__(*args, **kwargs)

        if 'job_id' not in kwargs:
            if 'xcom_task_id' not in kwargs:
                raise Exception('job_id and xcom_task_id cannot be both None!')

            self.xcom_task_id = kwargs['xcom_task_id']
        else:
            self.job_id = kwargs['job_id']

    def poke(self, context):
        # check if there is a job to poke
        if not hasattr(self, 'job_id'):
            self.xcom_job_id(task_instance=context['ti'])

        batch_client = BatchClient()
        _logger.info('m=poke, job_id={}'.format(self.job_id))
        job_status = batch_client.get_job_status_by_id(job_id=self.job_id)
        _logger.info('m=poke, job_id={}, job_status={}'.format(self.job_id, job_status))

        if job_status is None:
            raise Exception('Job not found')
        if job_status in ('SUBMITTED', 'PENDING', 'RUNNABLE', 'STARTING', 'RUNNING'):
            return False
        if job_status == 'SUCCEEDED':
            return True
        if job_status == 'FAILED':
            raise Exception('Job has failed!')

        raise Exception('Status not expected!')

    def xcom_job_id(self, task_instance):
        if not self.xcom_task_id:
            raise Exception('There must be an xcom_task_id to receive an xcom value!')

        self.job_id = xcom.xcom_pull(task_instance=task_instance, task_id=self.xcom_task_id)
