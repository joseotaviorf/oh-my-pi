import airflow.utils.helpers as airflow_helpers
from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.base.base_sub_dag import BaseSubDag
from bietlejuice.jobs.etl import DW_QUERIES_DIR
from qa_python_utils import QuintoAndarLogger

logger = QuintoAndarLogger('FunnelConversionSubDag')


class FunnelConversionSubDag(BaseSubDag):
    def __init__(self, bucket, sub_dag_name, dag_name, schedule_interval, start_date, funnel_side):
        super(FunnelConversionSubDag, self).__init__(
            bucket=bucket,
            sub_dag_name=sub_dag_name,
            dag_name=dag_name,
            schedule_interval=schedule_interval,
            start_date=start_date,
            table_name=None,
        )
        self.funnel_side = funnel_side

    @logger
    def load_funnel_conversions(self, period):
        dim_date_column = {'daily': 'date',
                           'weekly': 'week_start',
                           'monthly': 'month_start'}

        query = BaseETL.get_query_from_file_name(
            file_name='{}/marketing/funnel_conversions/fact_{}_funnel_conversions.sql'.format(DW_QUERIES_DIR,
                                                                                              self.funnel_side))

        query = query.format(dim_date_column.get(period), period)

        table = BaseETL.from_db_query(
            db_enum=EnumDB.BI_DW,
            query=query)

        BaseETL.bulk_insert(
            table=table,
            table_name='marketing.fact_{}_{}_funnel_conversions'.format(period, self.funnel_side),
            db_enum=EnumDB.BI_DW,
            encoding='UTF-8',
            append=False
        )

    def build_subdag(self):
        funnel_conversion_sub_dag = self._build_local_dag()

        daily_task, weekly_task, monthly_task = self.__build_data_tasks(funnel_conversion_sub_dag)

        airflow_helpers.chain(daily_task, weekly_task, monthly_task)

        return funnel_conversion_sub_dag

    @logger
    def __build_data_tasks(self, dag):
        daily_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='load_fact_daily_{}_funnel_conversions'.format(self.funnel_side),
            python_callable=self.load_funnel_conversions,
            op_kwargs={'funnel_side': self.funnel_side,
                       'period': 'daily'}
        )

        weekly_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='load_fact_weekly_{}_funnel_conversions'.format(self.funnel_side),
            python_callable=self.load_funnel_conversions,
            op_kwargs={'funnel_side': self.funnel_side,
                       'period': 'weekly'}
        )

        monthly_task = BaseDAG.build_python_operator(
            dag=dag,
            task_id='load_fact_monthly_{}_funnel_conversions'.format(self.funnel_side),
            python_callable=self.load_funnel_conversions,
            op_kwargs={'funnel_side': self.funnel_side,
                       'period': 'monthly'}
        )

        return daily_task, weekly_task, monthly_task
