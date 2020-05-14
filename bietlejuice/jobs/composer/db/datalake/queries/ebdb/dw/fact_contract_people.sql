  with cpf_person as (
            select   id
                    ,cpf
                    ,case when cpf rlike '^([0-9]{3})?(\.)([0-9]{3})?(\.)([0-9]{3})?(.)([0-9]{2})$' then true
                          else false
                     end as is_cpf_format
                    ,case when cpf rlike '^([0-9]{2})?(\.)([0-9]{3})?(\.)([0-9]{3})(\/)([0-9]{4})?(.)([0-9]{2})$' then true
                          else false
                     end as is_cnpj_format
            from datalake_ebdb_clean.contract_person
            where cpf is not null
),
string_to_validate as (
              select   id
                      ,cpf
                      ,is_cpf_format
                      ,is_cnpj_format
                      ,case when is_cpf_format = true then substring(cast(regexp_replace(cpf,'\\D+','') as string),1,9)
                           when is_cnpj_format = true then substring(cast(regexp_replace(cpf,'\\D+','') as string),1,12)
                      end as first_digits
              from cpf_person
              where is_cpf_format = true or is_cnpj_format = true
),
base_doc_aux as (
              select  id
                      ,cpf
                      ,is_cpf_format
                      ,is_cnpj_format
                      ,first_digits
                      ,'cpf' as doc_type
                      ,cast(SUBSTR(first_digits, 1,1) as integer) 	as col1
                      ,cast(SUBSTR(first_digits, 2,1) as integer) 	as col2
                      ,cast(SUBSTR(first_digits, 3,1) as integer) 	as col3
                      ,cast(SUBSTR(first_digits, 4,1) as integer) 	as col4
                      ,cast(SUBSTR(first_digits, 5,1) as integer) 	as col5
                      ,cast(SUBSTR(first_digits, 6,1) as integer) 	as col6
                      ,cast(SUBSTR(first_digits, 7,1) as integer) 	as col7
                      ,cast(SUBSTR(first_digits, 8,1) as integer) 	as col8
                      ,cast(SUBSTR(first_digits, 9,1) as integer) 	as col9
                      ,cast(0 as integer)								as col10
                      ,cast(0 as integer)								as col11
                      ,cast(0 as integer)								as col12
          from 	string_to_validate
          where 	is_cpf_format = true
              and length(first_digits) = 9
          union all
              select  id
                      ,cpf
                      ,is_cpf_format
                      ,is_cnpj_format
                      ,first_digits
                      ,'cnpj'
                      ,cast(SUBSTR(first_digits, 1,1)  as integer)
                      ,cast(SUBSTR(first_digits, 2,1)  as integer)
                      ,cast(SUBSTR(first_digits, 3,1)  as integer)
                      ,cast(SUBSTR(first_digits, 4,1)  as integer)
                      ,cast(SUBSTR(first_digits, 5,1)  as integer)
                      ,cast(SUBSTR(first_digits, 6,1)  as integer)
                      ,cast(SUBSTR(first_digits, 7,1)  as integer)
                      ,cast(SUBSTR(first_digits, 8,1)  as integer)
                      ,cast(SUBSTR(first_digits, 9,1)  as integer)
                      ,cast(SUBSTR(first_digits, 10,1) as integer)
                      ,cast(SUBSTR(first_digits, 11,1) as integer)
                      ,cast(SUBSTR(first_digits, 12,1) as integer)
          from 	string_to_validate
          where 	is_cnpj_format = true
              and length(first_digits) = 12
),auxtb1 as (
          select  id
                  ,doc_type
                  ,case when doc_type = 'cpf'  then (10*col1 + 9*col2 + 8*col3 + 7*col4 + 6*col5 + 5*col6 + 4*col7 + 3*col8 + 2*col9)
                       when doc_type = 'cnpj' then (5*col1 + 4*col2 + 3*col3 + 2*col4 + 9*col5 + 8*col6 + 7*col7 + 6*col8 + 5*col9 + 4*col10 + 3*col11 + 2*col12)
                  end aux1
          from base_doc_aux
),digtb1 as (
          select	id,
                  cast(
                      case when (aux1%11) < 2 then 0
                      else 11 - (aux1%11)
                      end as integer) as dig1
          from auxtb1
),auxtb2 as (
          select  bda.id
                  ,bda.doc_type
                  ,case when doc_type = 'cpf'  then (11*col1 + 10*col2 + 9*col3 + 8*col4 + 7*col5 + 6*col6 + 5*col7 + 4*col8 + 3*col9 + 2*dig1)
                       when doc_type = 'cnpj' then (6*col1 + 5*col2 + 4*col3 + 3*col4 + 2*col5 + 9*col6 + 8*col7 + 7*col8 + 6*col9 + 5*col10 + 4*col11 + 3*col12 + 2*dig1)
                  end as aux2
          from base_doc_aux bda
          inner join digtb1 dtb1
          on bda.id = dtb1.id
),digtb2 as (
          select	 id
                  ,case when (aux2%11) < 2 then 0
                   else 11 - (aux2%11)
                   end as dig2
          from auxtb2
),valid_cpf as (
          select   bda.id
                  ,bda.cpf
                  ,bda.is_cpf_format
                  ,bda.is_cnpj_format
                  ,bda.first_digits
                  ,regexp_replace(bda.cpf,'\\D+','') as cpf_digits
                  ,concat(bda.first_digits,concat(cast(digtb1.dig1 as string),cast(digtb2.dig2 as string))) as valid_cpf
                  ,case when regexp_replace(bda.cpf,'\\D+','') rlike '\b(\d)\1+\b' then true else false end as is_repeated_numbers
          from   base_doc_aux bda
          inner join digtb1 on digtb1.id = bda.id
          inner join digtb2 on digtb2.id = bda.id
),cpf_validator as (
          select	id
                  ,cpf
                  ,is_cpf_format
                  ,is_cnpj_format
                  ,cpf_digits
                  ,valid_cpf
          from valid_cpf
          where is_repeated_numbers = false
),contract_to_user as (
          select  c.id as sk_contract,
                  c.ts_signed,
                  rf.id_client as sk_client,
                  coalesce(h.id_user, pa_b2b_online.id_user,pa_b2b_prime.id_user, -1) as sk_owner,
                  coalesce(pa_b2b_online.id_partner, pa_b2b_prime.id_partner, -1) as sk_partner
          from    datalake_ebdb_clean.contract c
          inner join datalake_ebdb_clean.rent_flow rf
              on c.id_house = rf.id_house
              and c.id_user = rf.id_client
          inner join datalake_ebdb_clean.house h
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
), contract_users as (
          select  sk_contract,
                    sk_owner as user,
                    ts_signed
          from contract_to_user
          union all
          select  sk_contract,
                    sk_client as user,
                    ts_signed
          from    contract_to_user
          union all
          select  sk_contract,
                    sk_partner as user,
                    ts_signed
          from    contract_to_user
),distinct_contract_users as (
          select  user,
                  sk_contract,
                  ts_signed
          from    contract_users
          group by user,
                  sk_contract,
                  ts_signed
),first_last_contract as (
          select
              user,
              min(sk_contract) as id_first_contract,
              max(sk_contract) as id_last_contract
          from distinct_contract_users
          group by 1
)select
	cp.id,
	cp.cpf,
	coalesce(cp.id_user,-1) as sk_user,
	c.id as sk_contract,
	coalesce(cast(date_format(cp.dt_birth, 'yyyyMMdd') as bigint), -1) as sk_birth_date,
	coalesce(cast(date_format(cp.ts_created, 'yyyyMMdd') as bigint), -1) as sk_created_date,
	coalesce(cast(date_format(cp.ts_updated, 'yyyyMMdd') as bigint), -1) as sk_updated_date,
	case when cp.type = 'Fiador' then 'sponsor'
		when cp.type = 'Inquilino' then 'tenant'
		when cp.type = 'Morador' then 'dweller'
		when cp.type = 'Partner' then 'partner'
		when cp.type = 'Proprietario' then 'landlord'
		end as contract_role,
	u.id is not null as is_user,
		(cv.is_cpf_format = true and cv.valid_cpf = cast(regexp_replace(cp.cpf,'\\D+','') as string)) as is_valid_cpf,
		(cv.is_cnpj_format = true and cv.valid_cpf = cast(regexp_replace(cp.cpf,'\\D+','') as string)) as is_valid_cnpj,
	case when cp.type = 'Inquilino' and cp.id_user = cu.sk_client then true
		when cp.type = 'Proprietario' and cp.id_user = cu.sk_owner then true
		when cp.type = 'Partner' and cp.id_user = cu.sk_partner then true
		else false
		end as is_contract_user,
	cp.will_live as is_living,
	case when sk_contract = fl.id_first_contract then true else false end as is_first_contract,
	case when sk_contract = fl.id_last_contract then true else false end as is_last_contract,
	current_timestamp as ts_load
from datalake_ebdb_clean.contract_person cp
left join datalake_ebdb_clean.contract c
	on cp.id_contract = c.id
left join datalake_ebdb_clean.user u
	on u.id = cp.id_user
	and cp.id_user is not null
left join contract_to_user cu
	on cu.sk_contract = cp.id_contract
left join first_last_contract fl
	on fl.user = cp.id_user
left join cpf_validator cv
		on cp.id = cv.id
