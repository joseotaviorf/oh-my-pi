  with cpf_person as (
    select 
        id,
        cpf,
        case when cpf rlike '^([0-9]{3})?(\.)([0-9]{3})?(\.)([0-9]{3})?(.)([0-9]{2})$' then true else false end as is_cpf_format,
        case when cpf rlike '^([0-9]{2})?(\.)([0-9]{3})?(\.)([0-9]{3})(\/)([0-9]{4})?(.)([0-9]{2})$' then true else false end as is_cnpj_format
    from datalake_ebdb_clean.proponent_proposal
    where cpf is not null
),
string_to_validate as (
    select 
        id,
        cpf,
        is_cpf_format,
        is_cnpj_format,
        case when is_cpf_format = true then substring(cast(regexp_replace(cpf,'\\D+','') as string),1,9) 
            when is_cnpj_format = true then substring(cast(regexp_replace(cpf,'\\D+','') as string),1,12)
            end as first_digits
    from cpf_person
),
base_doc_aux as (
    select
        id,
        cpf,
        is_cpf_format,
        is_cnpj_format,
        first_digits,
        'cpf' as doc_type,
        cast(substring(first_digits, 1,1) as integer)  as col1,
        cast(substring(first_digits, 2,1) as integer)  as col2,
        cast(substring(first_digits, 3,1) as integer)  as col3,
        cast(substring(first_digits, 4,1) as integer)  as col4,
        cast(substring(first_digits, 5,1) as integer)  as col5,
        cast(substring(first_digits, 6,1) as integer)  as col6,
        cast(substring(first_digits, 7,1) as integer)  as col7,
        cast(substring(first_digits, 8,1) as integer)  as col8,
        cast(substring(first_digits, 9,1) as integer)  as col9,
        cast(0 as integer)                             as col10,
        cast(0 as integer)                             as col11,
        cast(0 as integer)                             as col12
from    string_to_validate
where   is_cpf_format = true
    and length(first_digits) = 9
union all
    select
        id,
        cpf,
        is_cpf_format,
        is_cnpj_format,
        first_digits,
        'cnpj',
        cast(substring(first_digits, 1,1)  as integer), 
        cast(substring(first_digits, 2,1)  as integer), 
        cast(substring(first_digits, 3,1)  as integer), 
        cast(substring(first_digits, 4,1)  as integer), 
        cast(substring(first_digits, 5,1)  as integer), 
        cast(substring(first_digits, 6,1)  as integer), 
        cast(substring(first_digits, 7,1)  as integer), 
        cast(substring(first_digits, 8,1)  as integer), 
        cast(substring(first_digits, 9,1)  as integer), 
        cast(substring(first_digits, 10,1) as integer),
        cast(substring(first_digits, 11,1) as integer),
        cast(substring(first_digits, 12,1) as integer)
from    string_to_validate
where   is_cnpj_format = true
    and length(first_digits) = 12
),auxtb1 as (
            select  id,
                    doc_type,
                    case when doc_type = 'cpf'  then (10*col1 + 9*col2 + 8*col3 + 7*col4 + 6*col5 + 5*col6 + 4*col7 + 3*col8 + 2*col9)
                         when doc_type = 'cnpj' then (5*col1 + 4*col2 + 3*col3 + 2*col4 + 9*col5 + 8*col6 + 7*col7 + 6*col8 + 5*col9 + 4*col10 + 3*col11 + 2*col12)
                    end aux1
            from base_doc_aux
),digtb1 as (
            select  id, 
                    cast(
                        case when (aux1%11) < 2 then 0
                        else 11 - (aux1%11)
                        end as integer) as dig1
            from auxtb1
),auxtb2 as (
            select  bda.id,
                    bda.doc_type,
                    case when doc_type = 'cpf'  then (11*col1 + 10*col2 + 9*col3 + 8*col4 + 7*col5 + 6*col6 + 5*col7 + 4*col8 + 3*col9 + 2*dig1) 
                         when doc_type = 'cnpj' then (6*col1 + 5*col2 + 4*col3 + 3*col4 + 2*col5 + 9*col6 + 8*col7 + 7*col8 + 6*col9 + 5*col10 + 4*col11 + 3*col12 + 2*dig1)
                    end as aux2
            from base_doc_aux bda
            inner join digtb1 dtb1
            on bda.id = dtb1.id
),digtb2 as (
            select  id, 
                    cast(
                        case when (aux2%11) < 2 then 0
                        else 11 - (aux2%11)
                        end as integer) as dig2
            from auxtb2
),
valid_cpf as (
    select
        bda.id,
        bda.cpf,
        bda.is_cpf_format,
        bda.is_cnpj_format,
        bda.first_digits,
        regexp_replace(bda.cpf,'\\D+','') as cpf_digits,
        concat(bda.first_digits,concat(cast(digtb1.dig1 as string),cast(digtb2.dig2 as string))) as valid_cpf,
        case when (regexp_replace(bda.cpf,'(\\D+)','')) rlike '\b(\d)\1+\b' then true else false end as is_repeated_numbers
    from base_doc_aux bda
    inner join digtb1 on digtb1.id = bda.id
    inner join digtb2 on digtb2.id = bda.id
),
cpf_validator as (
    select id,
           cpf,
           is_cpf_format,
           is_cnpj_format,
           cpf_digits,
           valid_cpf
    from valid_cpf vc
    where is_repeated_numbers = false
),
first_last_proposal as (
    select 
        id_proponent,
        min(id) as id_first_proposal,
        max(id) as id_last_proposal
    from datalake_ebdb_clean.proposal 
    group by 1
)
select 
    pp.id,
    pp.cpf,
    coalesce(u.id,-1) as sk_proponent,
    pp.id_proposal as sk_proposal,
    coalesce(cast(date_format(pp.dt_birth, 'yyyyMMdd') as bigint), -1) as sk_birth_date,
    coalesce(cast(date_format(pp.ts_created, 'yyyyMMdd') as bigint), -1) as sk_created_date,
    case when u.id is not null then true else false end as is_user,
        (cv.is_cpf_format = true and cv.valid_cpf = cast(regexp_replace(pp.cpf,'(\\D+)','') as string)) as is_valid_cpf,
        (cv.is_cnpj_format = true and cv.valid_cpf = cast(regexp_replace(pp.cpf,('\\D+'),'') as string)) as is_valid_cnpj, 
    case when pp.type = 'Proprietario' then 'landlord'
        when pp.type = 'Inquilino' then 'tenant'
        when pp.type = 'Fiador' then 'sponsor'
        else pp.type end as expected_contract_role,
    case when pp.rental_motive = 'ProximidadeAOTrabalho' then 'work proximity'
        when pp.rental_motive = 'ParaFamiliares' then 'for relatives'
        when pp.rental_motive = 'RealocacaoEmpresa' then 'company realocation'
        when pp.rental_motive = 'ReducaoCustos' then 'cost reduction'
        when pp.rental_motive = 'Casamento' then 'marriage'
        when pp.rental_motive = 'Separacao' then 'divorce'
        when pp.rental_motive = 'ProximidadeAFamiliares' then 'family proximity'
        when pp.rental_motive = 'Independencia' then 'independence'
        when pp.rental_motive = 'VendaImovelProprio' then 'selling own house'
        when pp.rental_motive = 'ProximidadeAEscola' then 'school proximity'
        when pp.rental_motive = 'ParaTerceiros' then 'for third party'
        else pp.rental_motive end as rental_motive,
        pp.will_live as is_going_to_live,
        case when pp.id_proposal = fl.id_first_proposal then true else false end as is_first_proposal,
    case when pp.id_proposal = fl.id_last_proposal then true else false end as is_last_proposal,
        coalesce(pp.monthly_salary,0)+coalesce(pp.additional_income,0) as brl_total_income,
        now() as ts_load
    from datalake_ebdb_clean.proponent_proposal pp
    inner join datalake_ebdb_clean.proposal p 
        on pp.id_proposal = p.id
    left join datalake_ebdb_clean.user u 
        on p.id_proponent = u.id
        and pp.cpf = u.cpf
    inner join first_last_proposal fl 
        on fl.id_proponent = p.id_proponent
    left join cpf_validator cv 
        on cv.id = pp.id