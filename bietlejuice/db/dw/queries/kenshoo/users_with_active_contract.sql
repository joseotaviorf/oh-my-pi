with users_with_contracts_signed as (
	select
        distinct
        rf.sk_client,
        date(ts_signature) as date,
        u.email,
        replace(u.telefone_principal, '+', '') as phone,
        c.status as status
	from fact_listing_rent_flows rf
	join dim_user u on u.sk_user = rf.sk_client
	join dim_contract c on c.sk_contract = rf.sk_contract
	where rf.sk_contract != -1
        and c.status = 'Ativo'
        and date(c.ts_signature) between dateadd(day, {days}, date('{dt}')) and date('{dt}')
)
select distinct
    f_sha256(email) as email,
    f_sha256(phone) as phone
from users_with_contracts_signed;

