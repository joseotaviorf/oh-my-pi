from os import listdir
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.new_etl.autodialer import AUTODIALER_DATALAKE_QUERIES_DIR
from bietlejuice.jobs.new_etl.autodialer.autodialer import AutoialerETL

logger = QuintoAndarLogger('AutodialerSubDag')


class AutodialerSubDag(BaseSubDag):
    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date, document_type):
        super(AutodialerSubDag, self).__init__(bucket, sub_dag_name, dag_name, schedule_interval, start_date)
        self.document_type = document_type

    @logger
    def __get_files_list(self, document_type):
        path = '{}/{}'.format(AUTODIALER_DATALAKE_QUERIES_DIR, document_type)
        return path, listdir(path)

    @logger
    def build_clean_tasks(self):
        autodialer_dag = BaseSubDag._build_local_dag()
        path, dir_files = self.__get_files_list(self.document_type)

        if len(dir_files) > 0:
            for _file in dir_files:
                BaseDAG.build_python_operator(
                    dag=autodialer_dag,
                    task_id='{}_to_clean'.format(_file),
                    python_callable=self.dump_to_clean,
                    provide_context=True
                )

        return autodialer_dag

    @logger
    def dump_to_clean(self, **kwargs):
        autodialer = AutoialerETL(
            bucket_name=self.bucket,
            execution_date=kwargs['execution_date']
        )
        autodialer.move_data_to_clean(self.document_type)
