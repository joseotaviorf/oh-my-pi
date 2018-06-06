import io
import gzip
import boto3
import botocore
import pandas as pd
import pickle
from qa_python_utils.default_logger import _logger

s3 = boto3.resource('s3')


def get_file_from_s3(bucket, file_name_s3, file_name_local):
    try:
        s3.Bucket(bucket).download_file(file_name_s3, file_name_local)
    except botocore.exceptions.ClientError as e:
        if e.response['Error']['Code'] == "404":
            _logger.info("The object does not exist.")
            return False
        else:
            raise
    return True


def write_to_s3(bucket, obj, filename, to_csv=True, to_pickle=False):
    """write dataframe obj to s3 (in the ts/monitoring directory)"""
    if (isinstance(obj, pd.DataFrame)) or (isinstance(obj, pd.Series)):

        s3 = boto3.resource('s3')
        obj = obj.copy()  # we don't want to alter the original object
        if to_csv is True:
            csv_buffer = io.BytesIO()
            obj.to_csv(csv_buffer, index=False, sep=',', encoding='utf-8', header=True)
            s3.Object(bucket, 'KPI_predictor/' + filename + '.csv').put(Body=csv_buffer.getvalue())
        if to_pickle is True:
            file = io.BytesIO()
            with gzip.GzipFile(fileobj=file, mode='w') as fp:
                fp.write(pickle.dumps(obj))
            s3.Object(bucket, 'KPI_predictor/' + filename + '.gz').put(
                Body=file.getvalue())


def get_prediction(city, region, begin_pred):
    begin_pred_string = begin_pred.strftime(format='%Y-%m-%d')
    flag = get_file_from_s3('5a-data-science',
                            'KPI_predictor/monitoring/%s/%s/%s/kpis_prediction.gz' % (begin_pred_string, city, region),
                            'kpis_prediction.gz')
    if flag is False:  # error getting the file
        return None
    else:
        kpis_prediction = pd.read_pickle('kpis_prediction.gz', compression='gzip')
        return kpis_prediction


def get_count(df, steps, step):
    """returns a series with the number of steps on each day. days with no steps are not included"""
    deduplication_col_step = steps.loc[step, 'deduplication_col']
    df_dedup = df.drop_duplicates(deduplication_col_step)  # returns a copy
    daily = df_dedup.groupby(df_dedup[step].dt.date).count().iloc[:, 0]
    daily.index = pd.DatetimeIndex(daily.index).rename('index')
    daily = daily.rename(step)

    return daily


def daily_to_weekly(ts):
    return ts.resample('W-MON', closed='left', label='left').sum()


# def get_kpis(df, regions, steps):
#     """not up to date"""
#     # we count as an instance of a step a row that remains after a deduplication by the key of that step
#     past = None
#     for step, row_step in steps.iterrows():
#         s_step = pd.DataFrame()
#         for (city, region), row in regions.iterrows():
#             if city == 'all':
#                 df_region = df.copy()
#             elif region == 'all':
#                 df_region = df[df.city_name == city]
#             else:
#                 df_region = df[df.region_code == region]
#             t = df_region.drop_duplicates(row_step.deduplication_col)
#             s = t.groupby(pd.to_datetime(t[step].dt.date)).size()
#             s = pd.DataFrame(s, columns=[step])
#             s.index = pd.MultiIndex.from_product([[city], [region], s.index],
#                                                  names=['city', 'region', 'date'])
#             s_step = pd.concat([s_step, s], axis=0)  # we put all regions together in a big column
#
#         if past is None:
#             past = s_step
#         else:
#             past = past.merge(s_step, how='outer', left_index=True, right_index=True).fillna(0.0)
#
#     past.columns = steps.index.tolist()
#     return past

def get_local_kpi(df_region, row_step, step, city, region):
    t = df_region.drop_duplicates(row_step.deduplication_col)
    s = t.groupby(pd.to_datetime(t[step].dt.date)).size()
    s = pd.DataFrame(s, columns=[step])
    s.index = pd.MultiIndex.from_product([[city], [region], s.index],
                                         names=['city', 'region', 'date'])
    return s


def get_kpis(df, steps, geo_levels, cities, regions):
    # we count as an instance of a step a row that remains after a deduplication by the key of that step
    past = None
    for step, row_step in steps.iterrows():
        s_step = pd.DataFrame()

        city = 'all'
        region = 'all'
        df_region = df.copy()
        s_step = get_local_kpi(df_region, row_step, step, city, region)

        for city in cities:
            region = 'all'
            df_region = df[df.city_name == city]
            s = get_local_kpi(df_region, row_step, step, city, region)
            s_step = pd.concat([s_step, s], axis=0)  # we put all regions together in a big column

        for region in regions:
            city = geo_levels.set_index('region').loc[region, 'city']
            df_region = df[df.region_code == region]
            s = get_local_kpi(df_region, row_step, step, city, region)
            s_step = pd.concat([s_step, s], axis=0)  # we put all regions together in a big column

        if past is None:
            past = s_step
        else:
            past = past.merge(s_step, how='outer', left_index=True, right_index=True).fillna(0.0)

    past.columns = steps.index.tolist()
    return past
