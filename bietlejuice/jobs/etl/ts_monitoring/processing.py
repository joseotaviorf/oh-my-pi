from itertools import tee, izip

import numpy as np
import pandas as pd
from variables import variables_of_property
from variables import variables_of_subset


def pairwise(iterable):
    "s -> (s0,s1), (s1,s2), (s2, s3), ..."
    a, b = tee(iterable)
    next(b, None)
    return izip(a, b)


today = pd.Timestamp(pd.Timestamp.today(tz='Brazil/East').date())


def preprocess_contracts(df_contrato_aud_ebdb, date):
    """
    takes the audit table and returns the state of the contract table at date 'date'(end of day)

    :param df_contrato_aud_ebdb: the dataframe containing the whole audit table of contrato
    :param date: we output the contrato table as it was at the end of date
    :return: the historical value of contrato, at the end of date 'date'
    """

    # we keep the changes made strictly before date+1day (we put ourselves at the end of 'date')
    df_contrato_ebdb = df_contrato_aud_ebdb[df_contrato_aud_ebdb.date_change < date + pd.to_timedelta(1, unit='days')]

    # we keep the last version of the line
    df_contrato_ebdb = df_contrato_ebdb.sort_values('date_change', ascending=False).groupby('contract_id').first()

    # new columns
    df_contrato_ebdb['planned_end_contract'] = pd.concat([
        df_contrato_ebdb.date_rescisao,
        df_contrato_ebdb.date_fim_previsto,
        df_contrato_ebdb.date_rescisao_prevista],
        axis=1).min(axis=1)

    df_contrato_ebdb['dob'] = ((pd.concat([date - pd.to_datetime(df_contrato_ebdb.date_signature.dt.date),
                                           pd.to_datetime(df_contrato_ebdb.planned_end_contract) - pd.to_datetime(
                                               df_contrato_ebdb.date_signature.dt.date)],
                                          axis=1).min(axis=1)) / pd.to_timedelta(1, unit='days')).fillna(
        0.0)  # if never signed we put 0

    return df_contrato_ebdb


def preprocess_payments(df_payments, date):
    """
    compute what the payments df would have looked like at date 'date' (end of day).
    - changes tenant_status to 'open' if date<tenant_paid_date
    - recomputes 'delay' and 'tenant status is open'

    PS : there is no audit for invoice table. moreover, it would not be accurate once the invoice table will be corrected.

    :param df_payments: current payments table
    :param date: date at the end of which we want to simulate the payments table
    :return: payments table as it was at the end of date 'date'
    """
    df_payments.loc[:, 'tenant_paid_date'] = np.where(date >= df_payments.tenant_paid_date,
                                                      df_payments.tenant_paid_date, np.datetime64('NaT'))
    df_payments.loc[:, 'tenant_status'] = np.where(date >= df_payments.tenant_paid_date, 'paid', 'open')

    delay_paid = (df_payments['tenant_paid_date'] - df_payments['tenant_due_date']) / pd.Timedelta('1 days')
    if date != today:
        delay_open = (date - df_payments['tenant_due_date']) / pd.Timedelta(
            '1 days') + 1  # we assume the db is up to date and the invoice still hasnt been paid on date 'date'
    else:  # today is the only day that has not ended so we do not count it in the delay
        delay_open = (date - df_payments['tenant_due_date']) / pd.Timedelta(
            '1 days')  # we assume the db is up to date and the invoice still hasnt been paid on date 'date'
    df_payments['delay'] = pd.concat([delay_paid, delay_open], axis=1).min(axis=1)
    df_payments['tenant_status_is_open'] = (df_payments['tenant_status'] == 'open')

    return df_payments


