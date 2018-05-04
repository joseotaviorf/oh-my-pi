import io

import boto3
import pandas as pd


def find_best_subset(df):
    """
    for a given dataframe of subsets of the same proposal, returns the proposal_id_subset of the best subset that meets the hard rules, and if there is none it just returns the best subset

    :param df:
    :return:
    """
    respect_hard_rules = df[(df.income_over_package_sum >= 2.5) & (df.boavista_srccrdalinseg_max >= 550)]
    if respect_hard_rules.shape[0] > 0:
        return \
            respect_hard_rules.sort_values(['risk_level', 'score_cardif', 'score_5a'],
                                           ascending=[True, False, False]).iloc[
                0]['proposal_id_subset']
    else:
        return df.sort_values(['risk_level', 'score_cardif', 'score_5a'], ascending=[True, False, False]).iloc[0][
            'proposal_id_subset']


def write_to_s3(obj, filename):
    """
    write obj in s3 (in the ts/monitoring directory)
    dataframes are converted to .csv, strings to .txt

    :param obj: dataframe or string
    :param filename: folder and filename where we should write the file (clean/tenant_screening/monitoring/<filename>
    :return:
    """
    s3 = boto3.resource('s3')

    if isinstance(obj, pd.DataFrame):
        obj = obj.copy()  # we don't want to alter the original object
        # we want to force all dates to be written in the format '%Y-%m-%d %H:%M:%S', so we convert them to string first
        for col, dtype in obj.dtypes.iteritems():
            if str(dtype) == 'datetime64[ns]':
                obj[col] = obj[col].dt.strftime('%Y-%m-%d %H:%M:%S').replace(to_replace='NaT', value='')
            if str(dtype) in ['uint8', 'int64', 'float64']:  # convert float to string and null to blank strings
                obj[col] = obj[col].astype(str).replace(to_replace='nan', value='')
            if str(dtype) == 'bool':
                obj[col] = obj[col].astype(
                    str).str.upper()  # hopefully uppercase is automatically seen as boolean by PBI

        csv_buffer = io.BytesIO()
        obj.to_csv(csv_buffer, index=False, sep=',', encoding='utf-8', header=False)
        s3.Object('5a-datalake', 'clean/tenant_screening/monitoring/' + filename).put(
            Body=csv_buffer.getvalue())

    if isinstance(obj, str):
        txt_buffer = io.BytesIO(obj)
        s3.Object('5a-datalake', 'clean/tenant_screening/monitoring/' + filename).put(
            Body=txt_buffer.getvalue())


def create_sk_dates(df):
    """
    creates a new col for every datatime column. it will be used to link to the date table in PBI

    :param df: dataframe to which surrogate keys should be added
    :return:
    """
    for col, dtype in df.dtypes.iteritems():
        if str(dtype) == 'datetime64[ns]':
            df['sk_' + col] = df[col].dt.strftime('%Y%m%d').replace(
                {'NaT': ''})  # sk date is a string in dim_date so we keep it as a string here too

    return df


def generate_queries(df, table_name):
    """
    creates DDL for athena and query for PBI.
    the query automatically transforms the dates (that were written as strings in the csv) back into dates.

    :param df: dataframe that will be written in s3 and for which a ddl and query should be created
    :param table_name: name of the table in athena (not including tenantscreening_monitoring_) which should also be the name of the folder under 'monitoring' where the files are stored in s3
    :return:
    """
    df_converion = pd.DataFrame(
        [
            {
                'dtype': 'object',
                'athena_type': 'STRING',
                'pbi_query': '%s',
            },
            {
                'dtype': 'bool',  # written as True and False in csv
                'athena_type': 'STRING',  # eg: api_fairfax boolean,
                'pbi_query': "cast(if(%s = '', null, %s) as BOOLEAN) as %s",
            },
            {
                'dtype': 'uint8',
                'athena_type': 'STRING',
                'pbi_query': "cast(if(%s = '', null, %s) as INTEGER) as %s",
            },
            {
                'dtype': 'int64',
                'athena_type': 'STRING',
                'pbi_query': "cast(if(%s = '', null, %s) as INTEGER) as %s",
            },
            {
                'dtype': 'float64',
                'athena_type': 'STRING',
                'pbi_query': "cast(if(%s = '', null, %s) as DECIMAL) as %s",
            },
            {
                'dtype': 'datetime64[ns]',  # written as 2018-02-05 12:47:55.647508 in csv
                'athena_type': 'STRING',  # dates are in string columns in athena
                'pbi_query': "cast(regexp_extract(%s, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp) as %s",
            },

        ]
    )

    df_converion = df_converion.set_index('dtype')

    athena_ddl_cols = ''
    pbi_query_cols = ''
    for col, dtype in df.dtypes.iteritems():
        # if this is not the first column, add a comma and go to the new line
        if athena_ddl_cols != '':
            athena_ddl_cols += ',\n'
        if pbi_query_cols != '':
            pbi_query_cols += ',\n'

        athena_ddl_cols += (col + ' ' + df_converion.loc[str(dtype), 'athena_type'])
        pbi_query_cols += df_converion.loc[str(dtype), 'pbi_query'].replace('%s', col)

    # after the last column, simply go to the next line
    athena_ddl_cols += '\n'
    pbi_query_cols += '\n'

    athena_ddl_begin = 'CREATE EXTERNAL TABLE tenantscreening_monitoring_%s(' % table_name  # eg: originacao
    athena_ddl_end = """
    )
    ROW FORMAT SERDE
      'org.apache.hadoop.hive.serde2.OpenCSVSerde'
    WITH SERDEPROPERTIES (
      'quoteChar'='\"',
      'separatorChar'=',')
    STORED AS INPUTFORMAT
      'org.apache.hadoop.mapred.TextInputFormat'
    OUTPUTFORMAT
      'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
    LOCATION
      's3://5a-datalake/clean/tenant_screening/monitoring/%s'
    TBLPROPERTIES (
      'skip.header.line.count'='1',
      'transient_lastDdlTime'='1522344718')
      """ % table_name

    pbi_query_begin = """let
    Source = Odbc.Query("dsn=Athena - ODBC", "
    select """

    pbi_query_end = """
    from datalake_clean.tenantscreening_monitoring_%s
    ")
    in
    Source""" % table_name

    athena_ddl = athena_ddl_begin + athena_ddl_cols + athena_ddl_end
    pbi_query = pbi_query_begin + pbi_query_cols + pbi_query_end

    return [athena_ddl, pbi_query]
