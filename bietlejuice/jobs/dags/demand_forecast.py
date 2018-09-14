from datetime import date
from datetime import datetime

import pandas as pd
import petl
from airflow.models import DAG
from qa_python_utils.default_logger import _logger

from bietlejuice.jobs.base.base_dag import BaseDAG
from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB
from bietlejuice.jobs.dags.util import environment as env
from bietlejuice.jobs.new_etl.kpi_forecast.funnel import Funnel
from bietlejuice.jobs.new_etl.kpi_forecast.helpers import get_count, write_to_s3, get_file_from_s3, get_prediction, \
    get_kpis
from bietlejuice.jobs.new_etl.kpi_forecast.preprocessor import Preprocessor
from bietlejuice.jobs.new_etl.kpi_forecast.query_demand import query_demand
from bietlejuice.jobs.new_etl.kpi_forecast.steps_demand import steps
from bietlejuice.jobs.new_etl.kpi_forecast.ts_predictor import Ts_predictor

bucket_ds = env.get_airflow_env_var('bi-data-science-s3-bucket')  # comment for testing without airflow
bucket_dl = env.get_airflow_env_var('bi-datalake-s3-bucket')  # comment for testing without airflow
# bucket_ds = '5a-data-science'
# bucket_dl = '5a-datalake'

env.set_airflow_var_to_local_env('BI_DW')

MAIN_DAG_NAME = 'bi-demand-forecast'
MAIN_START_DATE = datetime(2018, 3, 20)
MAIN_SCHEDULE_INTERVAL = '30 3 * * 1'  # At 03:30:00am, on every Monday, every month

# parameters of the script
begin_pred = pd.to_datetime(date.today()) - pd.to_timedelta(date.today().weekday(),
                                                            unit='days')  # last monday # must be a monday pandas timestamp

_logger.info(begin_pred)
end_pred = begin_pred + pd.to_timedelta(125, unit='days')  # must be a sunday
n_training_days = 126  # hard limit on the days we do not want to consider for creating distributions
n_recent_days = 60
rolavg_duration = 120
min_samples = 500
max_samples = 10000
model_weekly_seasonality = True
model_yearly_seasonality = True

# other global variables variables
range_pred_day = pd.date_range(begin_pred, end_pred, freq='D', closed='left')
range_pred_week = pd.date_range(begin_pred, end_pred, freq='W-MON', closed='left')
range_recent_day = pd.date_range(begin_pred - pd.to_timedelta(n_recent_days, unit='days'),
                                 begin_pred,
                                 freq='D',
                                 closed='left')
range_training_day = pd.date_range(begin_pred - pd.to_timedelta(n_training_days, unit='days'),
                                   begin_pred,
                                   freq='D',
                                   closed='left')


def load_fact(begin_pred):
    table_demand = BaseETL.from_db_query(
        db_enum=EnumDB.BI_DW,
        query=query_demand
    )
    fact = petl.todataframe(table_demand)
    _logger.info('end query')

    preprocessor_demand = Preprocessor(steps)
    fact = preprocessor_demand.preprocess(fact)
    write_to_s3(bucket_ds, fact, 'monitoring/%s/fact' % (
        begin_pred.strftime("%Y-%m-%d")), to_csv=False, to_pickle=True)  # write to s3 compressed

    # split df_demand into past and future bookings (putting ourselves at the beginning of begin_pred)
    fact_past_bookings = fact[(fact[steps.index[0]] < begin_pred)]

    return fact_past_bookings


