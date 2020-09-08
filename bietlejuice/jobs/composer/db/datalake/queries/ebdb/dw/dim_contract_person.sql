with contract_users as (
	select
		id as id_contract,
		id_user
	from datalake_ebdb_clean.contract
	union all
	select
		c.id as id_contract,
		h.id_user as id_user
	from datalake_ebdb_clean.contract c
	inner join datalake_ebdb_clean.house h
		on h.id = c.id_house
),
contract_cpfs as (
	select
		id_contract,
		cpf
	from datalake_ebdb_clean.contract_person
),
ongoing_contracts as (
	select
		id as id_contract,
		case when status in ('Ativo','Finalizado')
			and type <> 'DealOnly'
			and current_date >= coalesce(date(ts_signed),dt_started,dt_entered)
			and (current_date < dt_termination or dt_termination is null)
			then true
		else false end as is_ongoing_contract
	from datalake_ebdb_clean.contract
),
users_ongoing as (
	select
		cu.id_user,
		MAX(oc.id_contract) as id_max_ongoing_contract
	from contract_users cu
	inner join ongoing_contracts oc
		on cu.id_contract = oc.id_contract
	where oc.is_ongoing_contract = true
	group by 1
),
cpfs_ongoing as (
	select
		cc.cpf,
		MAX(oc.id_contract) as id_max_ongoing_contract
	from contract_cpfs cc
	inner join ongoing_contracts oc
		on cc.id_contract = oc.id_contract
	where oc.is_ongoing_contract = true
	group by 1
)
select
	cp.id as sk_contract_person,
	cp.name as full_name,
	cp.phone_number,
	cp.email,
	cp.cpf as personal_document,
	case when cp.cpf rlike '([0-9]{3})(.)([0-9]{3})(.)([0-9]{3})(-)([0-9]{2})' then 'CPF'
		when cp.cpf rlike '([0-9]{2})(.)([0-9]{3})(.)([0-9]{3})(\/)([0-9]{4})(-)([0-9]{2})' then 'CNPJ'
	end as personal_document_type,
	coalesce(uo.id_max_ongoing_contract,co.id_max_ongoing_contract) > 0 as has_ongoing_contract,
	replace(lower(cp.gender), 'o', 'e') as gender,
	case when cp.marital_status = 'Amasiado' then 'common-law marriage'
		when cp.marital_status = 'Casado' then 'married'
		when cp.marital_status = 'Desquitado' then 'separated'
		when cp.marital_status = 'Divorciado' then 'divorced'
		when cp.marital_status = 'Separado' then 'separated'
		when cp.marital_status = 'Solteiro' then 'single'
		when cp.marital_status = 'Viuvo' then 'widower'
		end as marital_status,
	cp.state_id as state_code,
	cp.dt_birth,
	cp.ts_created,
	cp.ts_updated,
	current_timestamp as ts_load
from datalake_ebdb_clean.contract_person cp
left join users_ongoing uo
	on uo.id_user = cp.id_user
left join cpfs_ongoing co
	on co.cpf = cp.cpf