import pandas as pd
import boto3
import io
import botocore


s3 = boto3.resource('s3')
def get_file_from_s3(file_name_s3, file_name_local):
    bucket = '5a-data-science'
    try:
        s3.Bucket(bucket).download_file(file_name_s3, file_name_local)
    except botocore.exceptions.ClientError as e:
        if e.response['Error']['Code'] == "404":
            return False
        else:
            raise
    return True

def write_to_s3(obj, filename):
    """write dataframe obj to s3 (in the ts/monitoring directory)"""
    if (type(obj)== pd.DataFrame) or (type(obj) == pd.Series):
        s3 = boto3.resource('s3')
        obj = obj.copy()  # we don't want to alter the original object
        csv_buffer = io.BytesIO()
        obj.to_csv(csv_buffer, index=False, sep=',', encoding='utf-8', header=True)
        s3.Object('5a-data-science', 'KPI_predictor/monitoring/' + filename +'.csv').put(Body=csv_buffer.getvalue())

        pickle_buffer = io.BytesIO()
        obj.to_pickle(pickle_buffer)
        s3.Object('5a-data-science', 'KPI_predictor/monitoring/' + filename +'.p').put(Body=pickle_buffer.getvalue())

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

def get_kpis(df, regions, steps):
    """not up to date"""
    # we count as an instance of a step a row that remains after a deduplication by the key of that step
    past = None
    for step, row_step in steps.iterrows():
        s_step = pd.DataFrame()
        for (city, region), row in regions.iterrows():
            if city == 'all':
                df_region = df.copy()
            elif region == 'all':
                df_region = df[df.city_name == city]
            else:
                df_region = df[df.region_code == region]
            t = df_region.drop_duplicates(row_step.deduplication_col)
            s = t.groupby(pd.to_datetime(t[step].dt.date)).size()
            s = pd.DataFrame(s, columns=[step])
            s.index = pd.MultiIndex.from_product([[city], [region], s.index],
                                                 names=['city', 'region', 'date'])
            s_step = pd.concat([s_step, s], axis=0)  # we put all regions together in a big column

        if past is None:
            past = s_step
        else:
            past = past.merge(s_step, how='outer', left_index=True, right_index=True).fillna(0.0)

    past.columns = steps.index.tolist()
    return past