def get_default_parameters(city, region):
    default_distribs = None
    if city == 'all':
        # global level. no default
        pass

    elif region == 'all':
        # city level. only possible default is the global level
        if get_file_from_s3(bucket_ds,
                            'KPI_predictor/monitoring/%s/all/all/distribs.gz' % (begin_pred.strftime("%Y-%m-%d")),
                            'global_default_distribs.gz'):
            default_distribs = pd.read_pickle('global_default_distribs.gz', compression='gzip')

    else:
        # region level. default is city level, if not available then use the global level
        if get_file_from_s3(bucket_ds,
                            'KPI_predictor/monitoring/%s/%s/all/distribs.gz' % (begin_pred.strftime("%Y-%m-%d"), city),
                            'city_default_distribs.gz'):
            default_distribs = pd.read_pickle('city_default_distribs.gz', compression='gzip')
        elif get_file_from_s3(bucket_ds,
                              'KPI_predictor/monitoring/%s/all/all/distribs.gz' % (begin_pred.strftime("%Y-%m-%d")),
                              'global_default_distribs.gz'):
            default_distribs = pd.read_pickle('global_default_distribs.gz', compression='gzip')

    return default_distribs


def split_train_recent(df, n_training_days=63, n_recent_days=21):
    """
    we set a limit between training data (all bookings older than a threshold date,
    for which we are sure the process is finished) and current data (other bookings)
    n_training_days : hard limit on the days we do not want to consider for creating distributions
    """

    # todo : we can probably reduce the period of the recent set as we are limited by the maximum delay between two consecutive steps, not the delay between booking and contract
    train_df = df[
        df[steps.index[0]] >= (begin_pred - pd.to_timedelta(n_training_days, unit='days'))]

    recent_df = df[df[steps.index[0]] >= (begin_pred - pd.to_timedelta(n_recent_days, unit='days'))]
    mask = (recent_df[steps.index] < begin_pred) & (recent_df[steps.index].notnull())
    recent_df.loc[:, steps.index] = recent_df[steps.index].where(mask)

    return [train_df, recent_df]


def predict_bookings(fact_past_bookings):
    """
    predicts the upcoming bookings per day, starting at begin_pred
    :param fact_past_bookings:
    :return:ts_first_step_pred : None in case of failure. otherwise a Series defined over range_pred_day
    predictor.own_yearly_seasonality : None in case it uses the default or faillure
    """
    # Predict bookings
    # contains first step regions that have data in the past #defined over beginning-begin_pred -1
    ts_first_step = get_count(fact_past_bookings, steps, steps.index[0])
    predictor = Ts_predictor(ts_first_step,
                             begin_pred,
                             end_pred,
                             range_pred_day,
                             range_pred_week,
                             )
    ts_first_step_pred = predictor.predict()  # defined over range_pred_day

    return ts_first_step_pred


def predict_next_steps(fact_past_bookings, ts_first_step_pred, default_distribs):
    """
    receives as input the preprocessed dataframe of events of a single geography. this dataframe contains
    only events with booking dates prior to begin_pred.
    outputs the dataframe of predicted kpis after begin_pred

    :param fact_past_bookings:
    :param default_distribs:
    :param ts_first_step_pred: assumed to be not None (the prediction of the TS worked)
    :return:
    """
    train_df, recent_df = split_train_recent(fact_past_bookings, n_training_days, n_recent_days)
    geo_funnel = Funnel(steps,  # deduplication_col	order	predict_with	step	q_threshold
                        train_df,
                        begin_pred=begin_pred,
                        end_pred=end_pred,
                        range_recent_day=range_recent_day,
                        range_pred_day=range_pred_day,
                        default_distribs=default_distribs,
                        min_samples=min_samples,
                        max_samples=max_samples,
                        )
    regional_kpi_pred = geo_funnel.predict(recent_df, ts_first_step_pred)  # includes the first step

    # kpis predicted, after begin_pred (included)
    regional_kpi_pred = regional_kpi_pred.loc[begin_pred:]

    return [regional_kpi_pred, geo_funnel.distribs]


