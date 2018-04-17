import pandas as pd

from bietlejuice.jobs.new_etl.kpi_forecast.funnel import Funnel
from bietlejuice.jobs.new_etl.kpi_forecast.helpers import get_count, write_to_s3, get_file_from_s3
from bietlejuice.jobs.new_etl.kpi_forecast.preprocessor import Preprocessor
from bietlejuice.jobs.new_etl.kpi_forecast.steps_demand import steps
from bietlejuice.jobs.new_etl.kpi_forecast.ts_predictor import Ts_predictor

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDb
from bietlejuice.jobs.new_etl.kpi_forecast.query_demand import query_demand
import petl


# parameters of the script
begin_pred = pd.Timestamp('2018-04-16')  # must be a monday #todo : why?
end_pred = begin_pred + pd.to_timedelta(125, unit='days')  # must be a sunday
n_training_days = 63  # hard limit on the days we do not want to consider for creating distributions
n_recent_days = 21
rolavg_duration = 120
min_samples = 500
max_samples = 5000
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
            db_enum=EnumDb.BI_DW,
            query=query_demand
        )
    fact = petl.todataframe(table_demand);
    fact.to_pickle('fact')

    # shortcut :
    # fact = pd.read_pickle('fact')

    preprocessor_demand = Preprocessor(steps)
    fact = preprocessor_demand.preprocess(fact)
    fact.to_pickle('fact_preprocessed')
    write_to_s3(fact, '%s/fact' % (begin_pred.strftime("%Y-%m-%d")))

    #shortcut :
    # fact = pd.read_pickle('fact_preprocessed')

    # split df_demand into past and future bookings (putting ourselves at the beginning of begin_pred)
    fact_past_bookings = fact[(fact[steps.index[0]] < begin_pred)]
    write_to_s3(fact_past_bookings, '%s/fact_past_bookings' % (begin_pred.strftime("%Y-%m-%d")))

    return fact_past_bookings


def get_default_parameters(city, region):
    default_yearly_seasonality = None
    default_distribs = None

    if city == 'all':
        # global level. no default
        pass

    elif region == 'all':
        # city level. only possible default is the global level. try to find yearly and weekly seasonality
        if get_file_from_s3('KPI_predictor/monitoring/%s/all/all/own_yearly_seasonality.p'%(begin_pred.strftime("%Y-%m-%d")),
                            'global_default_yearly_seasonality.p'):
            default_yearly_seasonality = pd.read_pickle('global_default_yearly_seasonality.p')

        if get_file_from_s3('KPI_predictor/monitoring/%s/all/all/distribs.p'%(begin_pred.strftime("%Y-%m-%d")),
                            'global_default_distribs.p'):
            default_distribs = pd.read_pickle('global_default_distribs.p')

    else:
        #region level. default is city level, if not available then use the global level
        if get_file_from_s3('KPI_predictor/monitoring/%s/%s/all/own_yearly_seasonality.p'%(begin_pred.strftime("%Y-%m-%d"),city),
                            'city_default_yearly_seasonality.p'):
            default_yearly_seasonality = pd.read_pickle('city_default_yearly_seasonality.p')
        elif get_file_from_s3('KPI_predictor/monitoring/%s/all/all/own_yearly_seasonality.p'%(begin_pred.strftime("%Y-%m-%d")),
                              'global_default_yearly_seasonality.p'):
            default_yearly_seasonality = pd.read_pickle('global_default_yearly_seasonality.p')

        if get_file_from_s3('KPI_predictor/monitoring/%s/%s/all/distribs.p'%(begin_pred.strftime("%Y-%m-%d"),city),
                            'city_default_distribs.p'):
            default_distribs = pd.read_pickle('city_default_distribs.p')
        elif get_file_from_s3('KPI_predictor/monitoring/%s/all/all/distribs.p'%(begin_pred.strftime("%Y-%m-%d")),
                              'global_default_distribs.p'):
            default_distribs = pd.read_pickle('global_default_distribs.p')

    return [default_yearly_seasonality, default_distribs]


def split_train_recent(df, n_training_days=63, n_recent_days=21):
    """
    we set a limit between training data (all bookings older than a threshold date,
    for which we are sure the process is finished) and current data (other bookings)
    n_training_days : hard limit on the days we do not want to consider for creating distributions
    """

    # todo : we can probably reduce the period of the recent set as we are limited by the maximum delay between two consecutive steps, not the delay between booking and contract
    # todo : check if we need the copy()
    train_df = df[
        df[steps.index[0]] >= (begin_pred - pd.to_timedelta(n_training_days, unit='days'))].copy()
    recent_df = df[
        df[steps.index[0]] >= (begin_pred - pd.to_timedelta(n_recent_days, unit='days'))].copy()

    return [train_df, recent_df]


