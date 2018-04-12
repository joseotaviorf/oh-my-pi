from kpi_forecast.predictor import Predictor
from kpi_forecast.preprocessor import Preprocessor
from kpi_forecast.steps_demand import steps_demand
# from base_etl import BaseETL
# from enum_db import EnumDb
# from kpi_forecast.query_demand import query_demand
# import petl

import pandas as pd

# parameters of the script
begin_pred = pd.Timestamp('2018-01-15') #must be a monday #todo : why?
end_pred = begin_pred + pd.to_timedelta(125, unit='days') #must be a sunday

# table_demand = BaseETL.from_db_query(
#         db_enum=EnumDb.BI_DW,
#         query=query_demand
#     )
# df_demand = petl.todataframe(table_demand);
# df_demand.to_pickle('df_demand')
df_demand = pd.read_pickle('df_demand')

preprocessor_demand = Preprocessor(steps_demand)
df_demand2 = preprocessor_demand.preprocess(df_demand)
# df_demand2.to_pickle('df_demand2')
#df_demand2 = pd.read_pickle('df_demand2')
#df_demand3 = pd.read_pickle('df_demand3') #10% of lines

regions_demand = preprocessor_demand.get_regions(df_demand2)
# kpis = preprocessor_demand.get_kpis(df_demand2, regions_demand)

# split df_demand into past and future bookings (putting ourselves at the beginning of begin_pred)

# the predictor takes the dataframe,
# provides booking history to Ts_predictor
# and then recent events + booking prediction to the funnel
predictor_demand = Predictor(df_demand2,
                             steps_demand,
                             regions_demand,
                            )
kpi_pred_demand = predictor_demand.predict(
    begin_pred, #must be a monday #pd.Timestamp('2018-01-29') #todo : why?
    end_pred, #must be a sunday,
    n_training_days=63, #hard limit on the days we do not want to consider for creating distributions
    n_recent_days=21,
    rolavg_duration = 90,
    max_samples = 4000,
    min_samples = 1000)

# compute the kpis for past, future and our prediction
# kpis for bookings made before begin_pred
kpi_past_demand = preprocessor_demand.get_kpis(predictor_demand.past_df, regions_demand)
kpi_past_demand = kpi_past_demand.reset_index(level='date').query("date < '%s'" %begin_pred.strftime("%Y-%m-%d")).set_index('date', append=True)
# kpis for bookings made after begin_pred
kpi_future_demand = preprocessor_demand.get_kpis(predictor_demand.future_df, regions_demand)
# kpis predicted after begin_pred
kpi_pred_demand = kpi_pred_demand.reset_index(level='date').query("date >= '%s'" %begin_pred.strftime("%Y-%m-%d")).set_index('date', append=True)