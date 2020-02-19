with contract_user as (
	select 
		c.id as sk_contract,
		rf.id_client as sk_client,
		coalesce(h.id_user, pa_b2b_online.id_user, pa_b2b_prime.id_user, -1) as sk_owner,
  		coalesce(pa_b2b_online.id_partner, pa_b2b_prime.id_partner, -1) as sk_partner
	from datalake_ebdb_clean.contract c
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
	  on pa_b2b_online.id_user = l.id_agent_has_indicated
)  
select
	e.id_external as sk_invoice_entry,
	coalesce(i.id_external, -1) as sk_invoice,
	coalesce(c_rtsk.id_external, -1) as sk_contract,
	case 
        when af.type = 'tenant' or at.type = 'tenant' then coalesce(u.sk_client, -1)
		when af.type = 'landlord' or at.type = 'landlord' then coalesce(u.sk_owner, -1)
		when af.type = 'adm-partner' or at.type = 'adm-partner' then coalesce(u.sk_partner, -1)
		else -1 
	end as sk_contract_user,
	coalesce (h.id_region, -1) as sk_region,
	coalesce(cast(date_format(e.ts_created, 'YYYYMMdd') as int), -1) as sk_created_date,
	coalesce(cast(date_format(i.ts_due, 'YYYYMMdd') as int), -1) as sk_due_date,
	coalesce(cast(date_format(i.ts_paid, 'YYYYMMdd') as int), -1) as sk_paid_date,
	case 
        when af.type = 'contract' and at.type <> 'contract' then -1.0*e.amount
		else e.amount
    end as brl_entry_due_amount,
	case 
        when af.type = 'contract' and at.type <> 'contract' then round(((-1.0*e.amount/abs(i.due_amount))*i.paid_amount), 2)
		else round(((1.0*e.amount/abs(i.due_amount))*i.paid_amount), 2)	
	end as brl_entry_paid_amount,
    e.ts_created,
    now() as ts_load
from datalake_retsuko_clean.entry e
left join datalake_retsuko_clean.invoice i
	on e.id_invoice = i.id
inner join datalake_retsuko_clean.account af 
	on e.id_from_account = af.id
inner join datalake_retsuko_clean.account at 
	on e.id_to_account = at.id
left join datalake_retsuko_clean.contract c_rtsk 
	on i.id_contract = c_rtsk.id
left join datalake_ebdb_clean.contract c_ebdb
	on c_rtsk.id_external = c_ebdb.id
left join datalake_ebdb_clean.house h
	on c_ebdb.id_house = h.id
left join contract_user u 
	on u.sk_contract = c_rtsk.id_external