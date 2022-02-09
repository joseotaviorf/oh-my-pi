-- Gets demand taxonomy of the offer submitted event
WITH taxonomy_demand AS (
	WITH taxonomy_min_ids AS (
		SELECT
			MIN(id) AS id
		FROM
			datalake_gsheets_clean.taxonomy_demand
		WHERE
			first_update_source = 'Inquilinos'
			AND flg_via_reschedule = 0
		GROUP BY
			LOWER(app_type),
			LOWER(utm_source),
			LOWER(utm_medium),
			LOWER(branded),
			LOWER(first_update_source),
			flg_via_reschedule
	)
	SELECT
		CAST(td.id AS BIGINT) AS id,
		td.app_type,
		td.utm_source,
		td.utm_medium,
		td.branded,
		td.category AS mkt_category,
		td.flow AS mkt_flow,
		td.completion AS mkt_completion,
		td.channel AS mkt_channel,
		td.medium AS mkt_medium,
		td.origin AS mkt_origin,
		td.source AS mkt_source,
		td.platform AS mkt_platform
	FROM
		datalake_gsheets_clean.taxonomy_demand AS td
	JOIN
		taxonomy_min_ids AS td_min
		ON td.id = td_min.id
),
offer_taxonomy AS (
	SELECT
		sor.id_offer,
		td.app_type,
		td.utm_source,
		td.utm_medium,
		sor.utm_campaign,
		td.mkt_category,
		td.mkt_flow,
		td.mkt_completion,
		td.mkt_origin,
		td.mkt_channel,
		td.mkt_medium,
		td.mkt_source,
		td.mkt_platform,
		sor.branded = 'Branded' AS flg_branded
	FROM
		datalake_amplitude_offer.sale_offer_raw_events AS sor
	LEFT JOIN
		taxonomy_demand AS td
			ON LOWER(COALESCE(td.app_type,'')) = LOWER(COALESCE(sor.app_type,''))
			AND LOWER(COALESCE(td.utm_source,'')) = LOWER(COALESCE(sor.utm_source,''))
			AND LOWER(COALESCE(td.utm_medium,'')) = LOWER(COALESCE(sor.utm_medium,''))
			AND LOWER(COALESCE(td.branded,'')) = LOWER(COALESCE(sor.branded,''))
)
SELECT 
	eso.id_offer AS sk_offer,
	eso.monday_status,
	eso.offer_status,
	eso.drop_reason,
	eso.drop_reason_responsible,
	eso.current_payment_method AS payment_method,
	eso.business_unit,
	eso.offer_platform,
	eso.offer_flow,
	eso.agent_work_contract,
	eso.team_lead_name,
	eso.consultant_name AS deal_maker_name,
	eso.agent_name,
	eso.sale_price,
	eso.registry_price,
	eso.itbi_price,
	eso.payment_entry_amount,
	ot.app_type,
	ot.utm_source,
	ot.utm_medium,
	ot.utm_campaign,
	COALESCE(ot.mkt_category,'Not Mapped') AS mkt_category,
	COALESCE(ot.mkt_flow,'Not Mapped') AS mkt_flow,
	COALESCE(ot.mkt_completion,'Not Mapped') AS mkt_completion,
	COALESCE(ot.mkt_origin,'Not Mapped') AS mkt_origin,
	COALESCE(ot.mkt_channel,'Not Mapped') AS mkt_channel,
	COALESCE(ot.mkt_medium,'Not Mapped') AS mkt_medium,
	COALESCE(ot.mkt_source,'Not Mapped') AS mkt_source,
	COALESCE(ot.mkt_platform,'Not Mapped') AS mkt_platform,
	ot.flg_branded AS is_branded,
	eso.has_used_fgts_in_payment,
	eso.has_used_negotiation_chat,
	eso.ts_offer_submitted,
	eso.ts_updated,
	NOW() AS ts_load
FROM
	datalake_offer.sale_offer AS eso
LEFT JOIN
	offer_taxonomy AS ot
		ON eso.id_offer = ot.id_offer