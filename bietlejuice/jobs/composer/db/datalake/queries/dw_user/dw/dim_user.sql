with user_dates (
    select
        u.id,
        min(b.ts_created) as ts_first_booking,
        -- TODO [ODS] the value for status should be Cancelado instead of Canceled
        min(if(b.status != 'Canceled', b.ts_created, null)) as ts_first_booking_confirmed,
        min(v.dt_visit) as dt_first_visit,
        -- TODO [ODS] the value for status should be Cancelado instead of Canceled
        min(if(b.status != 'Canceled', v.dt_visit, null)) as dt_first_visit_confirmed,
        min(pp.ts_created) as ts_first_pre_proposal,
        min(p.ts_created) as ts_first_proposal_accepted,
        min(c.ts_created) as ts_first_contract,
        min(c.ts_signed) as ts_first_signed_contract
    from datalake_ebdb_user.user u
    left join datalake_booking.booking b
        on b.id_visitor = u.id
    left join datalake_ebdb_clean.visit v
        on v.id = b.id_visit
    left join datalake_ebdb_clean.rent_flow rf
        on rf.id = b.id_rent_flow
    left join datalake_ebdb_clean.pre_proposal pp
        on rf.id_client = pp.id_user
    left join datalake_ebdb_clean.proposal p
        on p.id_pre_proposal = pp.id
    left join datalake_ebdb_clean.contract c
        on c.id_proposal = p.id
    group by u.id
),
booking_counts as (
    select
        id_visitor,
        cast(count(1) as integer) as visits_booked,
        cast(sum(if(is_visit_completed, 1, 0)) as integer) as visits_realized,
        cast(sum(if(visit_fup is not null, 1, 0)) as integer) as visits_expected_to_happen
    from datalake_booking.booking
    group by id_visitor
 )
select
    u.id as sk_user,
    coalesce(cast(date_format(ad.ts_doorman_joined, 'yyyyMMdd') as bigint), -1) as sk_doorman_joined_date,
    u.id as id_user,
    u.id_agent,
    u.id_photographer,
    u.id_sales_rep,
    u.id_affiliates as id_affiliate,
    u.id_facebook,
    u.id_linkedin,
    u.id_google,
    u.is_active,
    u.is_blocked,
    ad.is_active as is_affiliate_active,
    ag.is_active as is_agent_active,
    p.is_active as is_photographer_active,
    coalesce(ad.is_doorman_affiliate, false) as is_doorman_affiliate,
    u.is_tenant,
    ag.is_sale_agent,
    ag.is_rent_agent,
    u.bank_another_holder as is_bank_another_holder,
    u.has_house,
    u.has_tenant_app,
    u.has_active_contract,
    u.has_accepted_sms,
    left(u.name, 200) as name,
    u.cpf,
    u.rg,
    u.gender,
    u.email,
    u.alternative_email,
    u.main_phone,
    u.address,
    u.number,
    u.complement,
    u.neighborhood,
    u.zip_code,
    u.city,
    s.name as state_name,
    s.abbreviation as state_abbreviation,
    u.admin_type,
    b.code as bank_code,
    b.name as bank_name,
    u.bank_agency,
    u.bank_account,
    u.bank_cpf_cnpj,
    u.bank_name as bank_person_name,
    u.bank_account_type,
    ag.profile as agent_profile,
    ag.creci_number as agent_creci_number,
    p.contract_type as photographer_contract_type,
    ad.work_city as affiliate_work_city,
    ad.payment_preference as affiliate_payment_preference,
    ad.creci_number as affiliate_creci_number,
    ad.last_week_balance_communication as affiliate_last_week_balance_communication,
    b_counts.visits_booked,
    b_counts.visits_realized,
    b_counts.visits_expected_to_happen,
    u.dt_birth,
    user_dates.dt_first_visit,
    user_dates.dt_first_visit_confirmed,
    u.ts_click_anuncie,
    p.ts_contract_started as ts_photographer_contract_started,
    sr.ts_contract_started as ts_sales_rep_contract_started,
    ad.ts_first_operation_start as ts_affiliate_first_operation_started,
    user_dates.ts_first_booking,
    user_dates.ts_first_booking_confirmed,
    user_dates.ts_first_pre_proposal,
    user_dates.ts_first_proposal_accepted,
    user_dates.ts_first_contract,
    user_dates.ts_first_signed_contract,
    u.ts_first_document_sent,
    u.ts_last_document_sent,
    u.ts_first_sent_to_insurance,
    u.ts_created,
    u.ts_updated,
    now() as ts_load
from datalake_ebdb_user.user u
inner join user_dates user_dates
    on user_dates.id = u.id
left join booking_counts b_counts
    on b_counts.id_visitor = u.id
left join datalake_ebdb_clean.state s
    on s.id = u.id_state
left join datalake_ebdb_user.agent_data ag
    on ag.id = u.id_agent
left join datalake_ebdb_clean.bank b
    on b.id = u.id_bank
left join datalake_ebdb_clean.photographer p
    on p.id = u.id_photographer
left join datalake_ebdb_clean.sales_rep sr
    on sr.id = u.id_sales_rep
left join datalake_ebdb_user.affiliate_data ad
    on ad.id = u.id_affiliates
