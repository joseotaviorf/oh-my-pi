with contract_to_user as (
	select 
		c.id as sk_contract,
		c.ts_signed,
		rf.id_client as sk_client,
		coalesce(h.id_user, pa_b2b_online.id_user,pa_b2b_prime.id_user, -1) as sk_owner,
  		coalesce(pa_b2b_online.id_partner, pa_b2b_prime.id_partner, -1) as sk_partner
	from datalake_ebdb_clean.contract c
	join datalake_ebdb_clean.rent_flow rf
		on c.id_house = rf.id_house
		and c.id_user = rf.id_client
	join datalake_ebdb_clean.house h
		on c.id_house = h.id
	left join datalake_ebdb_clean.partner_agent pa_b2b_prime
		on h.id_user = pa_b2b_prime.id_user
	left join datalake_ebdb_clean.conversion_lead lc
		on lc.id_house = h.id
	left join datalake_ebdb_clean.lead l
		on l.id = lc.id_converted_lead
	    and l.affiliate_type = 'B2BPartner'
	left join datalake_ebdb_clean.partner_agent pa_b2b_online
	  on pa_b2b_online.id_user = l.id_affiliate_has_indicated
),
contract_users as (
	select 
		sk_contract,
		sk_owner as user
	from contract_to_user 
	union all
	select 
		sk_contract,
		sk_client as user
	from contract_to_user
	union all
	select 
		sk_contract,
		sk_partner as user
	from contract_to_user
),
ongoing_contracts as ( 
	select 
		id,
		case when status in ('Ativo','Finalizado') 
			and type <> 'DealOnly'
			and current_date >= coalesce(date(ts_signed),dt_started,dt_entered)
			and (current_date < dt_termination or dt_termination is null)
			then true
		else false end as is_ongoing_contract
from datalake_ebdb_clean.contract
),
user_contracts as (
	select 
		uc.*,
		coalesce(oc.is_ongoing_contract,false) as is_ongoing_contract
	from contract_users uc 
	left join ongoing_contracts oc 
		on uc.sk_contract = oc.id
),
ongoing_agg as (
	select
		user,
		count(case when is_ongoing_contract = true then sk_contract end) as ongoing_contracts
	from user_contracts
	group by 1 
),
users_ongoing as (
	select 
		user,
		ongoing_contracts > 0 as has_ongoing_contract
	from ongoing_agg
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
	coalesce(uo.has_ongoing_contract,false) as has_ongoing_contract,
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
	on uo.user = cp.id_user