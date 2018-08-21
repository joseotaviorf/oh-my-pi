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
            if 'xcom_task_id' in kwargs:
                self.xcom_task_id = kwargs['xcom_task_id']
            else:
                raise Exception('job_id and xcom_task_id cannot be both None!')
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
        elif job_status in ('SUBMITTED', 'PENDING', 'RUNNABLE', 'STARTING', 'RUNNING'):
            return False
        elif job_status == 'SUCCEEDED':
            return True
        elif job_status == 'FAILED':
            raise Exception('Job has failed!')

        raise Exception()

    def xcom_job_id(self, task_instance):
        if self.xcom_task_id:
            self.job_id = xcom.xcom_pull(task_instance=task_instance, task_id=self.xcom_task_id)
        else:
            raise Exception('There must be an xcom_task_id to receive an xcom value!')
