with person_cpf as (
	select
		id,
		cpf,
		cpf rlike '^([0-9]{3})?(\.)([0-9]{3})?(\.)([0-9]{3})?(.)([0-9]{2})$' as is_cpf_format,
		cpf rlike '^([0-9]{2})?(\.)([0-9]{3})?(\.)([0-9]{3})(\/)([0-9]{4})?(.)([0-9]{2})$' as is_cnpj_format
	from datalake_ebdb_clean.proponent_proposal
	where cpf is not null
),
validation_string as (
	select
		id,
		cpf,
		is_cpf_format,
		is_cnpj_format,
		case when is_cpf_format = true then substring(cast(regexp_replace(cpf, '\\D+', '') as string),1,9)
			when is_cnpj_format = true then substring(cast(regexp_replace(cpf, '\\D+', '') as string),1,12)
			end as first_digits
	from person_cpf
	where is_cpf_format = true
		or is_cnpj_format = true
),
unnested_digits as (
	select
		id,
		cpf,
		is_cpf_format,
		is_cnpj_format,
		first_digits,
		'cpf' as doc_type,
		cast(SUBSTR(first_digits, 1, 1) as integer) as col1,
		cast(SUBSTR(first_digits, 2, 1) as integer) as col2,
		cast(SUBSTR(first_digits, 3, 1) as integer) as col3,
		cast(SUBSTR(first_digits, 4, 1) as integer) as col4,
		cast(SUBSTR(first_digits, 5, 1) as integer) as col5,
		cast(SUBSTR(first_digits, 6, 1) as integer) as col6,
		cast(SUBSTR(first_digits, 7, 1) as integer) as col7,
		cast(SUBSTR(first_digits, 8, 1) as integer) as col8,
		cast(SUBSTR(first_digits, 9, 1) as integer) as col9,
		cast(0 as integer) as col10,
		cast(0 as integer) as col11,
		cast(0 as integer) as col12
	from validation_string
	where is_cpf_format = true
		and length(first_digits) = 9
	union all
	select
		id,
		cpf,
		is_cpf_format,
		is_cnpj_format,
		first_digits,
		'cnpj' as doc_type,
		cast(SUBSTR(first_digits, 1, 1) as integer),
		cast(SUBSTR(first_digits, 2, 1) as integer),
		cast(SUBSTR(first_digits, 3, 1) as integer),
		cast(SUBSTR(first_digits, 4, 1) as integer),
		cast(SUBSTR(first_digits, 5, 1) as integer),
		cast(SUBSTR(first_digits, 6, 1) as integer),
		cast(SUBSTR(first_digits, 7, 1) as integer),
		cast(SUBSTR(first_digits, 8, 1) as integer),
		cast(SUBSTR(first_digits, 9, 1) as integer),
		cast(SUBSTR(first_digits, 10, 1) as integer),
		cast(SUBSTR(first_digits, 11, 1) as integer),
		cast(SUBSTR(first_digits, 12, 1) as integer)
	from validation_string
	where is_cnpj_format = true
		and length(first_digits) = 12
),
first_linear_combination as (
	select
		id,
		doc_type,
		case when doc_type = 'cpf' then (10 * col1 + 9 * col2 + 8 * col3 + 7 * col4 + 6 * col5 + 5 * col6 + 4 * col7 + 3 * col8 + 2 * col9)
			when doc_type = 'cnpj' then (5 * col1 + 4 * col2 + 3 * col3 + 2 * col4 + 9 * col5 + 8 * col6 + 7 * col7 + 6 * col8 + 5 * col9 + 4 * col10 + 3 * col11 + 2 * col12)
			end aux1
	from unnested_digits
),
calculate_first_digit as (
	select
		id,
		cast(case when (aux1 % 11) < 2 then 0 else 11 - (aux1 % 11) end as integer) as dig1
	from first_linear_combination
),
second_linear_combination as (
	select
		ud.id,
		ud.doc_type,
		case when doc_type = 'cpf' then (11 * col1 + 10 * col2 + 9 * col3 + 8 * col4 + 7 * col5 + 6 * col6 + 5 * col7 + 4 * col8 + 3 * col9 + 2 * dig1)
			when doc_type = 'cnpj' then (6 * col1 + 5 * col2 + 4 * col3 + 3 * col4 + 2 * col5 + 9 * col6 + 8 * col7 + 7 * col8 + 6 * col9 + 5 * col10 + 4 * col11 + 3 * col12 + 2 * dig1)
			end as aux2
	from unnested_digits ud
	inner join calculate_first_digit cfd
		on ud.id = cfd.id
),
calculate_second_digit as (
	select
		id,
		case when (aux2 % 11) < 2 then 0 else 11 - (aux2 % 11) end as dig2
	from second_linear_combination
),
validate_cpfs as (
	select
		ud.id,
		ud.cpf,
		ud.is_cpf_format,
		ud.is_cnpj_format,
		ud.first_digits,
		regexp_replace(ud.cpf, '\\D+', '') as cpf_digits,
		concat(ud.first_digits,concat(cast(cfd.dig1 as string),cast(csd.dig2 as string))) as valid_cpf,
		regexp_replace(ud.cpf, '\\D+', '') rlike '\b(\d)\1+\b' as is_repeated_numbers
	from unnested_digits ud
	inner join calculate_first_digit cfd
		on cfd.id = ud.id
	inner join calculate_second_digit csd
		on csd.id = ud.id
),
cpf_validator as (
	select
		id,
		cpf,
		is_cpf_format,
		is_cnpj_format,
		cpf_digits,
		valid_cpf
	from validate_cpfs
	where is_repeated_numbers = false
),
cpf_agg_proposals as (
	select
		cpf,
		min(id_proposal) as id_first_proposal,
		max(id_proposal) as id_last_proposal
	from datalake_ebdb_clean.proponent_proposal
	group by 1
)
select
	pp.id as sk_proposal_person,
	pp.cpf as sk_personal_document,
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
		else pp.type
        end as expected_contract_role,
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
		else pp.rental_motive
        end as rental_motive,
	pp.will_live as is_going_to_live,
	(pp.id_proposal = cag.id_first_proposal) as is_first_proposal,
	(pp.id_proposal = cag.id_last_proposal) as is_last_proposal,
	coalesce(pp.monthly_salary,0) + coalesce(pp.additional_income,0) as brl_total_income,
	now() as ts_load
from datalake_ebdb_clean.proponent_proposal pp
inner join datalake_ebdb_clean.proposal p
	on pp.id_proposal = p.id
left join datalake_ebdb_clean.user u
	on p.id_proponent = u.id
	and pp.cpf = u.cpf
left join cpf_agg_proposals cag
	on cag.cpf = pp.cpf
left join cpf_validator cv
	on cv.id = pp.id