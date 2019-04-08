from airflow.contrib.hooks.emr_hook import EmrHook
from airflow.contrib.sensors.emr_base_sensor import EmrBaseSensor
from airflow.utils import apply_defaults


class QuintoAndarEmrJobFlowSensor(EmrBaseSensor):
    """
    Asks for the state of the JobFlow until it reaches a terminal state.
    If it fails the sensor errors, failing the task.

    Note: this is a copy from EmrJobFlowSensor class without the 'WAITING' state in the NON_TERMINAL_STATES list,
    because there is a need to know when the cluster is done bootstrapping and it is waiting for new steps to be added.

    :param job_flow_id: job_flow_id to check the state of
    :type job_flow_id: string
    """

    NON_TERMINAL_STATES = ['STARTING', 'BOOTSTRAPPING', 'RUNNING', 'TERMINATING']
    FAILED_STATE = ['TERMINATED_WITH_ERRORS']
    template_fields = ['job_flow_id']
    template_ext = ()

    @apply_defaults
    def __init__(self,
                 job_flow_id,
                 *args,
                 **kwargs):
        super(QuintoAndarEmrJobFlowSensor, self).__init__(*args, **kwargs)
        self.job_flow_id = job_flow_id

    def get_emr_response(self):
        emr = EmrHook(aws_conn_id=self.aws_conn_id).get_conn()

        self.log.info('Poking cluster %s', self.job_flow_id)
        return emr.describe_cluster(ClusterId=self.job_flow_id)

    @staticmethod
    def state_from_response(response):
        return response['Cluster']['Status']['State']
