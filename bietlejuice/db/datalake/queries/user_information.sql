with ns as (
    select 1 as n
    union all
    select 2
    union all
    select 3
    union all
    select 4
    union all
    select 5
    union all
    select 6
    union all
    select 7
    union all
    select 8
    union all
    select 9
    union all
    select 10
),
ns_c as (
    select
    trim(split_part(cp.email, ',', ns.n)) as email, cp.phone_number, cp.name, cp.type
    from ns
    join datalake_ebdb_clean_prod.contract_person cp
        on ns.n <= regexp_count(cp.email, ',') + 1
),
ns_p as (
    select
    trim(split_part(cp.email, ';', ns.n)) as email, cp.phone_number, cp.name, cp.type
    from ns
    join datalake_ebdb_clean_prod.contract_person cp
        on ns.n <= regexp_count(cp.email, ';') + 1
),
union_all as (
    select email, phone_number, name, type
    from ns_c
    union all
    select email, phone_number, name, type
    from ns_p
),
contract_person as (
    select distinct trim(email) as email, phone_number, name, type
    from union_all
    where email is not null
    and email != ''
),
users_prev as (
    select distinct
    coalesce(uc.email, up.email, cp.email, pp.email) as email,
    coalesce(uc.main_phone, up.main_phone) as main_phone,
    coalesce(uc.secondary_phone, up.secondary_phone) as secondary_phone,
    coalesce(uc.business_phone, up.business_phone) as commercial_phone,
    cp.phone_number as contract_phone,
    pp.phone_number as proposal_phone,
    coalesce(uc.name, up.name, cp.name) as name,
    coalesce(uc.id, up.id, null) as id,
    coalesce(uc.admin_type, up.admin_type) as admin_type,
    coalesce(uc.is_blocked, up.is_blocked) as is_blocked,
    coalesce(uc.id_agent_rep, up.id_agent_rep) as id_agent_rep,
    coalesce(uc.id_photographer_data, up.id_photographer_data) as id_photographer_data,
    coalesce(uc.id_affiliates, up.id_affiliates) as id_affiliates,
    coalesce(uc.id_sales_rep, up.id_sales_rep) as id_sales_rep
    from contract_person cp
    full outer join datalake_ebdb_clean_prod.proponent_proposal pp
        on pp.email = cp.email
    full outer join datalake_ebdb_clean_prod.user up
        on up.email = pp.email
    full outer join datalake_ebdb_clean_prod.user uc
        on uc.email = cp.email
),
users as (
    select distinct
    up.email,
    main_phone,
    secondary_phone,
    commercial_phone,
    contract_phone,
    proposal_phone,
    up.name,
    up.id,
    (
        '' ||
        case
            when h.id is not null
            then 'proprietario'
            else ''
        end
        ||
        case
            when up.admin_type in ('Admin','Sudo','Contratos','Financeiro','AtendimentoParceiros')
            and up.is_blocked = 'false'
            then ',admin'
            else ''
        end
        ||
        case
            when up.admin_type = 'Sudo' and up.is_blocked = 'false'
            then ',sudo'
            else ''
        end
        ||
        case
            when pd.id is not null
            then ',fotografo'
            else ''
        end
        ||
        case
            when ad.id is not null
            then ',afiliado'
            else ''
        end
        ||
        case
            when sd.id is not null
            then ',vendedor'
            else ''
        end
        ||
        case
            when up.id_agent_rep is not null
            then ',agente'
            else ''
        end
        ||
        ''
    ) as roles
    from users_prev up
    left join datalake_ebdb_clean_prod.house h
    on h.id_user = up.id
        and h.status != 'excluido'
    left join datalake_ebdb_clean_prod.photographer_data pd
    on pd.id = up.id_photographer_data
        and pd.is_active = 'true'
    left join datalake_ebdb_clean_prod.affiliate_data ad
    on ad.id = up.id_affiliates
        and ad.is_active = 'true'
    left join datalake_ebdb_clean_prod.sales_rep sd
    on sd.id = up.id_sales_rep
        and sd.is_active = 'true'
),
all_info as (
    select distinct
    us.id as quintoandar_id,
    trim(us.email) as email,
    trim(us.name) as "name",
    us.roles as roles,
    coalesce(us.main_phone, '')
        || ',' || coalesce(us.secondary_phone, '')
        || ',' || coalesce(us.commercial_phone, '')
        || ',' || coalesce(us.contract_phone, '')
        || ',' || coalesce(us.proposal_phone, '')
    as phones,
    mu.amplitude_id as amplitude_id,
    zu.id as zendesk_id
    from users us
    left join amplitude_events.merged_users mu
    on us.id = mu.user_id
    left join datalake_clean.zendesk_user zu
    on zu.email = us.email
)
select distinct
    quintoandar_id,
    email,
    roles,
    phones,
    listagg("name", ',')
    within group (order by "name")
    over (partition by quintoandar_id, email) as names,
    listagg(zendesk_id, ',')
    within group (order by zendesk_id)
    over (partition by quintoandar_id, email) as zendesk_ids,
    listagg(amplitude_id, ',')
    within group (order by amplitude_id)
    over (partition by quintoandar_id, email) as amplitude_ids
from all_info