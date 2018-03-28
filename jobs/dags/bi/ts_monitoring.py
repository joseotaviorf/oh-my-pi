# -*- coding: utf-8 -*-
# Monitoring report
#
# Original file is located at
#     https://colab.research.google.com/drive/1BBX38O8SgnJ_nu25agplUKlR0cCk0AC4

import io
from datetime import datetime, timedelta

import boto3
import numpy as np
import pandas as pd
from airflow.models import DAG
from airflow.operators import PythonOperator
from jobs.dags.util import environment as env
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import _logger

MAIN_DAG_NAME = 'tenantScreening-monitoring-tables'
MAIN_START_DATE = datetime(2018, 3, 20)
MAIN_SCHEDULE_INTERVAL = timedelta(days=1)
bucket = env.get_airflow_env_var('bi-datalake-s3-bucket')

# global variables (api columns)
today = pd.Timestamp(pd.Timestamp.today(tz='Brazil/East').date())
client = AthenaClient(bucket)

col_string = ['proposal_id_subset',
              'name',
              'matrix_position',
              'request_ts',
              'source',
              'ym',
              'risk_level',
              'matrix_position_cardif',
              'matrix_position_5a'
              ]
col_bool = ['fullset', 'best_subset']
col_float = ['proposal_id',
             'score_5a',
             'score_cardif',
             'n_applicants', ]
variables_of_subset = ['age_max',
                       'age_mean',
                       'age_min',
                       'age_will_live',
                       'aonbps',
                       'aonpwl',
                       'available_income_after_crivo_max',
                       'available_income_after_crivo_mean',
                       'available_income_after_crivo_min',
                       'available_income_after_crivo_over_rent_sum',
                       'available_income_after_crivo_over_rent_will_live',
                       'available_income_after_crivo_sum',
                       'available_income_after_crivo_will_live',
                       'available_income_max',
                       'available_income_mean',
                       'available_income_min',
                       'available_income_over_rent_sum',
                       'available_income_over_rent_will_live',
                       'available_income_sum',
                       'available_income_will_live',
                       'boavista_srccrdalinseg_max',
                       'boavista_srccrdalinseg_mean',
                       'boavista_srccrdalinseg_min',
                       'income_after_crivo_max',
                       'income_after_crivo_mean',
                       'income_after_crivo_min',
                       'income_after_crivo_over_rent_sum',
                       'income_after_crivo_over_rent_will_live',
                       'income_after_crivo_sum',
                       'income_after_crivo_will_live',
                       'income_max',
                       'income_mean',
                       'income_min',
                       'income_over_package_g1',
                       'income_over_package_g2',
                       'income_over_package_g3',
                       'income_over_package_sum',
                       'income_over_package_will_live',
                       'income_over_rent_g1',
                       'income_over_rent_g2',
                       'income_over_rent_g3',
                       'income_over_rent_sum',
                       'income_over_rent_will_live',
                       'income_sum',
                       'income_will_live',
                       'is_moving',
                       'is_woman',
                       'is_woman_will_live',
                       'job_time_max',
                       'job_time_mean',
                       'job_time_min',
                       'marital_state_g1',
                       'marital_state_g2',
                       'marital_state_g3',
                       'motivation_g1',
                       'motivation_g2',
                       'motivation_g3',
                       'nbpsowl',
                       'origin_g1',
                       'origin_g2',
                       'origin_g3'
                       ]
variables_of_property = [
    'property_area',
    'property_bathrooms',
    'property_bedrooms',
    'property_condominium',
    'property_garages',
    'property_iptu',
    'property_package',
    'property_rent',
    'property_suites',
    'property_additional_costs',
    'residence_condition_alugado',
    'residence_condition_proprio',
    'residence_condition_familiares',
    'residence_time_max',
    'residence_time_min',
    'will_live', ]


# helpers

def find_best_subset(df):
    respect_hard_rules = df[(df.income_over_package_sum >= 2.5) & (df.boavista_srccrdalinseg_max >= 550)]
    if respect_hard_rules.shape[0] > 0:
        return \
            respect_hard_rules.sort_values(['risk_level', 'score_cardif', 'score_5a'],
                                           ascending=[True, False, False]).iloc[
                0]['proposal_id_subset']
    else:
        return df.sort_values(['risk_level', 'score_cardif', 'score_5a'], ascending=[True, False, False]).iloc[0][
            'proposal_id_subset']


