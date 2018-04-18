import numpy as np
import pandas as pd

from helpers import find_best_subset
from variables import *


def import_ebdb_proposta(client):
    """
    import selected fields from the proposta table and creates custom ones
    :param client: athena client
    :return:dataframe
    """
    # query made with akira and translated into presto
    sql_proposta_ebdb = '''
    select
        a.id as proposal_id,
      p.imovel_id,

      -- dates
        p.dataaprovacao as date_approval_5a,
        p.dataproposta as date_agreement, -- date the agreement is reached. 
        -- (continued) the offer is accepted. documentation is not yet sent. exactly the same as criadoem in proposta
      -- p.dataparamudanca as date_mudanca, -- is always null. ignore
        from_unixtime(cast(r.timestamp as bigint)/1000) as date_start_of_analysis,

        p.statusDocumentacaoInq,
        (from_unixtime(cast(r.timestamp as bigint)/1000) - interval '2' hour) >= date('2018-02-01') as screened_by_5a

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
        df_proposta_ebdb.loc[:, date_col] = pd.to_datetime(df_proposta_ebdb[date_col],
                                                           yearfirst=True,
                                                           errors='coerce')

    return df_proposta_ebdb


def import_sortinghat_proposal(client):
    """
    import selected fields from the sortinghat.proposal table
    :param client: athena client
    :return:dataframe
    """
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
        'updated_at': 'date_update',
        'process_date': 'date_processed'
    })

    # dates as datetime
    df_proposal_sh['date_analysis'] = pd.to_datetime(df_proposal_sh['date_analysis'])
    df_proposal_sh['date_creation'] = pd.to_datetime(df_proposal_sh['date_creation'])
    df_proposal_sh['date_update'] = pd.to_datetime(df_proposal_sh['date_update'])
    df_proposal_sh['date_processed'] = pd.to_datetime(df_proposal_sh['date_processed'])

    # take the last proposal in sh in case the same proposal was sent there multiple times
    df_proposal_sh = df_proposal_sh.sort_values(['proposal_id', 'date_creation', 'date_update'],
                                                ascending=[True, False, False]).groupby('proposal_id').first()

    # no analyst => not assigned
    df_proposal_sh.loc[:, 'analyst_name'] = df_proposal_sh.analyst_name.replace({'': 'not assigned'})
    df_proposal_sh.loc[:, 'supervisor_name'] = df_proposal_sh.supervisor_name.replace({'': 'not assigned'})

    # no rejection_motive => rejection_reason_unkown/not_rejected
    df_proposal_sh.loc[(df_proposal_sh.status == 'REJECTED') & (
        df_proposal_sh.rejection_motive == ''), 'rejection_motive'] = 'rejection_reason_unkown'
    df_proposal_sh.loc[(df_proposal_sh.status != 'REJECTED') & (
        df_proposal_sh.rejection_motive == ''), 'rejection_motive'] = 'not_rejected'

    col_string_to_float = [
        'score_5a',
        'score_5a_best_subset',
        'score_cardif',
        'score_cardif_best_subset']
    df_proposal_sh.loc[:, col_string_to_float] = df_proposal_sh.loc[:, col_string_to_float].replace(
        to_replace='',
        value=np.nan).astype(float)

    return df_proposal_sh


def import_sortinghat_proponent(client):
    """
    import selected fields from the sortinghat.proponent table
    :param client: athena client
    :return:dataframe
    """
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

    # rename
    df_proponent_sh = df_proponent_sh.rename(columns={
        'id': 'proponent_id',
        'admission_date': 'date_admission',
        'birthday': 'date_birth'
    })

    # dates as datetime
    df_proponent_sh['date_admission'] = pd.to_datetime(df_proponent_sh['date_admission'], yearfirst=True, errors='coerce')
    df_proponent_sh['date_birth'] = pd.to_datetime(df_proponent_sh['date_birth'], yearfirst=True, errors='coerce')

    # variables from the first proponent. todo check that it is the same as in ebdb
    df_proponent_sh_first = df_proponent_sh.sort_values('proponent_id', ascending=True).groupby('proposal_id').first()
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
    """
    import selected fields from the api table (production lines) and corrects some values
    :param client: athena client
    :return:dataframe
    """
    sql_api = '''
    select *, cardinality(name) as n_applicants from datalake_raw.tenant_screening_processed
    -- where source='prod' -- done in code
    '''
    df_api = client.execute_query_and_return_dataframe(sql_api)
    df_api.loc[:, col_float + variables_of_subset + variables_of_property] = df_api.loc[:,
                                                                             col_float + variables_of_subset +
                                                                             variables_of_property].replace(
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


def import_ebdb_contrato_aud(client):
    """
    import selected fields from the contrato audit table
    :param client: athena client
    :return:dataframe
    """
    # query made with akira and translated into presto
    sql_contrato_ebdb = '''
    select 
      (from_unixtime(cast(r.timestamp as bigint)/1000) - interval '2' hour) as date_change, 
      ca.id as contract_id,
      c.proposta_id as proposal_id,
      ca.imovel_id,
      ca.status,
      c.criadoem as date_creation, -- creation of the line in the table
      ca.dataassinado as date_signature, -- signature of the contract
      ca.datainicio as date_beginning, -- date the tenant can move in and we start to charge
      ca.datafimcontratoprevisto as date_fim_previsto, -- normal date of end of contract. 
      -- (continued) always signature + 30m unless 2nd signature
      ca.datarescisaoprevista as date_rescisao_prevista, -- date in the future at which the contract will be stopped
      ca.datarescisao as date_rescisao, -- end of the contract that has already ended
      ca.diamescobranca,
      ca.garantia,
      ca.valoraluguel,
      c.cidade,
      ca.contractversion_id
    from datalake_raw.ebdb_contrato_aud ca
    join datalake_raw.ebdb_usuariorevisionentity r on ca.REV = r.id 
    join datalake_raw.ebdb_contrato c on c.id=ca.id
    -- where ca.garantia='SeguroFairfax' -- to determine this field they look if the beginning of the 
    -- negociation was before feb
    -- we need to remove this condition because it could be that we end up deciding a 
    -- proposition where we initially 'promised' it would be covered by cardif
    where c.proposta_id is not null and c.proposta_id!=''
    '''
    df_contrato_ebdb = client.execute_query_and_return_dataframe(sql_contrato_ebdb)

    date_cols = [
        'date_change',
        'date_creation',
        'date_signature',
        'date_beginning',
        'date_rescisao',
        'date_fim_previsto',
        'date_rescisao_prevista'
    ]
    for date_col in date_cols:
        df_contrato_ebdb.loc[:, date_col] = pd.to_datetime(df_contrato_ebdb[date_col], yearfirst=True, errors='coerce')

    return df_contrato_ebdb


def import_ebdb_contrato(client):
    """
    import selected fields from the contrato table
    :param client: athena client
    :return:dataframe
    """
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
      c.datafimcontratoprevisto date_fim_previsto, -- normal date of end of contract. 
      -- (continued) always signature + 30m unless 2nd signature
      c.datarescisaoprevista date_rescisao_prevista, -- date in the future at which the contract will be stopped
      c.datarescisao date_rescisao, -- end of the contract that has already ended
      c.diamescobranca,
      c.garantia,
      c.valoraluguel,
      c.cidade,
      c.contractversion_id
    from datalake_raw.ebdb_contrato c
    -- where ca.garantia='SeguroFairfax' -- to determine this field they look if the beginning of the 
    -- negociation was before feb
    -- we need to remove this condition because it could be that we end up deciding a 
    -- proposition where we initially 'promised' it would be covered by cardif
    where c.proposta_id is not null and c.proposta_id!=''
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

    df_contrato_ebdb = df_contrato_ebdb.set_index('contract_id')

    return df_contrato_ebdb


def import_invoices(client):
    """
    import selected fields from the invoice table
    :param client: athena client
    :return: dataframe
    """
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

    return df_payments