def compute_all_predictions(fact_past_bookings):
    # for every all>city>region, go down the hierarchy of folders, taking default parameters if they exist
    # make the prediction for that region, write it in the folder as pickle

    geo_levels = fact_past_bookings.groupby('region_code').agg({'city_name': 'first'}).reset_index()
    geo_levels.columns = ['region', 'city']
    cities = [city for city in geo_levels.city.unique().tolist() if city != 'NONE']
    regions = [region for region in geo_levels.region.unique().tolist() if region != 'NONE']

    city = 'all'
    region = 'all'
    _logger.info(city + ' ' + region)
    fact_regional = fact_past_bookings.copy()
    bookings_pred = predict_bookings(fact_regional)
    write_to_s3(bucket_ds,
                bookings_pred,
                'monitoring/%s/%s/%s/bookings_pred' % (begin_pred.strftime("%Y-%m-%d"), city, region),
                to_csv=True, to_pickle=True)
    default_distribs = None
    kpis_prediction, distribs = predict_next_steps(fact_regional, bookings_pred, default_distribs)
    kpis_prediction['city'] = city
    kpis_prediction['region'] = region
    write_to_s3(bucket_ds,
                kpis_prediction,
                'monitoring/%s/%s/%s/kpis_prediction' % (begin_pred.strftime("%Y-%m-%d"), city, region),
                to_csv=True, to_pickle=True)
    write_to_s3(bucket_ds,
                distribs,
                'monitoring/%s/%s/%s/distribs' % (begin_pred.strftime("%Y-%m-%d"), city, region),
                to_csv=True, to_pickle=True)

    for city in cities:
        region = 'all'
        _logger.info(city + ' ' + region)
        fact_regional = fact_past_bookings[fact_past_bookings.city_name == city]
        bookings_pred = predict_bookings(fact_regional)
        if bookings_pred is not None:
            write_to_s3(bucket_ds,
                        bookings_pred,
                        'monitoring/%s/%s/%s/bookings_pred' % (begin_pred.strftime("%Y-%m-%d"), city, region),
                        to_csv=True, to_pickle=True)
            default_distribs = get_default_parameters(city, region)
            kpis_prediction, distribs = predict_next_steps(fact_regional, bookings_pred, default_distribs)
            if kpis_prediction is not None:
                kpis_prediction['city'] = city
                kpis_prediction['region'] = region
                write_to_s3(bucket_ds,
                            kpis_prediction,
                            'monitoring/%s/%s/%s/kpis_prediction' % (begin_pred.strftime("%Y-%m-%d"), city, region),
                            to_csv=True, to_pickle=True)
                write_to_s3(bucket_ds,
                            distribs,
                            'monitoring/%s/%s/%s/bookings_pred' % (begin_pred.strftime("%Y-%m-%d"), city, region),
                            to_csv=True, to_pickle=True)

    for region in regions:
        city = geo_levels.set_index('region').loc[region, 'city']
        _logger.info(city + ' ' + region)
        fact_regional = fact_past_bookings[fact_past_bookings.region_code == region]
        bookings_pred = predict_bookings(fact_regional)
        if bookings_pred is not None:
            write_to_s3(bucket_ds,
                        bookings_pred,
                        'monitoring/%s/%s/%s/bookings_pred' % (begin_pred.strftime("%Y-%m-%d"), city, region),
                        to_csv=True, to_pickle=True)
            default_distribs = get_default_parameters(city, region)
            kpis_prediction, distribs = predict_next_steps(fact_regional, bookings_pred, default_distribs)
            if kpis_prediction is not None:
                kpis_prediction['city'] = city
                kpis_prediction['region'] = region
                write_to_s3(bucket_ds,
                            kpis_prediction,
                            'monitoring/%s/%s/%s/kpis_prediction' % (begin_pred.strftime("%Y-%m-%d"), city, region),
                            to_csv=True, to_pickle=True)
                write_to_s3(bucket_ds,
                            distribs,
                            'monitoring/%s/%s/%s/distribs' % (begin_pred.strftime("%Y-%m-%d"), city, region),
                            to_csv=True, to_pickle=True)
    return [geo_levels, cities, regions]


