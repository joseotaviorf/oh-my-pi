with landing_pages as (
	select 
		distinct date_submitted,
		time_submitted,
		substring(time_submitted,7,9) as time_op,
		substring(time_submitted,1,5) as teste,
		cast(substring(time_submitted,1,2) as bigint) as hour_submitted,
		replace(substring(substr(time_submitted,3,4),2,3), ' ', '')  as minute_submitted,
		nome_completo_do_novo_inquilino as nome_inquilino,
		lower(email_do_novo_inquilino) as email_inquilino,
		telefone_celular_do_novo_inquilino as celular_inquilino,
		seu_nome_completo as nome_corretor,
		seu_telefone_celular as telefone_corretor,
		seu_email as email_corretor,
		creci
	from datalake_raw.gsheets_agent_recommendation_tenant gart
	order by 1
),
converted_hours as (
	select 
		date_submitted,
		time_submitted,
		hour_submitted,
		case when time_op = 'PM UTC' and hour_submitted < 12 then cast(substring(time_submitted,1,2) as bigint) + 12 
			when time_op = 'AM UTC' and hour_submitted = 12 then 00 else hour_submitted end  as correct_hour,
		minute_submitted,
		nome_inquilino,
		email_inquilino,
		celular_inquilino,
		nome_corretor,
		telefone_corretor,
		email_corretor,
		creci
	from landing_pages
),
adjuste_hour as(
	select 
		date_submitted,
		time_submitted,
		hour_submitted,
		case when correct_hour < 10 then '0'|| cast(correct_hour as varchar) else cast(correct_hour as varchar) end as correct_hour,
		minute_submitted,
		nome_inquilino,
		email_inquilino,
		celular_inquilino,
		nome_corretor,
		telefone_corretor,
		email_corretor,
		creci	
	from converted_hours
),
correct_hour as (
	select 
		date_submitted,
		time_submitted,
		cast((date_submitted || ' ' || correct_hour || ':' || minute_submitted || ':00') as timestamp) as date_hour,
		nome_inquilino,
		email_inquilino,
		celular_inquilino,
		nome_corretor,
		telefone_corretor,
		email_corretor,
		creci
	from adjuste_hour
),
leads_users as (
	select
		date_hour,
		nome_inquilino,
		email_inquilino,
		celular_inquilino,
		nome_corretor,
		telefone_corretor,
		email_corretor,
		creci,
		coalesce(cast(lead(date_hour) over(partition by email_inquilino order by date_hour) as timestamp), current_date) as last_date_email,
		coalesce(cast(lead(date_hour) over(partition by celular_inquilino order by date_hour) as timestamp), current_date) as last_date_cell,
		coalesce(cast(lead(date_hour) over(partition by email_inquilino order by date_hour desc) as timestamp), date_hour) as first_date_email,
		coalesce(cast(lead(date_hour) over(partition by celular_inquilino order by date_hour desc) as timestamp),date_hour) as first_date_cell
    from correct_hour
),
rk_date as (
	select
		date_hour,
		last_date_email,
		first_date_email,
		date_diff('day',date_hour,last_date_email) as vl_date_email,
		date_diff('day', date_hour, current_date) as vl_date2_email,
		date_diff('day', first_date_email, date_hour) as vl_fdate_email,
		last_date_cell,
		first_date_cell,
		date_diff('day',date_hour,last_date_cell) as vl_date_cell,
		date_diff('day', date_hour, current_date) as vl_date2_cell,
		date_diff('day',first_date_cell, date_hour) as vl_fdate_cell,
		nome_inquilino,
		email_inquilino,
		celular_inquilino,
		nome_corretor,
		telefone_corretor,
		email_corretor,
		creci,
		rank() over(partition by email_inquilino order by date_hour) as rkemail_vl_date,
		rank() over(partition by celular_inquilino order by date_hour) as rkcell_vl_date
	from leads_users
),
define_status_validate as (
	select
		date_hour,
		last_date_email,
		first_date_email,
		vl_date_email,
		vl_date2_email,
		vl_fdate_email,
		last_date_cell,
		first_date_cell,
		vl_date_cell,
		vl_date2_cell,
		vl_fdate_cell,
		nome_inquilino,
		email_inquilino,
		celular_inquilino,
		nome_corretor,
		telefone_corretor,
		email_corretor,
		creci,
		rkemail_vl_date,
		rkcell_vl_date,
		case
			when (vl_date2_cell >= 30 or vl_date2_email >= 30) then 'Descarte por validade' else 'Lead valido' end as vl_status_descartado
	from rk_date
),
rk_lead_valido as (
    select 
        date_hour,
        last_date_email,
        vl_date_email,
        vl_date2_email,
        vl_fdate_email,
        last_date_cell,
        vl_date_cell,
        vl_date2_cell,
        vl_fdate_cell,
        nome_inquilino,
        email_inquilino,
        celular_inquilino,
        nome_corretor,
        telefone_corretor,
        email_corretor,
        creci,
        rkemail_vl_date,
        rkcell_vl_date,
        vl_status_descartado,
        rank() over(partition by email_inquilino order by date_hour) as rkemail_valido,
        rank() over(partition by celular_inquilino order by date_hour) as rkcell_valido
    from define_status_validate
    where vl_status_descartado != 'Descarte por validade'
),
vl_duplicidade as (
    select
        dd.date_hour,
        dd.last_date_email,
        dd.vl_date_email,
        dd.vl_date2_email,
        dd.vl_fdate_email,
        dd.last_date_cell,
        dd.vl_date_cell,
        dd.vl_date2_cell,
        dd.vl_fdate_cell,
        dd.nome_inquilino,
        dd.email_inquilino,
        dd.celular_inquilino,
        dd.nome_corretor,
        dd.telefone_corretor,
        dd.email_corretor,
        dd.creci,
        dd.rkemail_vl_date,
        dd.rkcell_vl_date,
        dd.vl_status_descartado,
        rlv.rkemail_valido,
        rlv.rkcell_valido,
        rank() over(partition by dd.email_inquilino, dd.vl_status_descartado order by dd.date_hour) as rkemail_status,
        rank() over(partition by dd.celular_inquilino, dd.vl_status_descartado order by dd.date_hour ) as rkcell_status
    from define_status_validate dd
    left join rk_lead_valido rlv
        on dd.date_hour = rlv.date_hour 
        and dd.email_inquilino = rlv.email_inquilino
        and dd.celular_inquilino = rlv.celular_inquilino
),
validacao_feita as (
    select
        date_hour,
        last_date_email,
        vl_date_email,
        vl_date2_email,
        last_date_cell,
        vl_date_cell,
        vl_date2_cell,
        nome_inquilino,
        email_inquilino,
        celular_inquilino,
        nome_corretor,
        telefone_corretor,
        email_corretor,
        creci,
        vl_status_descartado,
        rkemail_vl_date,
        rkcell_vl_date,
        rkemail_status,
        rkcell_status,
        rkemail_valido,
        rkcell_valido,
        case
            when rkcell_vl_date = 1 and rkemail_vl_date = 1 and vl_date2_cell < 30 and vl_date2_email < 30 and vl_date_email < 30 and vl_date_cell < 30 then 'Lead valido'
            when vl_date_email < 30 and vl_date_cell < 30 and vl_date2_cell < 30 and vl_date2_email < 30 and (vl_fdate_cell >=30 or vl_fdate_email >= 30) then 'Lead valido'
            when (rkcell_status > 1 or rkemail_vl_date > 1) and (vl_date2_cell <= 30 or vl_date2_email <= 30) then 'Descarte por duplicidade'
            when rkcell_vl_date > 1 or rkemail_vl_date > 1 then 'Descarte por duplicidade' else vl_status_descartado end as status_lead
    from vl_duplicidade
),
processing_leads as (
	select
		date_hour - interval '3' hour as date_hour,
		last_date_email,
        vl_date_email,
		vl_date2_email,
        last_date_cell,
        vl_date_cell,
		vl_date2_cell,
		nome_inquilino,
		email_inquilino,
		concat('+55', celular_inquilino) as celular_inquilino,
		nome_corretor,
		telefone_corretor,
		email_corretor,
		creci,
		status_lead
		from validacao_feita
	order by 1
),
visitor_lisiting_page_view as (
    with listing_page_viewed AS (
        SELECT
            DISTINCT evt.id_user,
            CAST(evt.ts_event AS TIMESTAMP) AS event_timestamp,
            coalesce(ep_house_id, '') AS house_id,
            TRIM(evt.event_type) AS event
        FROM datalake_amplitude_clean_prod."170698_listing_page_viewed_events" evt
        WHERE cast(ts_event as date) >= cast('2019-05-01' as date)
	)
	SELECT 
	  du.sk_user,
	  du.email,
	  du.nome,
	  du.telefone_principal,
	  COUNT(*) AS listing_page_views,
	  cast(lpv.event_timestamp as date) AS latest_pageview
	FROM listing_page_viewed lpv
	JOIN datalake_clean.ods_dim_user du
	  ON lpv.id_user = du.sk_user
	where lpv.event_timestamp >= date('2019-06-01') 
	GROUP BY 1, 2, 3, 4, 6
	ORDER BY 6 desc			
),
last_lpv as (
    select 
        vlpv.*
    from visitor_lisiting_page_view vlpv
    where vlpv.latest_pageview >= (current_date - interval '61' day)
),
contract_signed as (
	SELECT 
		cast(dc.ts_signature as timestamp) as dt_signature,
		dc.id_contract,
		dhl.id_house,
		duv.nome,
		lower(duv.email) as email,
		duv.telefone_principal,
		dc.rent,
		dr.city_group
	FROM datalake_clean.ods_fact_listing_rent_flows  AS flrf
	FULL OUTER JOIN datalake_clean.ods_dim_house_listing  AS dhl 
		ON flrf.sk_house_listing = dhl.sk_house_listing 
	LEFT JOIN datalake_clean.ods_fact_house_listings AS fhl
		ON fhl.sk_house_listing = dhl.sk_house_listing 
	LEFT JOIN datalake_clean.ods_dim_region  AS dr 
		ON fhl.sk_region = dr.sk_region 
	LEFT JOIN datalake_clean.ods_dim_contract  AS dc 
		ON flrf.sk_contract = dc.sk_contract 
	LEFT JOIN datalake_clean.ods_dim_user  AS duv 
		ON flrf.sk_client = duv.sk_user 
	WHERE 
		(dc.ts_signature  >= '2019-06-25')
	GROUP BY 1,2,3,4,5,6,7,8
	ORDER BY 3 
),
leads_to_contract as (
	select
		nll.date_hour,
		nll.last_date_email,	
		nll.nome_inquilino,
		nll.email_inquilino,
		nll.celular_inquilino,
		nll.nome_corretor,
		nll.telefone_corretor as celular_corretor,
		nll.email_corretor,
		nll.creci,
		nll.status_lead,
		case when cs.email is not null and (date_diff('day',nll.date_hour,cs.dt_signature)) < 31 and status_lead != 'Descarte por duplicidade' then 'Convertido' else null end as status_lead_convertido,
		cs.city_group,
		cs.dt_signature,
		cs.rent
	from processing_leads nll
	left join contract_signed cs
		on (lower(nll.email_inquilino) = cs.email or nll.celular_inquilino = cs.telefone_principal)
		and nll.date_hour < cs.dt_signature
	order by 1
),
status_convertido as (
    select 
        cast((date_hour - interval '31' day)as date) as min_date_hour,
        cast((date_hour - interval '1' day)as date) as max_date_hour,
        date_hour,	
        nome_inquilino,
        email_inquilino,
        celular_inquilino,
        nome_corretor,
        celular_corretor,
        email_corretor,
        creci,
        status_lead,
        status_lead_convertido,
        case when status_lead_convertido is not null then city_group else null end as city_group,
        case when status_lead_convertido is not null then dt_signature else null end as dt_signature,
        case when status_lead_convertido is not null then rent else null end as rent
    from leads_to_contract
    where status_lead_convertido is not null
),
convertidos as (
    select 
        sc.min_date_hour,
        sc.max_date_hour,
        min(sc.date_hour) as date_hour,
        sc.email_inquilino,
        sc.celular_inquilino,
        sc.status_lead_convertido,
        sc.status_lead,
        max(case when vlpv.latest_pageview between sc.min_date_hour and sc.max_date_hour and sc.status_lead_convertido is not null then'Descartado por duplicidade de user' else 'Convertido' end) as vl_status_convertido,
        sc.city_group,
        sc.dt_signature,
        sc.rent
    from status_convertido sc
    left join visitor_lisiting_page_view vlpv
        on (sc.email_inquilino = vlpv.email or sc.celular_inquilino = vlpv.telefone_principal)
    group by 1,2,4,5,6,7,9,10,11
    order by 3
),
base as (
    select 
        pl.date_hour,
        max(pl.nome_corretor) as nome_corretor,
        pl.email_corretor,	
        pl.telefone_corretor as celular_corretor,
        pl.creci,
        '' as parceiriaB2B,
        '' as agent5a,
        replace(pl.nome_inquilino, 'Nome: 	','') as nome_inquilino,
        pl.email_inquilino,
        pl.celular_inquilino,
        coalesce(c.vl_status_convertido, pl.status_lead) as status,
        case when vl_status_convertido is not null and (pl.status_lead != 'Descartado por duplicidade de cell' or pl.status_lead != 'Descartado por duplicidade de user') then dt_signature else null end as date_signature,
        case when vl_status_convertido is not null and (pl.status_lead != 'Descartado por duplicidade de cell' or pl.status_lead != 'Descartado por duplicidade de user') then rent else null end as rent,
        case when vl_status_convertido is not null and (pl.status_lead != 'Descartado por duplicidade de cell' or pl.status_lead != 'Descartado por duplicidade de user') then city_group else null end as city_group
    from processing_leads pl
    left join convertidos c
        on (pl.email_inquilino = c.email_inquilino or pl.celular_inquilino = c.celular_inquilino)
        and pl.date_hour = c.date_hour
    group by 1,3,4,5,6,7,8,9,10,11,12,13,14
    order by 1
),
base_validos as (
    select 
        cast((date_hour - interval '32' day)as date) as min_date_hour,
        cast((date_hour - interval '1' day)as date) as max_date_hour,
        *
    from base
    where status = 'Lead valido'
),
status_leads_validos as (
    select
        min_date_hour,
        max_date_hour,
        date_hour,
        max(email_inquilino) as email_inquilino,
        celular_inquilino,
        case when (latest_pageview between bv.min_date_hour and bv.max_date_hour) then'Descartado por duplicidade de user' else 'Lead valido' end as vl_status_lead
    from base_validos bv
    left join last_lpv ll
        on (bv.email_inquilino = ll.email or bv.celular_inquilino = ll.telefone_principal)
        and ll.latest_pageview > bv.min_date_hour and ll.latest_pageview <= bv.max_date_hour
    group by 1,2,3,5,6
),
final_base as (
    select
        b.date_hour,
        b.nome_corretor,
        b.email_corretor,	
        b.celular_corretor,
        b.creci,
        b.parceiriaB2B,
        b.agent5a,
        max(b.nome_inquilino) AS nome_inquilino,
        b.email_inquilino,
        b.celular_inquilino,
        coalesce(slv.vl_status_lead,b.status) as status_final,
        b.date_signature,
        b.rent,
        b.city_group
    from base b
    left join status_leads_validos slv
        on b.date_hour = slv.date_hour
        and b.email_inquilino = slv.email_inquilino
        and b.celular_inquilino = slv.celular_inquilino
    group by 1,2,3,4,5,6,7,9,10,11,12,13,14
    order by 1
)
select 
	date_hour,
	nome_corretor,
	email_corretor,	
	celular_corretor,
	creci,
	parceiriaB2B,
	agent5a,
	nome_inquilino,
	email_inquilino,
	celular_inquilino,
	status_final,
	case when status_final = 'Convertido' then date_signature else null end as date_signature,
	case when status_final = 'Convertido' then rent else null end as rent,
	case when status_final = 'Convertido' then city_group else null end as city_group	
from final_base