def generate_queries(df):
    """generating queries
    create DDL for athena and query for PBI
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
                'athena_type': 'BOOLEAN',  # eg: api_fairfax boolean,
                'pbi_query': '%s',
            },
            {
                'dtype': 'uint8',
                'athena_type': 'INT',
                'pbi_query': '%s',
            },
            {
                'dtype': 'int64',
                'athena_type': 'INT',
                'pbi_query': '%s',
            },
            {
                'dtype': 'float64',
                'athena_type': 'FLOAT',
                'pbi_query': '%s',
            },
            {
                'dtype': 'datetime64[ns]',  # written as 2018-02-05 12:47:55.647508 in csv
                'athena_type': 'STRING',  # dates are in string columns in athena
                'pbi_query': "cast(regexp_extract(%s, '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}') as timestamp)",
            },

        ]
    )

    df_converion = df_converion.set_index('dtype')

    athena_ddl = ''
    pbi_query = ''
    for col, dtype in df.dtypes.iteritems():
        athena_ddl += (col + ' ' + df_converion.loc[str(dtype), 'athena_type'] + ",\n")
        pbi_query += (df_converion.loc[str(dtype), 'pbi_query'] % (col) + ' as ' + col + ',\n')

    return [athena_ddl, pbi_query]


def write_to_s3(obj, filename):
    """write to s3"""
    s3 = boto3.resource('s3')

    if type(obj) == pd.DataFrame:
        csv_buffer = io.BytesIO()
        obj.to_csv(csv_buffer, index=False, sep=',', encoding='utf-8', header=False)
        s3.Object('5a-datalake', 'clean/tenant_screening/monitoring/' + filename).put(
            Body=csv_buffer.getvalue())

    if type(obj) == str:
        txt_buffer = io.BytesIO(obj)
        s3.Object('5a-datalake', 'clean/tenant_screening/monitoring/' + filename).put(
            Body=txt_buffer.getvalue())


def create_sk_dates(df):
    for col, dtype in df.dtypes.iteritems():
        if str(dtype) == 'datetime64[ns]':
            df['sk_' + col] = df[col].dt.strftime('%Y%m%d').replace(
                {'NaT': ''})  # sk date is a string in dim_date so we keep it as a string here too

    return df


# import functions

def import_ebdb_proposta(client):
    # query made with akira and translated into presto
    sql_proposta_ebdb = '''
    select
        a.id as proposal_id,
      p.imovel_id,
      
      -- dates
        p.dataaprovacao as date_approval_5a,
        p.dataproposta as date_agreement, -- date the agreement is reached. the offer is accepted. documentation is not yet sent. exactly the same as criadoem in proposta
      -- p.dataparamudanca as date_mudanca, -- is always null. ignore
        from_unixtime(cast(r.timestamp as bigint)/1000) as date_start_of_analysis,
      
        p.statusDocumentacaoInq,
        (from_unixtime(cast(r.timestamp as bigint)/1000) - interval '2' hour) >= date('2018-02-01') as Fairfax
      
    from datalake_raw.ebdb_proposta p 
    join datalake_raw.ebdb_proposta_AUD a on a.id = p.id -- inner join by default
    join datalake_raw.ebdb_usuariorevisionentity r on a.REV = r.id 
    where 
        a.statusDocumentacaoInq_MOD = '1' and 
        a.statusDocumentacaoInq = 'AnaliseCardiff' 
    '''

    df_proposta_ebdb = client.execute_query_and_return_dataframe(sql_proposta_ebdb)

    # select one line per proposal, the one with the last date_start_of_analysis
    df_proposta_ebdb = df_proposta_ebdb.sort_values('date_start_of_analysis', ascending=False).groupby(
        'proposal_id').first()

    date_cols = ['date_agreement',
                 'date_approval_5a',
                 'date_start_of_analysis',
                 ]
    for date_col in date_cols:
        df_proposta_ebdb.loc[:, date_col] = pd.to_datetime(df_proposta_ebdb[date_col], yearfirst=True,
                                                           errors='coerce')  # format='%Y-%m-%d')

    df_proposta_ebdb['ym_date_agreement'] = pd.to_datetime(
        (df_proposta_ebdb['date_agreement'].dt.strftime("%Y%m") + '01').where(
            df_proposta_ebdb['date_agreement'].notnull(), other=np.nan))
    df_proposta_ebdb['ym_date_approval_5a'] = pd.to_datetime(
        (df_proposta_ebdb['date_approval_5a'].dt.strftime("%Y%m") + '01').where(
            df_proposta_ebdb['date_approval_5a'].notnull(), other=np.nan))
    df_proposta_ebdb['ym_date_start_of_analysis'] = pd.to_datetime(
        (df_proposta_ebdb['date_start_of_analysis'].dt.strftime("%Y%m") + '01').where(
            df_proposta_ebdb['date_start_of_analysis'].notnull(), other=np.nan))

    return df_proposta_ebdb


def import_sortinghat_proposal(client):
    sql_proposal_sh = '''
        SELECT *
        FROM datalake_raw.sortinghat_proposal proposal
        '''
    df_proposal_sh = client.execute_query_and_return_dataframe(sql_proposal_sh)

    # rename
    df_proposal_sh = df_proposal_sh.rename(columns={
        'id': 'proposal_id',
        'analysis_date': 'date_analysis',
        'created_at': 'date_creation',
        'updated_at': 'date_update'
    })

    # dates as datetime
    df_proposal_sh['date_analysis'] = pd.to_datetime(df_proposal_sh['date_analysis'])
    df_proposal_sh['date_creation'] = pd.to_datetime(df_proposal_sh['date_creation'])
    df_proposal_sh['date_update'] = pd.to_datetime(df_proposal_sh['date_update'])

    # take the last proposal in sh in case the same proposal was sent there multiple times
    df_proposal_sh = df_proposal_sh.sort_values(['proposal_id', 'date_creation', 'date_update'],
                                                ascending=[True, False, False]).groupby('proposal_id').first()

    # no analyst => not assigned
    df_proposal_sh.loc[:, 'analyst_name'] = df_proposal_sh.analyst_name.replace({'': 'not assigned'})
    df_proposal_sh.loc[:, 'supervisor_name'] = df_proposal_sh.supervisor_name.replace({'': 'not assigned'})

    col_string_to_float = [
        'score_5a',
        'score_5a_best_subset',
        'score_cardif',
        'score_cardif_best_subset']
    df_proposal_sh.loc[:, col_string_to_float] = df_proposal_sh.loc[:, col_string_to_float].replace(to_replace='',
                                                                                                    value=np.nan).astype(
        float)

    return df_proposal_sh


def import_sortinghat_proponent(client):
    sql_proponent_sh = '''
        SELECT 
        *
        FROM datalake_raw.sortinghat_proponent proponent
        '''
    df_proponent_sh = client.execute_query_and_return_dataframe(sql_proponent_sh)

    # proposal_id to float
    df_proponent_sh['proposal_id'] = df_proponent_sh.proposal_id.replace({'': np.nan}).astype(float)
    df_proponent_sh['gender'] = df_proponent_sh.gender.replace({'': 'unknown'})
    df_proponent_sh['marital_status'] = df_proponent_sh.marital_status.replace({'': 'unknown'})
    df_proponent_sh['income_nature'] = df_proponent_sh.income_nature.replace({'': 'unknown'})
    df_proponent_sh['location_motive'] = df_proponent_sh.location_motive.replace({'': 'unknown'})
    df_proponent_sh['state'] = df_proponent_sh.state.replace({'': 'unknown'})

    # variables from the first proponent. todo check that it is the same as in ebdb
    df_proponent_sh_first = df_proponent_sh.groupby('proposal_id').first()
    df_proponent_sh_first.columns = [col + '_first' for col in df_proponent_sh_first.columns]

    # dummies
    take_dummies = ['will_reside',
                    'income_nature',
                    'marital_status',
                    'gender',
                    'residence_condition',
                    'location_motive',
                    'state', ]
    df_proponent_sh_dummies = pd.get_dummies(df_proponent_sh[['proposal_id'] + take_dummies], columns=take_dummies)

    df_proponent_sh_dummies = df_proponent_sh_dummies.groupby('proposal_id').sum()
    df_proponent_sh_dummies.columns = [col + '_sum' for col in df_proponent_sh_dummies.columns]

    # merge first and dummies
    df_proponents_of_proposal = df_proponent_sh_first.merge(df_proponent_sh_dummies, left_index=True, right_index=True)

    return df_proponents_of_proposal


def import_api(client):
    sql_api = '''
    select *, cardinality(name) as n_applicants from datalake_raw.tenant_screening_processed
    -- where source='prod' -- change to prod
    '''
    df_api = client.execute_query_and_return_dataframe(sql_api)
    df_api.loc[:, col_float + variables_of_subset + variables_of_property] = df_api.loc[:,
                                                                             col_float + variables_of_subset + variables_of_property].replace(
        to_replace='', value=np.nan).astype(float)

    # take only production data
    df_api = df_api[df_api.source == 'prod']

    # create columns
    df_api['ym'] = df_api.ym.str.replace('-', '').astype(int)
    df_api['date_request_api'] = pd.to_datetime(df_api.request_ts, unit='s')
    df_api.drop('request_ts', axis=1, inplace=True)

    # keep only the last request for each application
    last_request_map = df_api[['proposal_id', 'date_request_api']].drop_duplicates().groupby(
        'proposal_id').max()  # correspondence table
    df_api_last = last_request_map.reset_index().merge(df_api, how='left', on=['proposal_id', 'date_request_api'])

    # correct best_subset column
    best_subset_map = df_api_last.groupby('proposal_id').apply(find_best_subset)
    best_subset_map.name = 'best_proposal_id_subset'
    df_api_last = df_api_last.merge(pd.DataFrame(best_subset_map), how='left', left_on='proposal_id', right_index=True)
    df_api_last['best_subset'] = (df_api_last['best_proposal_id_subset'] == df_api_last['proposal_id_subset'])

    # correct full subset column
    full_subset_map = df_api_last.sort_values(['proposal_id', 'n_applicants'], ascending=[False, False]).groupby(
        'proposal_id').proposal_id_subset.first()
    full_subset_map.name = 'full_proposal_id_subset'
    df_api_last = df_api_last.merge(pd.DataFrame(full_subset_map), how='left', left_on='proposal_id', right_index=True)
    df_api_last['full_subset'] = (df_api_last['full_proposal_id_subset'] == df_api_last['proposal_id_subset'])

    return df_api_last


def import_ebdb_contrato(client):
    # query made with akira and translated into presto
    sql_contrato_ebdb = '''
    select 
      c.id as contract_id,
      c.proposta_id as proposal_id,
      c.imovel_id,
      c.status,
      c.criadoem as date_creation, -- creation of the line in the table
      c.dataassinado as date_signature, -- signature of the contract
      c.datainicio as date_beginning, -- date the tenant can move in and we start to charge
      c.datafimcontratoprevisto date_fim_previsto, -- normal date of end of contract. always signature + 30m unless 2nd signature
      c.datarescisaoprevista date_rescisao_prevista, -- date in the future at which the contract will be stopped
      c.datarescisao date_rescisao, -- end of the contract that has already ended
      c.diamescobranca,
      c.garantia,
      c.valoraluguel,
      c.cidade,
      c.contractversion_id
    from datalake_raw.ebdb_contrato c
    where garantia='SeguroFairfax'
    '''
    df_contrato_ebdb = client.execute_query_and_return_dataframe(sql_contrato_ebdb)

    date_cols = ['date_creation',
                 'date_signature',
                 'date_beginning',
                 'date_rescisao',
                 'date_fim_previsto',
                 'date_rescisao_prevista']
    for date_col in date_cols:
        df_contrato_ebdb.loc[:, date_col] = pd.to_datetime(df_contrato_ebdb[date_col], yearfirst=True, errors='coerce')

    df_contrato_ebdb['ym_signature'] = pd.to_datetime(
        (df_contrato_ebdb['date_signature'].dt.strftime("%Y%m") + '01').where(
            df_contrato_ebdb['date_signature'].notnull(), other=np.nan))

    df_contrato_ebdb['planned_end_contract'] = pd.concat([
        df_contrato_ebdb.date_rescisao,
        df_contrato_ebdb.date_fim_previsto,
        df_contrato_ebdb.date_rescisao_prevista],
        axis=1).min(axis=1)
    df_contrato_ebdb['dob'] = ((pd.concat([today - pd.to_datetime(df_contrato_ebdb.date_signature.dt.date),
                                           df_contrato_ebdb.planned_end_contract - pd.to_datetime(
                                               df_contrato_ebdb.date_signature.dt.date)],
                                          axis=1).min(axis=1)) / pd.to_timedelta(1, unit='days')).fillna(
        0.0)  # if never signed we put 0

    df_contrato_ebdb = df_contrato_ebdb.set_index('contract_id')

    return df_contrato_ebdb


def import_invoices(client):
    sql_payments = '''
    Select distinct
      i.contract_id,
      i.amount,
      trim(i.year_month) as year_month,
      date(trim(i.tenant_due_date)) as tenant_due_date, 
      date(trim(i.tenant_paid_date)) as tenant_paid_date,
      trim(i.tenant_status) as tenant_status
    from datalake_clean.invoice i 
    where 
      trim("from")='Inquilino' 
      and trim("to")='Contrato' 
      and trim(item)='Aluguel' 
      and tenant_status in ('open', 'paid')
    '''  # todo understand the col 'blocked' and let someone review the query
    df_payments = client.execute_query_and_return_dataframe(sql_payments)

    df_payments['tenant_due_date'] = pd.to_datetime(df_payments['tenant_due_date'])
    df_payments['tenant_paid_date'] = pd.to_datetime(df_payments['tenant_paid_date'])

    delay_paid = (df_payments['tenant_paid_date'] - df_payments['tenant_due_date']) / pd.Timedelta('1 days')
    delay_open = (today - df_payments['tenant_due_date']) / pd.Timedelta(
        '1 days')  # we assume the db is up to date and the invoice still hasnt been paid today
    df_payments['delay'] = pd.concat([delay_paid, delay_open], axis=1).min(axis=1)
    df_payments['tenant_status_is_open'] = (df_payments['tenant_status'] == 'open')

    return df_payments


def compute_performance_kpis(**context):
    df_payments = context['task_instance'].xcom_pull(task_ids='import_invoices')

    thresholds = [1, 30, 50, 60, 90, 120, 150]
    # for every contract we determine the date at which it first became bad for a given threshold
    df_performance_threshold = pd.DataFrame()
    df_performance = pd.DataFrame()
    for cid in df_payments.contract_id.unique():
        contract = df_payments[df_payments.contract_id == cid].sort_values('year_month', ascending=True).copy()

        df_performance = df_performance.append({
            'contract_id': cid,
            'max_dpd_ever': contract.delay.max(),
            'sum_dpd_ever': contract[contract.delay > 0].delay.sum(),
            'max_dpd_current': contract[contract.tenant_status == 'open'].delay.max(),
            'sum_dpd_current': contract[(contract.tenant_status == 'open') & (contract.delay > 0)].delay.sum(),
            'last_invoice_dpd': contract.delay.iloc[-1],

            'n_issued_invoices': contract.year_month.nunique(),
            'n_paid_invoices': contract[contract.tenant_status == 'paid'].year_month.nunique(),
            'n_unpaid_invoices': contract[contract.tenant_status == 'open'].year_month.nunique(),

            'sum_rent_issued': contract.amount.sum(),
            'sum_rent_paid': contract[contract.tenant_status == 'paid'].amount.sum(),
            'sum_rent_unpaid': contract[contract.tenant_status == 'open'].amount.sum()
        }, ignore_index=True)
        for t in thresholds:
            # the goal is to determine the date at which the contract became bad according to the threshold t
            # we need to take the minimum date between:
            # - due date + t, for paid invoices that have a delay>=t
            candidates_all = (
                contract.loc[contract.delay >= t, 'tenant_due_date'] + pd.to_timedelta(t, unit='d')).tolist()
            thres_date = min(candidates_all) if len(candidates_all) > 0 else np.nan

            # determine if there are any unpaid invoices for more than t days
            candidates_unpaid = (
                contract.loc[
                    contract.tenant_status_is_open & (contract.delay >= t), 'tenant_due_date'] + pd.to_timedelta(t,
                                                                                                                 unit='d')).tolist()
            over_t = (
                len(
                    candidates_unpaid) > 0)  # the current status is over t if there is any open invoice with delay above t

            # write in df:
            df_performance_threshold = df_performance_threshold.append({
                'contract_id': cid,
                'threshold': t,
                'date_ever': thres_date,
                'status_over': over_t
            }, ignore_index=True)

    df_performance = df_performance.set_index('contract_id')

    df_performance_ever = df_performance_threshold.pivot(index='contract_id', columns='threshold', values='date_ever')
    df_performance_ever.columns = ['date_ever' + str(t) for t in thresholds]
    df_performance = df_performance.merge(df_performance_ever, left_index=True, right_index=True)

    df_performance_over = df_performance_threshold.pivot(index='contract_id', columns='threshold', values='status_over')
    df_performance_over.columns = ['over' + str(t) for t in thresholds]
    df_performance = df_performance.merge(df_performance_over, left_index=True, right_index=True)

    return df_performance


# Jonas tables

def compute_originacao(**context):
    df_proposta_ebdb = context['task_instance'].xcom_pull(task_ids='import_ebdb_proposta')
    df_contrato_ebdb = context['task_instance'].xcom_pull(task_ids='import_ebdb_contrato')
    df_proposal_sh = context['task_instance'].xcom_pull(task_ids='import_sortinghat_proposal')
    df_proponents_of_proposal = context['task_instance'].xcom_pull(task_ids='import_sortinghat_proponent')
    df_api_last = context['task_instance'].xcom_pull(task_ids='import_api')

    # for every proposal we give information related to the proposal, the last request sent to the api, the decision, etc

    # proposata of ebdb ################

    # managed by fairfax
    df_proposta_ebdb_prepared = df_proposta_ebdb[df_proposta_ebdb.Fairfax]  # select only fairfax propostas

    # select columns
    columns_to_keep_proposta_ebdb = [
        'imovel_id',
        'date_approval_5a',
        'date_agreement',
        'date_start_of_analysis',
        'statusdocumentacaoinq',
        'Fairfax'
    ]
    df_proposta_ebdb_prepared = df_proposta_ebdb_prepared[columns_to_keep_proposta_ebdb]

    # rename columns
    columns_names_proposta_ebdb = {col: 'proposta_' + col for col in columns_to_keep_proposta_ebdb}
    df_proposta_ebdb_prepared = df_proposta_ebdb_prepared.rename(columns=columns_names_proposta_ebdb)

    # merge with contrato ebdb (only to get the contract id)
    df_contrato_ebdb_prepared = df_contrato_ebdb.reset_index().set_index('proposal_id')[['contract_id']]

    # rename columns
    columns_names_ebdb_contrato = {'contract_id': 'contrato_contract_id'}
    df_contrato_ebdb_prepared = df_contrato_ebdb_prepared.rename(columns=columns_names_ebdb_contrato)

    # merge
    output_originacao = df_proposta_ebdb_prepared.merge(df_contrato_ebdb_prepared, how='left', left_index=True,
                                                        right_index=True)

    # df_proposal in sortinghat #####################

    # select columns
    columns_to_keep_sh = [
        'date_analysis',
        'score_5a',
        'score_5a_best_subset',
        'score_cardif',
        'score_cardif_best_subset',
        'status',
        'comment',
        'analyst_name',
        'supervisor_name',
        'rent_value',
        'condo_value',
        'iptu_value',
        'date_creation',
        'date_update',
        'home_area',
        'home_bathrooms',
        'home_bedrooms',
        'home_city',
        'home_garages',
        'home_region',
        'home_suites',
        'home_type',
        'home_zipcode',
        'drive_id'
    ]
    sh_proposal_prepared = df_proposal_sh[columns_to_keep_sh]

    # rename columns
    columns_names_sh_proposal = {col: 'sh_' + col for col in columns_to_keep_sh}
    sh_proposal_prepared = sh_proposal_prepared.rename(columns=columns_names_sh_proposal)

    # merge
    output_originacao = output_originacao.merge(sh_proposal_prepared, how='left', left_index=True, right_index=True)

    # df proponent of sh #####################

    # rename columns
    columns_names_sh_proponents = {col: 'sh_' + col for col in df_proponents_of_proposal.columns}
    sh_proponent_prepared = df_proponents_of_proposal.rename(columns=columns_names_sh_proponents)

    # merge #####################
    output_originacao = output_originacao.merge(sh_proponent_prepared, how='left', left_index=True, right_index=True)

    # constant columns #####################
    # take only the scored  applications with the full set  of applicants.
    df_api_last_big = df_api_last[df_api_last.full_subset == True]
    df_api_last_best = df_api_last[df_api_last.best_subset == True]

    # select columns
    relevant_api_cols_constant = variables_of_property + [
        'n_applicants',
        'date_request_api'
    ]
    api_last_constant = df_api_last_big[['proposal_id'] + relevant_api_cols_constant]

    # rename columns
    columns_names_api_cols_constant = {col: 'api_' + col for col in relevant_api_cols_constant}
    api_last_constant = api_last_constant.rename(columns=columns_names_api_cols_constant)

    # set index
    api_last_constant = api_last_constant.set_index('proposal_id')

    # merge
    output_originacao = output_originacao.merge(api_last_constant, how='left', left_index=True, right_index=True)

    # total subset of each proposal #####################
    # we want to include the value of the following columns for both the full and the best subset :
    # select columns
    relevant_api_cols_variable = variables_of_subset + [
        'proposal_id_subset',
        'score_cardif',
        'score_5a',
        'risk_level',
        'matrix_position',
        'matrix_position_cardif',
        'matrix_position_5a',
        'n_applicants']
    api_last_big = df_api_last_big[['proposal_id'] + relevant_api_cols_variable]

    # rename columns
    columns_names_api_cols_variable_full = {col: 'api_full_' + col for col in relevant_api_cols_variable}
    api_last_big = api_last_big.rename(columns=columns_names_api_cols_variable_full)

    # set index
    api_last_big = api_last_big.set_index('proposal_id')

    # merge
    output_originacao = output_originacao.merge(api_last_big, how='left', left_index=True, right_index=True)

    # best subset of each proposal #####################
    api_last_best = df_api_last_best[['proposal_id'] + relevant_api_cols_variable]

    # rename columns
    columns_names_api_cols_variable_best = {col: 'api_best_' + col for col in relevant_api_cols_variable}
    api_last_best = api_last_best.rename(columns=columns_names_api_cols_variable_best)

    # set index
    api_last_best = api_last_best.set_index('proposal_id')

    # merge
    output_originacao = output_originacao.merge(api_last_best, how='left', left_index=True, right_index=True)

    # new columns #####################

    # custom columns of Jonas
    output_originacao['api_decidido_no_fullset'] = np.nan
    output_originacao.loc[output_originacao.api_full_risk_level < 3, 'api_decidido_no_fullset'] = 1
    output_originacao.loc[output_originacao.api_full_risk_level >= 3, 'api_decidido_no_fullset'] = 0

    output_originacao['api_recomendacao_subset'] = 0
    output_originacao.loc[
        output_originacao.api_best_risk_level < output_originacao.api_full_risk_level, 'api_recomendacao_subset'] = 1

    # create sk_date for datetime types #####################

    for col, dtype in output_originacao.dtypes.iteritems():
        if str(dtype) == 'datetime64[ns]':
            output_originacao['sk_' + col] = output_originacao[col].dt.strftime('%Y%m%d').replace(
                {'NaT': ''})  # sk date is a string in dim_date so we keep it as a string here too

    # formatting ##
    # replace null values for float columns with 0
    for col, dtype in output_originacao.dtypes.iteritems():
        if str(dtype) in ['uint8', 'int64', 'float64']:
            output_originacao.loc[:, col] = output_originacao.loc[:, col].fillna(0.0)
    # remove commas from comments
    output_originacao.loc[:, 'sh_comment'] = output_originacao.loc[:, 'sh_comment'].str.replace(pat=',', repl=' ')
    output_originacao = output_originacao.reset_index()

    write_to_s3(output_originacao, 'originacao/originacao.csv')

    athena_ddl, pbi_query = generate_queries(output_originacao)
    write_to_s3(athena_ddl, 'queries/athena_originacao_ddl.txt')
    write_to_s3(pbi_query, 'queries/pbi_originacao_query.txt')

    _logger.info('originacao table computed with success!')


def compute_performance(**context):
    df_contrato_ebdb = context['task_instance'].xcom_pull(task_ids='import_ebdb_contrato')
    df_performance = context['task_instance'].xcom_pull(task_ids='compute_performance_kpis')

    # rename columns contrato
    columns_names_contrato_ebdb = {col: 'contrato_' + col for col in df_contrato_ebdb.columns}
    df_contrato_ebdb_prepared = df_contrato_ebdb.rename(columns=columns_names_contrato_ebdb)

    # rename columns_performance (coming from invoices db)
    columns_names_performance = {col: 'invoices_' + col for col in df_performance.columns}
    df_performance_prepared = df_performance.rename(columns=columns_names_performance)

    # join
    output_performance = df_contrato_ebdb_prepared.merge(df_performance_prepared, how='left', left_index=True,
                                                         right_index=True)
    # new columns ##

    # output_performance['days_contract_left'] =  (output_performance.dataassinado)
    output_performance['contrato_expected_total_contract_duration'] = (
        (
            output_performance.contrato_planned_end_contract - output_performance.contrato_date_signature) / pd.to_timedelta(
            1,
            unit='days')).fillna(
        915.0)  # 915 is 30 months

    cols_to_zero = [
        u'invoices_last_invoice_dpd',
        u'invoices_max_dpd_current',
        u'invoices_max_dpd_ever',
        u'invoices_n_issued_invoices',
        u'invoices_n_paid_invoices',
        u'invoices_n_unpaid_invoices',
        u'invoices_sum_dpd_current',
        u'invoices_sum_dpd_ever',
        u'invoices_sum_rent_issued',
        u'invoices_sum_rent_paid',
        u'invoices_sum_rent_unpaid',
        u'invoices_over1',
        u'invoices_over30',
        u'invoices_over50',
        u'invoices_over60',
        u'invoices_over90',
        u'invoices_over120',
        u'invoices_over150'
    ]

    output_performance.loc[:, cols_to_zero] = output_performance.loc[:, cols_to_zero].fillna(
        0)  # astype(str).replace({'NaT':''})

    output_performance['contrato_approx_n_invoices_expected'] = (
        output_performance['contrato_expected_total_contract_duration'] / 30.5).round()

    output_performance['approx_sum_rent_future_to_issue'] = (
                                                                output_performance.contrato_approx_n_invoices_expected - output_performance.invoices_n_issued_invoices) * output_performance.contrato_valoraluguel
    output_performance['approx_sum_rent_future_to_pay'] = (
                                                              output_performance.contrato_approx_n_invoices_expected - output_performance.invoices_n_paid_invoices) * output_performance.contrato_valoraluguel

    # create sk_date for datetime types
    output_performance = create_sk_dates(output_performance)

    # formatting ##
    # replace null dates by '' and store as string
    dates_ever = [u'invoices_date_ever1', u'invoices_date_ever30', u'invoices_date_ever50', u'invoices_date_ever60',
                  u'invoices_date_ever90', u'invoices_date_ever120', u'invoices_date_ever150']

    output_performance.loc[:, dates_ever] = output_performance.loc[:, dates_ever].astype(str).replace({'NaT': ''})

    output_performance = output_performance.reset_index()
    write_to_s3(output_performance, 'performance/performance.csv')

    athena_ddl, pbi_query = generate_queries(output_performance)
    write_to_s3(athena_ddl, 'queries/athena_performance_ddl.txt')
    write_to_s3(pbi_query, 'queries/pbi_performance_query.txt')

    _logger.info('performance table computed with success!')


# dag and operators

dag = DAG(
    dag_id=MAIN_DAG_NAME,
    default_args={
        'owner': 'Data Team',
        'wait_for_downstream': False,
        'depends_on_past': False
    },
    start_date=MAIN_START_DATE,
    schedule_interval=MAIN_SCHEDULE_INTERVAL,
    max_active_runs=1
)

dag_import_ebdb_proposta = PythonOperator(
    dag=dag,
    task_id='import_ebdb_proposta',
    func_command=import_ebdb_proposta,
    op_kwargs={'client': client}
)
dag_import_sortinghat_proposal = PythonOperator(
    dag=dag,
    task_id='import_sortinghat_proposal',
    func_command=import_sortinghat_proposal,
    op_kwargs={'client': client}
)
dag_import_sortinghat_proponent = PythonOperator(
    dag=dag,
    task_id='import_sortinghat_proponent',
    func_command=import_sortinghat_proponent,
    op_kwargs={'client': client}
)
dag_import_api = PythonOperator(
    dag=dag,
    task_id='import_api',
    func_command=import_api,
    op_kwargs={'client': client}
)
dag_import_ebdb_contrato = PythonOperator(
    dag=dag,
    task_id='import_ebdb_contrato',
    func_command=import_ebdb_contrato,
    op_kwargs={'client': client}
)
dag_import_invoices = PythonOperator(
    dag=dag,
    task_id='import_invoices',
    func_command=import_invoices,
    op_kwargs={'client': client}
)

dag_compute_performance_kpis = PythonOperator(
    compute_performance_kpis,
    provide_context=True,
    dag=dag,
    task_id='compute_performance_kpis'
)
dag_compute_performance = PythonOperator(
    compute_performance,
    provide_context=True,
    dag=dag,
    task_id='compute_performance'
)

dag_compute_originacao = PythonOperator(
    compute_originacao,
    provide_context=True,
    dag=dag,
    task_id='compute_originacao'
)

# flow

dag_import_ebdb_proposta >> dag_compute_originacao
dag_import_sortinghat_proposal >> dag_compute_originacao
dag_import_sortinghat_proponent >> dag_compute_originacao
dag_import_api >> dag_compute_originacao
dag_import_ebdb_contrato >> dag_compute_originacao

dag_import_ebdb_contrato >> dag_compute_performance
dag_import_invoices >> dag_compute_performance_kpis >> dag_compute_performance