def predict_bookings(fact_past_bookings, default_yearly_seasonality):
    """
    predicts the upcoming bookings per day, starting at begin_pred
    :param fact_past_bookings:
    :param default_yearly_seasonality:
    :return:ts_first_step_pred : None in case of failure. otherwise a Series defined over range_pred_day
    predictor.own_yearly_seasonality : None in case it uses the default or faillure
    """

    ### Predict bookings
    # contains first step regions that have data in the past #defined over beginning-begin_pred -1
    ts_first_step = get_count(fact_past_bookings, steps, steps.index[0])
    predictor = Ts_predictor(ts_first_step,
                             begin_pred,
                             end_pred,
                             range_pred_day,
                             range_pred_week,
                             )
    ts_first_step_pred = predictor.predict(
        model_weekly_seasonality=model_weekly_seasonality,
        model_yearly_seasonality=model_yearly_seasonality,
        default_yearly_seasonality=default_yearly_seasonality,
        rolavg_duration=rolavg_duration,
    )  # defined over range_pred_day

    return [ts_first_step_pred, predictor.own_yearly_seasonality]


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

    geo_levels = fact_past_bookings.groupby('region_code').agg({'city_name':'first'}).reset_index()
    geo_levels.columns = ['region', 'city']
    cities = [city for city in geo_levels.city.unique().tolist() if city!='NONE']
    regions = [region for region in geo_levels.region.unique().tolist() if region!='NONE']

    city = 'all'
    region = 'all'
    print city + ' ' + region
    fact_regional = fact_past_bookings
    default_yearly_seasonality, default_distribs = [None, None]
    bookings_pred, own_yearly_seasonality = predict_bookings(fact_regional, default_yearly_seasonality)
    write_to_s3(bookings_pred, '%s/%s/%s/bookings_pred' %(begin_pred.strftime("%Y-%m-%d"),city,region))
    write_to_s3(own_yearly_seasonality, '%s/%s/%s/own_yearly_seasonality' %(begin_pred.strftime("%Y-%m-%d"),city,region))

    kpis_prediction, distribs = predict_next_steps(fact_regional, bookings_pred, default_distribs)
    kpis_prediction['city'] = city
    kpis_prediction['region'] = region
    write_to_s3(kpis_prediction,'%s/%s/%s/kpis_prediction' %(begin_pred.strftime("%Y-%m-%d"),city,region))
    write_to_s3(distribs, '%s/%s/%s/distribs' %(begin_pred.strftime("%Y-%m-%d"),city,region))

    for city in cities:
        region = 'all'
        print city + ' ' + region
        fact_regional = fact_past_bookings[fact_past_bookings.city_name == city]
        default_yearly_seasonality, default_distribs = get_default_parameters(city, region)
        bookings_pred, own_yearly_seasonality = predict_bookings(fact_regional, default_yearly_seasonality)
        if bookings_pred is not None :
            write_to_s3(bookings_pred, '%s/%s/%s/bookings_pred' %(begin_pred.strftime("%Y-%m-%d"),city,region))
            write_to_s3(own_yearly_seasonality, '%s/%s/%s/own_yearly_seasonality' %(begin_pred.strftime("%Y-%m-%d"),city,region))
            kpis_prediction, distribs = predict_next_steps(fact_regional, bookings_pred, default_distribs)
            if kpis_prediction is not None:
                kpis_prediction['city'] = city
                kpis_prediction['region'] = region
                write_to_s3(kpis_prediction, '%s/%s/%s/kpis_prediction' %(begin_pred.strftime("%Y-%m-%d"),city,region))
                write_to_s3(distribs, '%s/%s/%s/bookings_pred' %(begin_pred.strftime("%Y-%m-%d"),city,region))

    for region in regions:
        city = geo_levels.set_index('region').loc[region,'city']
        print city + ' ' + region
        fact_regional = fact_past_bookings[fact_past_bookings.region_code == region]
        default_yearly_seasonality, default_distribs = get_default_parameters(city, region)
        bookings_pred, own_yearly_seasonality = predict_bookings(fact_regional, default_yearly_seasonality)
        if bookings_pred is not None:
            write_to_s3(bookings_pred, '%s/%s/%s/bookings_pred' %(begin_pred.strftime("%Y-%m-%d"),city,region))
            write_to_s3(own_yearly_seasonality, '%s/%s/%s/own_yearly_seasonality' %(begin_pred.strftime("%Y-%m-%d"),city,region))
            kpis_prediction, distribs = predict_next_steps(fact_regional, bookings_pred, default_distribs)
            if kpis_prediction is not None:
                kpis_prediction['city'] = city
                kpis_prediction['region'] = region
                write_to_s3(kpis_prediction, '%s/%s/%s/kpis_prediction' %(begin_pred.strftime("%Y-%m-%d"),city,region))
                write_to_s3(distribs, '%s/%s/%s/distribs' %(begin_pred.strftime("%Y-%m-%d"),city,region))


if __name__ == "__main__":
    fact_past_bookings = load_fact(begin_pred)
    compute_all_predictions(fact_past_bookings)