def forecast_to_csv(fact_past_bookings, geo_levels, cities, regions):
    # get kpis for fact past
    # they are needed here because we will compute new columns such as
    # monthly counts before deleting the dates from the past
    kpi_past_demand = get_kpis(fact_past_bookings, steps, geo_levels, cities, regions)
    # we should remove from this dataframe the dates that are in the future (including begin_pred)
    kpi_past_demand = kpi_past_demand.loc[(slice(None), slice(None), pd.date_range(
        start='20130101', end=begin_pred - pd.to_timedelta(1, unit='days'))), :]

    # get kpis of the prediction.
    # these kpis include both the predicted bookings, the next steps that those
    # predicted bookings will have, and the next steps of the already-initiated processes
    kpi_pred_demand = pd.DataFrame()

    city = 'all'
    region = 'all'
    _logger.info('getting ' + city + ' ' + region)
    kpis_prediction = get_prediction(city, region, begin_pred)
    if kpis_prediction is not None:
        kpi_pred_demand = kpis_prediction

    for city in cities:
        region = 'all'
        _logger.info('getting ' + city + ' ' + region)
        kpis_prediction = get_prediction(city, region, begin_pred)
        if kpis_prediction is not None:
            kpi_pred_demand = pd.concat([kpi_pred_demand, kpis_prediction])

    for region in regions:
        city = geo_levels.set_index('region').loc[region, 'city']
        _logger.info('getting ' + city + ' ' + region)
        kpis_prediction = get_prediction(city, region, begin_pred)
        if kpis_prediction is not None:
            kpi_pred_demand = pd.concat([kpi_pred_demand, kpis_prediction])

    kpi_pred_demand = kpi_pred_demand.reset_index().set_index(['city', 'region', 'date'])

    _logger.info('combine past and predictions')
    output = pd.concat([kpi_past_demand, kpi_pred_demand]).sort_index()

    _logger.info('format the output')
    # names of columns
    count_cols = [step[3:] for step in steps.index.tolist()]  # remove dt_ from col names
    count_weekly_cols = [step + '_weekly_count' for step in count_cols]
    count_monthly_cols = [step + '_monthly_count' for step in count_cols]
    count_yearly_cols = [step + '_yearly_count' for step in count_cols]
    output.columns = count_cols

    # compute the weekly monthly and yearly count
    output_count_weekly = pd.DataFrame()
    output_count_yearly = pd.DataFrame()
    output_count_monthly = pd.DataFrame()
    # for every unique combination of city and region,
    # filter the dataframe, drop the region, and compute weekly monthly and yearly
    for (city, region), row in output.reset_index()[['city', 'region']].drop_duplicates().set_index(
            ['city', 'region']).iterrows():
        region_output_count_yearly = output.loc[(city, region, slice(None)), count_cols].reset_index(
            level=['city', 'region'], drop=True).resample('AS').transform('cumsum')
        region_output_count_yearly.columns = count_yearly_cols
        region_output_count_yearly['region'] = region
        region_output_count_yearly['city'] = city
        output_count_yearly = pd.concat([output_count_yearly, region_output_count_yearly])

        region_output_count_monthly = output.loc[(city, region, slice(None)), count_cols].reset_index(
            level=['city', 'region'], drop=True).resample('M').transform('cumsum')
        region_output_count_monthly.columns = count_monthly_cols
        region_output_count_monthly['region'] = region
        region_output_count_monthly['city'] = city
        output_count_monthly = pd.concat([output_count_monthly, region_output_count_monthly])

        region_output_count_weekly = output.loc[(city, region, slice(None)), count_cols].reset_index(
            level=['city', 'region'], drop=True).resample('W-MON', closed='left').transform('cumsum')
        region_output_count_weekly.columns = count_weekly_cols
        region_output_count_weekly['region'] = region
        region_output_count_weekly['city'] = city
        output_count_weekly = pd.concat([output_count_weekly, region_output_count_weekly])
    output_count_yearly = output_count_yearly.set_index(['city', 'region'], append=True).reorder_levels([1, 2, 0])
    output_count_monthly = output_count_monthly.set_index(['city', 'region'], append=True).reorder_levels([1, 2, 0])
    output_count_weekly = output_count_weekly.set_index(['city', 'region'], append=True).reorder_levels([1, 2, 0])

    output = pd.concat([output, output_count_yearly, output_count_monthly, output_count_weekly], axis=1)

    # remove data from the past
    range_pred_day = pd.date_range(begin_pred, end_pred, freq='D', closed='left')
    output = output.loc[(slice(None), slice(None), range_pred_day), :].copy()

    # add timestamp
    dt_timestamp = str(pd.Timestamp.now(tz='America/Sao_Paulo')).split('.')[0]
    output['dt_timestamp'] = dt_timestamp

    output = output.reset_index()

    # add long region name
    long_region_name_query = '''select distinct long_region_name, region_code from dim_region'''
    table_long_region_name = BaseETL.from_db_query(
        db_enum=EnumDB.BI_DW,
        query=long_region_name_query
    )
    df_long_region_name = petl.todataframe(table_long_region_name)
    df_long_region_name = df_long_region_name[
        df_long_region_name.region_code.notnull() & (df_long_region_name.region_code != '')]
    df_long_region_name = df_long_region_name.append({'region_code': 'all', 'long_region_name': 'all'},
                                                     ignore_index=True)  # .set_index('region_code')
    df_long_region_name = df_long_region_name.set_index('region_code')
    output = output.merge(df_long_region_name, how='left', left_on='region', right_index=True)

    # rename using ribs convention
    output = output.rename(columns={'region': 'region_code',
                                    'long_region_name': 'region'})

    # reorder columns to fit the DDL of rib in athena
    ddl = ['city',
           'region',
           'date',
           'booking_created',
           'effective_visit',
           'offer_first_sent',
           'offer_approved',
           'tenant_first_document_sent',
           'credit_analysis_init',
           'credit_analysis_approved',
           'signature_notcancelled',
           'booking_created_yearly_count',
           'effective_visit_yearly_count',
           'offer_first_sent_yearly_count',
           'credit_analysis_init_yearly_count',
           'offer_approved_yearly_count',
           'tenant_first_document_sent_yearly_count',
           'credit_analysis_approved_yearly_count',
           'signature_notcancelled_yearly_count',
           'booking_created_monthly_count',
           'effective_visit_monthly_count',
           'offer_first_sent_monthly_count',
           'credit_analysis_init_monthly_count',
           'offer_approved_monthly_count',
           'tenant_first_document_sent_monthly_count',
           'credit_analysis_approved_monthly_count',
           'signature_notcancelled_monthly_count',
           'booking_created_weekly_count',
           'effective_visit_weekly_count',
           'offer_first_sent_weekly_count',
           'offer_approved_weekly_count',
           'tenant_first_document_sent_weekly_count',
           'credit_analysis_init_weekly_count',
           'credit_analysis_approved_weekly_count',
           'signature_notcancelled_weekly_count',
           'dt_timestamp', ]
    unused_cols = [col for col in output.columns if col not in ddl]
    output = output[ddl + unused_cols]

    # finally, write the csv
    _logger.info('writing csv in s3')
    write_to_s3(bucket_ds, output, 'demand_funnel_' + dt_timestamp.split(' ')[0], to_csv=True, to_pickle=False)
    write_to_s3(bucket_dl, output, 'demand_funnel', to_csv=True, to_pickle=False, path='raw/growth/demand_prediction/')


def demand_forecast():
    _logger.info('loading fact')
    fact_past_bookings = load_fact(begin_pred)
    _logger.info('computing predictions for all regions')
    geo_levels, cities, regions = compute_all_predictions(fact_past_bookings)  # writes in s3 (pickles)
    _logger.info('writing predictions to csv')
    forecast_to_csv(fact_past_bookings, geo_levels, cities, regions)  # reads in s3, formats, writes csv in s3


if __name__ == "__main__":
    demand_forecast()

# DAG

dag = DAG(
    dag_id=MAIN_DAG_NAME,
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1,
    catchup=False
)

BaseDAG.build_quintoandar_python_operator(
    dag=dag,
    task_id='demand_forecast',
    python_callable=demand_forecast
)
