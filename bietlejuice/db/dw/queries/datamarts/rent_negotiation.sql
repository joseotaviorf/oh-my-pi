WITH anniversary_contracts AS (
    SELECT 
    	dc.sk_contract,
    	dc.dt_entrance,
    	dd.date AS anniversary_date,
    	t.dt_termination AS dt_annulment,
    	dc.is_b2b,
    	dc.status,
    	fhl.sk_house_listing
    FROM dim_contract dc 
    LEFT JOIN datalake_terminator_clean_prod.termination t 
        ON t.id_contract = dc.sk_contract AND t.status != 'CANCELED'
    INNER JOIN dim_date dd 
        ON extract(day FROM dt_entrance) = dd.day AND extract(month FROM dt_entrance) = dd.month AND extract(year FROM dt_entrance) < dd.year AND dd.year <= COALESCE(extract(year FROM dt_termination) , extract(year FROM date '2021-01-01') + 1 )
    LEFT JOIN fact_house_listings fhl
	ON fhl.sk_contract = dc.sk_contract
    WHERE dc.status IN ('Ativo', 'Finalizado')
        AND dd.date >= date '2020-10-01'
        AND COALESCE(date_trunc('month', t.dt_termination), current_date + interval '3' month) >= date_trunc('month', dd.date)
), pwa_negotiation AS (
    SELECT 
	id_contract AS pwa_contract, 
	to_timestamp(ts_created, 'YYYY-MM-DD HH:MI:SS') AS pwa_neg_created,
	status,
	type
    FROM datalake_ebdb_clean_prod.contract_negotiation cn 
    WHERE date(ts_created) >= date '2020-10-01'
	AND cn.type IN ('IPCA_ADJUSTMENT', 'PRICE_INDEX_EXEMPTION', 'IGPM_FREEZE','FIXED_VALUE_ADJUSTMENT','KEEP_CONTRACT_ADJUSTMENT')
), tickets_negotiation AS (
    SELECT 
	ft.sk_contract AS ticket_contract,
	dt.sk_ticket,
	to_timestamp(dt.ts_created_local, 'YYYY-MM-DD HH:MI:SS') AS ticket_neg_created,
	to_timestamp(ft.ts_solved_local, 'YYYY-MM-DD HH:MI:SS') AS ticket_neg_solved,
	CASE 
            WHEN dt.tags ILIKE '%aprovada%' THEN 'approved' 
            WHEN dt.tags ILIKE '%negada%' THEN 'not approved' 
            ELSE NULL
        END AS tag_status,
        dt.status AS ticket_status,
        COALESCE(dt.client_type, dt.customer_type_tag) AS customer
    FROM zendesk.dim_ticket dt
    INNER JOIN zendesk.fact_tickets ft 
        ON ft.sk_ticket = dt.sk_ticket 
    LEFT JOIN anniversary_contracts ac
        ON ft.sk_house_listing = ac.sk_house_listing
    WHERE group_name ILIKE '%negociação%'
	    AND (dt.tags ILIKE '%igpm%' OR dt.tags ILIKE '%ipca%' 
	    OR dt.description ILIKE '%igpm%' OR dt.description ILIKE '%igp-m%' 
	    OR dt.description ILIKE '%ipca%' OR dt.subject ILIKE '%igpm%' 
	    OR dt.subject ILIKE '%igp-m%' OR dt.subject ILIKE '%ipca%')
	    AND ft.sk_contract > 0
	    AND dt.tags NOT ILIKE '%closed_by_merge%'
	UNION 
	SELECT 
	    ac.sk_contract AS ticket_contract,
            dt.sk_ticket,
	    to_timestamp(dt.ts_created_local, 'YYYY-MM-DD HH:MI:SS') AS ticket_neg_created,
	    to_timestamp(ft.ts_solved_local, 'YYYY-MM-DD HH:MI:SS') AS ticket_neg_solved,
	    CASE 
            WHEN dt.tags ILIKE '%aprovada%' THEN 'approved'
            WHEN dt.tags ILIKE '%negada%' THEN 'not approved'
            ELSE NULL
        END AS tag_status,
        dt.status AS ticket_status,
        COALESCE(dt.client_type, dt.customer_type_tag) AS customer
    FROM zendesk.dim_ticket dt
    INNER JOIN zendesk.fact_tickets ft
        ON ft.sk_ticket = dt.sk_ticket
    LEFT JOIN anniversary_contracts ac
        ON ft.sk_house_listing = ac.sk_house_listing
    WHERE group_name ILIKE '%negociação%'
	    AND (dt.tags ILIKE '%igpm%' OR dt.tags ILIKE '%ipca%'
	    OR dt.description ILIKE '%igpm%' OR dt.description ILIKE '%igp-m%'
	    OR dt.description ILIKE '%ipca%' OR dt.subject ILIKE '%igpm%'
	    OR dt.subject ILIKE '%igp-m%' OR dt.subject ILIKE '%ipca%')
	    AND ft.sk_contract < 0 AND ft.sk_house_listing > 0
	    AND dt.tags NOT ILIKE '%closed_by_merge%'
    GROUP BY 1, 2, 3, 4, 5, 6, 7
), first_and_last_tickets AS (
    SELECT 
        ticket_contract,
        MAX(sk_ticket) AS last_ticket,
        MIN(sk_ticket) AS first_ticket
    FROM tickets_negotiation 
    GROUP BY 1
), consolidated_tickets AS (
    SELECT 
        fl.ticket_contract,
        fl.first_ticket,
        first.ticket_neg_created AS first_ticket_neg_created,
        first.ticket_neg_solved AS first_ticket_neg_solved,
        first.tag_status AS first_tag_status,
        first.ticket_status AS first_ticket_status,
        first.customer AS first_customer,
        fl.last_ticket,
        last.ticket_neg_created AS last_ticket_neg_created,
        last.ticket_neg_solved AS last_ticket_neg_solved,
        last.tag_status AS last_tag_status,
        last.ticket_status AS last_ticket_status,
        last.customer AS last_customer
    FROM first_and_last_tickets fl
    INNER JOIN tickets_negotiation last
        ON last.sk_ticket = fl.last_ticket 
    INNER JOIN tickets_negotiation first
        ON first.sk_ticket = fl.first_ticket 
), crm_negotiation AS (
    SELECT DISTINCT 
        fpt.sk_contract AS crm_contract,
    	first_value(fpt.ts_action) OVER (PARTITION BY fpt.sk_contract ORDER BY fpt.ts_action DESC rows between unbounded preceding AND unbounded following) AS crm_date_start,
    	first_value(fpt.sk_task) OVER (PARTITION BY fpt.sk_contract ORDER BY fpt.ts_action DESC rows between unbounded preceding AND unbounded following) AS sk_task,
    	CASE WHEN false = first_value(flg_solved) OVER (PARTITION BY fpt.sk_contract ORDER BY fpt.ts_action DESC rows between unbounded preceding AND unbounded following) THEN 'open' ELSE 'closed' END AS status
    FROM crm.dim_payment_task dpt
    LEFT JOIN crm.fact_payment_tasks fpt 
        ON fpt.sk_task = dpt.sk_task
    WHERE
        dpt.workgroups IN ('[DEP_FINANCEIRO_ID]','[DEP_ACORDOS_DESCONTOS_ID]')
        AND fpt.action_type IN ('CREATE', 'REALIZE')
        AND (lower(dpt.description) LIKE '%igpm%' OR lower(dpt.description) LIKE '%igp-m%' OR lower(dpt.description) LIKE '%ipca%' OR lower(dpt.description) LIKE '%ipc-a%')
        AND fpt.sk_contract > 0
), forms_negotiation AS (
    SELECT 
        sk_contract::bigint AS form_contract, 
        sk_request,
        origin_request,
        to_timestamp(ts_request, 'YYYY-MM-DD HH:MI:SS') AS form_request_created,
        MIN(ts_request_execution) AS min_ts_request_execution,
        MIN(CASE WHEN ts_request_execution SIMILAR TO '\\d{1,4}\\-\\d{1,2}\\-\\d{1,2} \\d{1,2}:\\d{2}:\\d{2}' THEN to_timestamp(ts_request_execution, 'YYYY-MM-DD HH:MI:SS') END)  first_execution
    FROM datalake_raw.gsheets_payments_deals_and_discounts
    WHERE charge ILIKE '%IGPM%' OR origin_form ILIKE '%IGPM%' OR origin_form ILIKE '%Alteração de Valor de Reajuste%'
        AND is_canceled IS NULL 
        AND ts_request_execution NOT ILIKE '%incorreto%'
        AND ts_request_execution NOT ILIKE '%errado%'
        AND ts_request_execution NOT ILIKE '%cancela%'
        AND ts_request_execution NOT ILIKE '%do%'
        AND ts_request_execution NOT ILIKE '%fatura%'
    GROUP BY 1,2,3,4
), form_automation AS (
    SELECT
        form_contract,
        sk_request,
        origin_request,
        form_request_created,
        min_ts_request_execution,
        first_execution,
        CASE 
            WHEN min_ts_request_execution = ' ' THEN 'pending automation'
            WHEN min_ts_request_execution ILIKE '%:%' THEN 'finished'
            ELSE NULL
        END AS status
    FROM forms_negotiation
), form_2 AS (
    SELECT
        CASE 
            WHEN sk_contract IS NULL OR sk_contract = '' THEN NULL 
            ELSE sk_contract::bigint 
        END AS form2_contract,
        text,
        percentage,
        previous_value,
        new_value,
        index,
        CASE 
            WHEN ts_request_executed IS NULL OR ts_request_executed = '' OR regexp_replace(sla, '[^0-9]+', '') IS NULL OR regexp_replace(sla, '[^0-9]+', '') = '' THEN NULL
            ELSE date_add('day',-sla::bigint,to_date(ts_request_executed, 'YYYY-MM-DD'))
        END AS ts_request_created,
        CASE 
            WHEN ts_request_executed SIMILAR TO '\\d{1,4}\\-\\d{1,2}\\-\\d{1,2} \\d{1,2}:\\d{2}:\\d{2}' THEN to_timestamp(ts_request_executed, 'YYYY-MM-DD HH:MI:SS') 
        END AS ts_request_executed,
        summary,
        regexp_replace(sla, '[^0-9]+', '') AS sla,
        CASE 
            WHEN ts_request_executed IS NULL OR ts_request_executed = '' OR regexp_replace(sla, '[^0-9]+', '') IS NULL OR regexp_replace(sla, '[^0-9]+', '') = '' THEN 'pending automation' ELSE 'finished' 
        END AS status 
    FROM datalake_raw.gsheets_payments_automation_igpm
    WHERE NOT sk_contract LIKE '%-%' 
)
    SELECT 
        nc.sk_contract,
        nc.is_b2b,
        nc.status AS contract_status,
        to_char(trunc(nc.dt_entrance),'mm/dd/yyyy') AS dt_entrance,
        date_part('month', nc.dt_entrance) AS month,
        date_part('year', nc.dt_entrance) AS year,
        to_char(trunc(nc.anniversary_date),'mm/dd/yyyy') AS dt_anniversary,
        to_char(trunc(nc.dt_annulment),'mm/dd/yyyy') AS dt_annulment,
        CASE 
            WHEN pn.pwa_contract IS NOT NULL THEN TRUE 
            WHEN cn.crm_contract IS NOT NULL THEN TRUE
            WHEN tn.ticket_contract IS NOT NULL AND tn.last_tag_status = 'approved' AND tn.last_ticket_neg_solved IS NOT NULL THEN TRUE
            WHEN fa.form_contract IS NOT NULL OR f2.form2_contract IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS is_negotiated,
        CASE 
            WHEN COALESCE(COALESCE(COALESCE(COALESCE(pn.pwa_contract, cn.crm_contract), tn.ticket_contract), fa.form_contract::bigint),f2.form2_contract::bigint) IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS has_any_negotiation, 
        CASE 
            WHEN pn.pwa_contract IS NOT NULL AND cn.crm_contract IS NULL AND tn.ticket_contract IS NULL AND fa.form_contract IS NULL AND f2.form2_contract IS NULL THEN 'pwa'
            WHEN pn.pwa_contract IS NULL AND cn.crm_contract IS NOT NULL AND tn.ticket_contract IS NULL AND fa.form_contract IS NULL AND f2.form2_contract IS NULL THEN 'crm'
            WHEN pn.pwa_contract IS NULL AND cn.crm_contract IS NULL AND tn.ticket_contract IS NOT NULL AND fa.form_contract IS NULL AND f2.form2_contract IS NULL THEN 'ticket'
            WHEN pn.pwa_contract IS NULL AND cn.crm_contract IS NULL AND tn.ticket_contract IS NULL AND (fa.form_contract IS NOT NULL OR f2.form2_contract IS NOT NULL) THEN 'forms'
            WHEN pn.pwa_contract IS NULL AND fa.form_contract IS NULL AND cn.crm_contract IS NOT NULL AND tn.ticket_contract IS NOT NULL AND f2.form2_contract IS NULL THEN 'ticket & crm'
            WHEN pn.pwa_contract IS NULL AND (fa.form_contract IS NOT NULL OR f2.form2_contract IS NOT NULL) AND cn.crm_contract IS NULL AND tn.ticket_contract IS NOT NULL THEN 'ticket & forms'
            WHEN pn.pwa_contract IS NOT NULL AND fa.form_contract IS NULL AND cn.crm_contract IS NOT NULL AND tn.ticket_contract IS NULL AND f2.form2_contract IS NULL THEN 'pwa & crm'
            WHEN pn.pwa_contract IS NOT NULL AND (fa.form_contract IS NOT NULL OR f2.form2_contract IS NOT NULL) AND cn.crm_contract IS NULL AND tn.ticket_contract IS NULL THEN 'pwa & forms'
            WHEN pn.pwa_contract IS NULL AND (fa.form_contract IS NOT NULL OR f2.form2_contract IS NOT NULL) AND cn.crm_contract IS NOT NULL AND tn.ticket_contract IS NULL THEN 'forms & crm'
            WHEN pn.pwa_contract IS NOT NULL AND fa.form_contract IS NULL AND cn.crm_contract IS NULL AND tn.ticket_contract IS NOT NULL AND f2.form2_contract IS NULL THEN 'ticket & pwa'
            WHEN pn.pwa_contract IS NOT NULL AND (fa.form_contract IS NOT NULL OR f2.form2_contract IS NOT NULL) AND cn.crm_contract IS NOT NULL AND tn.ticket_contract IS NULL THEN 'pwa & form & crm'
            WHEN pn.pwa_contract IS NOT NULL AND (fa.form_contract IS NOT NULL OR f2.form2_contract IS NOT NULL) AND cn.crm_contract IS NULL AND tn.ticket_contract IS NOT NULL THEN 'pwa & form & ticket'
            WHEN pn.pwa_contract IS NOT NULL AND fa.form_contract IS NULL AND cn.crm_contract IS NOT NULL AND tn.ticket_contract IS NOT NULL AND f2.form2_contract IS NULL THEN 'pwa & crm & ticket'
            WHEN pn.pwa_contract IS NULL AND (fa.form_contract IS NOT NULL OR f2.form2_contract IS NOT NULL) AND cn.crm_contract IS NOT NULL AND tn.ticket_contract IS NOT NULL THEN 'crm & form & ticket'
            WHEN pn.pwa_contract IS NOT NULL AND (fa.form_contract IS NOT NULL OR f2.form2_contract IS NOT NULL) AND cn.crm_contract IS NOT NULL AND tn.ticket_contract IS NOT NULL THEN 'all'
            ELSE 'none'
        END AS negotiation_origin, 
        least(pn.pwa_neg_created, fa.form_request_created, cn.crm_date_start, tn.first_ticket_neg_created, f2.ts_request_created) AS first_ts_negotiation,
	greatest(pwa_neg_created,fa.first_execution,crm_date_start,last_ticket_neg_solved,f2.ts_request_executed) AS last_ts_negotiation,
	datediff(day, cast(first_ts_negotiation AS date), cast(last_ts_negotiation AS date)) AS negotiation_lead_time,
	CASE 
            WHEN last_ts_negotiation = pn.pwa_neg_created THEN 'pwa'
            WHEN last_ts_negotiation = fa.form_request_created THEN 'form'
            WHEN last_ts_negotiation = f2.ts_request_created THEN 'form'
            WHEN last_ts_negotiation = cn.crm_date_start THEN 'crm'
            WHEN last_ts_negotiation = tn.last_ticket_neg_created THEN 'ticket'
            ELSE NULL 
        END last_origin_negotiation,
        CASE 
            WHEN last_ts_negotiation = pn.pwa_neg_created THEN pn.type
            WHEN last_ts_negotiation = fa.form_request_created THEN NULL
            WHEN last_ts_negotiation = f2.ts_request_created THEN f2.index
            WHEN last_ts_negotiation = cn.crm_date_start THEN NULL
            WHEN last_ts_negotiation = tn.last_ticket_neg_created THEN NULL
            ELSE NULL 
        END last_type_negotiation,
        CASE 
            WHEN last_ts_negotiation = pn.pwa_neg_created THEN pn.status
            WHEN last_ts_negotiation = fa.form_request_created THEN fa.status
            WHEN last_ts_negotiation = f2.ts_request_created THEN f2.status
            WHEN last_ts_negotiation = cn.crm_date_start THEN cn.status
            WHEN last_ts_negotiation = tn.last_ticket_neg_created THEN tn.last_ticket_status
            ELSE NULL 
        END last_status_negotiation,
        CASE 
            WHEN pn.pwa_contract IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS has_pwa_negotiation,
        CASE 
            WHEN cn.crm_contract IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS has_crm_negotiation_task,
        CASE 
            WHEN tn.ticket_contract IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS has_negotiation_ticket,
        CASE 
            WHEN fa.form_contract IS NOT NULL OR f2.form2_contract IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS has_forms_contract,
        to_char(date(pn.pwa_neg_created),'MM/DD/YYYY') AS pwa_negotiation_created,
        pn.status AS pwa_negotiation_status,
        pn.type AS pwa_negotiation_type,
        cn.sk_task AS crm_negotiation_task,
        cn.crm_date_start AS crm_negotiation_task_created,
        cn.status AS crm_negotiation_task_status,
        fa.sk_request AS forms_negotiation_request,
        COALESCE(fa.form_request_created,f2.ts_request_created) AS forms_negotiation_request_created,
        COALESCE(fa.status, f2.status) AS forms_negotiation_task_status,
        CASE
            WHEN tn.first_ticket IS NULL THEN NULL 
            WHEN tn.first_ticket = tn.last_ticket THEN FALSE
            ELSE TRUE
        END AS has_more_than_one_ticket,
        tn.first_ticket AS first_negotiation_ticket,
        tn.first_ticket_neg_created AS first_negotiation_ticket_created,
        tn.first_ticket_neg_solved AS first_negotiation_ticket_solved,
        tn.first_tag_status AS first_ticket_negotiation_tag_status,
        tn.first_ticket_status AS first_ticket_negotiation_status,
        tn.last_ticket AS last_negotiation_ticket,
        tn.last_ticket_neg_created AS last_negotiation_ticket_created,
        tn.last_ticket_neg_solved AS last_negotiation_ticket_solved,
        tn.last_tag_status AS last_ticket_negotiation_tag_status,
        tn.last_ticket_status AS last_ticket_negotiation_status
    FROM anniversary_contracts nc 
    LEFT JOIN pwa_negotiation pn
        ON pn.pwa_contract = nc.sk_contract
    LEFT JOIN crm_negotiation cn 
        ON cn.crm_contract = nc.sk_contract
    LEFT JOIN consolidated_tickets tn
        ON tn.ticket_contract = nc.sk_contract
    LEFT JOIN form_automation fa 
        ON fa.form_contract = nc.sk_contract
    LEFT JOIN form_2 f2
        ON f2.form2_contract = nc.sk_contract
    ORDER BY 1 
