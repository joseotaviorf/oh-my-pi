import pandas as pd
import boto3
import io

def write_to_s3(obj, filename):
    """write dataframe obj to s3 (in the ts/monitoring directory)"""
    if type(obj)== pd.DataFrame:
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

    return daily  # return a series

# def get_all_counts(self, df):
#     all_counts = pd.DataFrame
#     for step in self.steps.index().tolist():
#         all_counts = pd.concat([all_counts, self.get_count(df, step)], axis=1)
#
#     return all_counts

def daily_to_weekly(ts):
    return ts.resample('W-MON', closed='left', label='left').sum()

def get_geo_levels(df):
    # individual regions
    geo_levels = df.groupby(['city_name', 'region_code']).size().reset_index()
    geo_levels.columns = ['city', 'region', 'cnt']

    # # cities
    # cities = df.groupby(['city_name']).size().reset_index()
    # cities.columns = ['city', 'cnt']
    # cities['region'] = 'all'
    # cities = cities[['city', 'region', 'cnt']]
    # geo_levels = pd.concat([regions, cities])

    # # all of quintoandar
    # geo_levels = regions.append({'city': 'all',
    #                           'region': 'all',
    #                           'cnt': df.shape[0]}, ignore_index=True)
    return geo_levels

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