def compute_performance_kpis(df_payments):  # , **context):
    """
    computes kpis per contract based on the payments table
    :param df_payments: payments dataframe coming from the invoice table
    :return:dataframe containing the kpis per contract
    """
    # df_payments = context['task_instance'].xcom_pull(task_ids='import_invoices')

    thresholds = [0, 30, 60, 90, 120, 150, 180]
    # for every contract we determine the date at which it first became bad for a given threshold
    df_performance_threshold = pd.DataFrame()
    df_performance_kpis = pd.DataFrame()
    for cid in df_payments.contract_id.unique():
        contract = df_payments[df_payments.contract_id == cid].sort_values('year_month', ascending=True).copy()

        df_performance_kpis = df_performance_kpis.append({
            'contract_id': cid,
            'max_dpd_ever': contract.delay.max(),
            'sum_dpd_ever': contract[contract.delay > 0].delay.sum(),
            'max_dpd_current': contract[contract.tenant_status == 'open'].delay.max(),
            'sum_dpd_current': contract[(contract.tenant_status == 'open') & (contract.delay > 0)].delay.sum(),
            'last_invoice_dpd': contract.delay.iloc[-1],

            'n_issued_invoices': contract.year_month.nunique(),
            # cant be computed for dated performance because we don't know when an invoice was issued
            'n_paid_invoices': contract[contract.tenant_status == 'paid'].year_month.nunique(),
            'n_open_late_invoices': contract[
                (contract.tenant_status == 'open') & (contract.delay > 0)].year_month.nunique(),

            'sum_rent_issued': contract.amount.sum(),
            'sum_rent_paid': contract[contract.tenant_status == 'paid'].amount.sum(),
            'sum_rent_unpaid': contract[contract.tenant_status == 'open'].amount.sum()
        }, ignore_index=True)

        for t in thresholds:
            # the goal is to determine the date at which the contract became bad according to the threshold t
            # we need to take the minimum date between:
            # - due date + t, for paid invoices that have a delay>=t
            candidates_all = (contract.loc[contract.delay >= t, 'tenant_due_date'] +
                              pd.to_timedelta(t, unit='d')).tolist()
            thres_date = min(candidates_all) if len(candidates_all) > 0 else np.nan

            # determine if there are any unpaid invoices for strictly more than t days
            candidates_unpaid = (
                contract.loc[contract.tenant_status_is_open & (contract.delay > t), 'tenant_due_date'] +
                pd.to_timedelta(t, unit='d')).tolist()
            # the current status is over t if there is any open invoice with delay above t
            over_t = (len(candidates_unpaid) > 0)

            # write in df:
            df_performance_threshold = df_performance_threshold.append({
                'contract_id': cid,
                'threshold': t,
                'date_ever': thres_date,
                'status_over': over_t,
                'ninvoices_above': len(candidates_unpaid)
            }, ignore_index=True)

    df_performance_kpis = df_performance_kpis.set_index('contract_id')

    df_performance_ever = df_performance_threshold.pivot(index='contract_id', columns='threshold', values='date_ever')
    df_performance_ever.columns = ['date_ever' + str(t + 1) for t in thresholds]
    df_performance_kpis = df_performance_kpis.merge(df_performance_ever, left_index=True, right_index=True)

    df_performance_over = df_performance_threshold.pivot(index='contract_id', columns='threshold', values='status_over')
    df_performance_over.columns = ['over' + str(t + 1) for t in thresholds]
    df_performance_kpis = df_performance_kpis.merge(df_performance_over, left_index=True, right_index=True)

    df_performance_nover = df_performance_threshold.pivot(index='contract_id', columns='threshold',
                                                          values='ninvoices_above')
    df_performance_nover.columns = ['nover_or_equal' + str(t + 1) for t in thresholds]
    df_performance_kpis = df_performance_kpis.merge(df_performance_nover, left_index=True, right_index=True)

    df_performance_nbetween = pd.DataFrame(index=df_performance_nover.index)
    for tlow, thigh in pairwise(thresholds):
        df_performance_nbetween['%dto%d' % (tlow + 1, thigh)] = df_performance_nover['nover_or_equal%d' % (tlow + 1)] - df_performance_nover['nover_or_equal%d' % (thigh + 1)]
    df_performance_kpis = df_performance_kpis.merge(df_performance_nbetween, left_index=True, right_index=True)

    return df_performance_kpis


def compute_performance_table(df_contrato_aud_ebdb, df_payments, date):
    """
    computes the performance table as it was at the end of date 'date'
    the performance table basically joins the information about the contract with the kpis computed with the invoice table
    :param df_contrato_aud_ebdb: audit table of contrato table in ebdb
    :param df_payments: payments dataframe as it is now (invoice table)
    :param date: date at the end of which we want to compute the performance table
    :return:
    """
    # get version of the table at the end of 'date' and add columns
    df_contrato_ebdb = preprocess_contracts(df_contrato_aud_ebdb, date)
    df_payments = preprocess_payments(df_payments, date)

    # compute performance kpis
    df_performance_kpis = compute_performance_kpis(df_payments)

    # rename columns contrato
    columns_names_contrato_ebdb = {col: 'contrato_' + col for col in df_contrato_ebdb.columns}
    df_contrato_ebdb_prepared = df_contrato_ebdb.rename(columns=columns_names_contrato_ebdb)

    # rename columns_performance kpis (coming from invoices db)
    columns_names_performance = {col: 'invoices_' + col for col in df_performance_kpis.columns}
    df_performance_prepared = df_performance_kpis.rename(columns=columns_names_performance)

    # join
    output_performance = df_contrato_ebdb_prepared.merge(df_performance_prepared, how='left', left_index=True,
                                                         right_index=True)
    # new columns ##

    # output_performance['days_contract_left'] =  (output_performance.dataassinado)
    output_performance['contrato_expected_total_contract_duration'] = (
        (pd.to_datetime(
            output_performance.contrato_planned_end_contract) - output_performance.contrato_date_signature) / pd.to_timedelta(
            1, unit='days')).fillna(915.0)  # 915 is 30 months

    cols_to_zero = [
        u'invoices_last_invoice_dpd',
        u'invoices_max_dpd_current',
        u'invoices_max_dpd_ever',
        u'invoices_n_issued_invoices',
        u'invoices_n_paid_invoices',
        u'invoices_n_open_late_invoices',
        u'invoices_sum_dpd_current',
        u'invoices_sum_dpd_ever',
        u'invoices_sum_rent_issued',
        u'invoices_sum_rent_paid',
        u'invoices_sum_rent_unpaid',
        u'invoices_nover_or_equal1',
        u'invoices_nover_or_equal31',
        u'invoices_nover_or_equal61',
        u'invoices_nover_or_equal91',
        u'invoices_nover_or_equal121',
        u'invoices_nover_or_equal151',
        u'invoices_nover_or_equal181',
        u'invoices_1to30',
        u'invoices_31to60',
        u'invoices_61to90',
        u'invoices_91to120',
        u'invoices_121to150',
        u'invoices_151to180',
    ]
    output_performance.loc[:, cols_to_zero] = output_performance.loc[:, cols_to_zero].fillna(
        0)  # astype(str).replace({'NaT':''})

    output_performance['contrato_approx_n_invoices_expected'] = \
        (output_performance['contrato_expected_total_contract_duration'] / 30.5).round()

    output_performance['approx_sum_rent_future_to_issue'] = \
        (output_performance.contrato_approx_n_invoices_expected - output_performance.invoices_n_issued_invoices) * \
        output_performance.contrato_valoraluguel

    output_performance['approx_sum_rent_future_to_pay'] = \
        (output_performance.contrato_approx_n_invoices_expected - output_performance.invoices_n_paid_invoices) * \
        output_performance.contrato_valoraluguel
    return output_performance


