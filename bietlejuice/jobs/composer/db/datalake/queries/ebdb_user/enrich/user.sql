with proponent_document_dates as (
    select
          p.id_proponent,
          min(if(p.ts_documentation_sent is not null, p.ts_documentation_sent, null)) as ts_first_document_sent,
          max(if(p.ts_documentation_sent is not null, p.ts_documentation_sent, null)) as ts_last_document_sent,
          min(if(p_aud.tenant_documentation_status = 'AnaliseCredito', ure.ts_revision, null)) as ts_first_sent_to_insurance
        from
          datalake_ebdb_clean.proposal p
        left join datalake_ebdb_clean.proposal_aud p_aud
           on p_aud.id_proposal = p.id
        join
          datalake_ebdb_user_revision_entity.user_revision_entity ure
          on ure.id = p_aud.rev
        group by
          p.id_proponent
),
user_information as (
    with distinct_id_user_from_house as (
      select
        distinct id_user
      from datalake_ebdb_clean.house
    ),
    distinct_id_user_from_device as (
      select
        distinct id_user
      from datalake_ebdb_clean.device
      where mobile_app = 'Inquilinos'
    ),
    distinct_id_user_from_contract as (
      select
        distinct id_user
      from datalake_ebdb_clean.contract
    )
    select
      user.id as id_user,
      (house_ids.id_user is not NULL) as has_house,
      (device_ids.id_user is not NULL) as has_tenant_app,
      (contract_ids.id_user is not NULL) as has_active_contract,
      (
        (
          user.id_affiliates is null
          and user.id_photographer is null
          and user.id_sales_rep is null
          and user.id_agent_rep is null
          and house_ids.id_user is NULL
        ) or  contract_ids.id_user is not null
      ) as is_tenant,
      (user.id_photographer is not null) as is_photographer,
      substring(user.main_phone, 4, 2) as main_phone_ddd
    from datalake_ebdb_clean.user user
    left join distinct_id_user_from_house house_ids
      on house_ids.id_user = user.id
    left join distinct_id_user_from_device device_ids
      on device_ids.id_user = user.id
    left join distinct_id_user_from_contract contract_ids
      on contract_ids.id_user = user.id
    group by 1, 2, 3, 4, 5, 6, 7
)
select
    u.id,
    u.id_facebook,
    u.id_linkedin,
    u.id_google,
    u.id_agent,
    u.id_photographer,
    u.id_sales_rep,
    u.id_affiliates,
    u.id_bank,
    u.id_state,
    u.cpf,
    u.rg,
    u.gender,
    u.email,
    u.alternative_email,
    u.name,
    u.admin_type,
    u.address,
    u.number,
    u.complement,
    u.neighborhood,
    u.city,
    u.zip_code,
    u.main_phone,
    ui.main_phone_ddd,
    u.bank_agency,
    u.bank_account,
    u.bank_cpf_cnpj,
    u.bank_name,
    u.bank_another_holder,
    u.bank_account_type,
    u.has_accepted_sms,
    ui.has_house,
    ui.has_tenant_app,
    ui.has_active_contract,
    ui.is_tenant,
    ui.is_photographer,
    u.is_active,
    u.is_blocked,
    case
      when date_format(u.dt_birth, 'y') < 100 then u.dt_birth + interval 1900 years
      when date_format(u.dt_birth, 'y') < 1000 then u.dt_birth + interval 1000 years
      else u.dt_birth
    end as dt_birth,
    u.ts_click_anuncie,
    pdd.ts_first_document_sent,
    pdd.ts_last_document_sent,
    pdd.ts_first_sent_to_insurance,
    u.ts_created,
    u.ts_updated
from datalake_ebdb_clean.user u
left join proponent_document_dates pdd
    on pdd.id_proponent = u.id
left join user_information ui
    on ui.id_user = u.id