def format_performance_table(output_performance):
    """
    takes the dataframe that was the output of compute_performance and makes it suitable to be written in s3
    :param output_performance: output of compute_performance (potentially modified afterwards)
    :return:formatted dataframe
    """

    output_performance = output_performance.reset_index()

    # sometimes these columns are null everywhere and pandas doesnt know they are dates, and the sk_date will not be created. so we force it:
    force_date_format = [u'invoices_date_ever1', u'invoices_date_ever31', u'invoices_date_ever61',
                         u'invoices_date_ever91', u'invoices_date_ever121', u'invoices_date_ever151',
                         u'invoices_date_ever181']
    for col in force_date_format:
        output_performance.loc[:, col] = output_performance.loc[:, col].astype('datetime64[ns]')

    return output_performance


def compute_originacao_table(df_proposta_ebdb, df_contrato_ebdb, df_proposal_sh, df_proponents_of_proposal,
                             df_api_last):
    """
    computes the originacao table as it was at the end of yesterday.
    the originacao table provides, for every proposal, information related to the proposal, to the last request sent to the api, to the decision made, etc

    :param df_proposta_ebdb: proposta dataframe coming from ebdb
    :param df_contrato_ebdb: contrato dataframe coming from ebdb
    :param df_proposal_sh: proposal dataframe coming from sortinghat
    :param df_proponents_of_proposal: proponents dataframe coming from sortinghat
    :param df_api_last: api dataframe containing, for each proposal for which a request was made, the information about the last request for that proposal.
    :return: the originacao table (unformatted)
    """
    # proposata of ebdb ################

    # we want to keep the propostas screened by 5a (those that went though sortinghat)
    df_proposta_ebdb_prepared = df_proposta_ebdb[df_proposta_ebdb.screened_by_5a]

    # select columns
    columns_to_keep_proposta_ebdb = [
        'imovel_id',
        'date_approval_5a',
        'date_agreement',
        'date_start_of_analysis',
        'statusdocumentacaoinq',
        'screened_by_5a'
    ]
    df_proposta_ebdb_prepared = df_proposta_ebdb_prepared[columns_to_keep_proposta_ebdb]

    # rename columns
    columns_names_proposta_ebdb = {col: 'proposta_' + col for col in columns_to_keep_proposta_ebdb}
    df_proposta_ebdb_prepared = df_proposta_ebdb_prepared.rename(columns=columns_names_proposta_ebdb)

    # merge with contrato ebdb (only to get the contract id)
    # there can be more than one contract per proposal
    # in rare cases where it has to be rewritten for example and the first one is cancelled
    # so we sort by status (take active if there is one) and by date (take the most recently signed)
    df_contrato_ebdb_prepared = df_contrato_ebdb.reset_index().sort_values(
        ['proposal_id', 'status', 'date_signature'],
        ascending=[True, True, False])
    df_contrato_ebdb_prepared = df_contrato_ebdb_prepared.groupby('proposal_id').agg(
        {'contract_id': 'first'})

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
        'date_processed',
        'imovel_id',
        'rejection_motive',
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
        'home_insurance_value',
        'drive_id',
        'risk_level',
        'risk_level_best_subset',
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
    df_api_last_big = df_api_last[df_api_last.full_subset]
    df_api_last_best = df_api_last[df_api_last.best_subset]

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

    return output_originacao


def format_originacao_table(output_originacao):
    """
    formats the originacao table outputted by compute_originacao_table
    :param output_originacao: dataframe coming from compute_originacao
    :return: formatted table that can be written in s3
    """
    # remove commas from comments
    output_originacao.loc[:, 'sh_comment'] = output_originacao.loc[:, 'sh_comment'].str.replace(pat=',', repl=' ')
    output_originacao = output_originacao.reset_index()

    return output_originacao
