WITH pre_proposal_aud AS (
    SELECT DISTINCT
		pp.id,
		MAX(pp.ts_updated) OVER w AS last_updated_date,
		MAX(pp_aud.ts_expired) OVER w AS expiration_date,
		MAX(CASE
		        WHEN is_tenant_edition AND mod_rent
		            THEN pp_aud.rent
		     END) OVER w
		AS last_rent_value_tenant,
		COALESCE(
			MIN(CASE
			        WHEN is_landlord_edition AND mod_rent
			            THEN pp_aud.rent
			    END) OVER w,
			MIN(pp_aud.original_rent) OVER w
		) AS last_rent_value_landlord,
		MAX(CASE
		        WHEN is_tenant_edition AND mod_rent
		            THEN pp_aud.rent
            END) OVER w
		+	MAX(pp_aud.original_condo) OVER w
	    AS total_rent_value
	FROM
		datalake_ebdb_proposal.pre_proposal pp
	JOIN
		datalake_ebdb_proposal.pre_proposal_aud pp_aud
		ON pp.id = pp_aud.id_pre_proposal
	WINDOW
		w AS (PARTITION BY pp.id)
),
enrich_attribution AS (
    SELECT
        aos.id_user,
        aos.id_house,
        aos.id_firestore,
        aos.ts_event,
        /*
        Attribution Rules, enriched with the new attribution and the old one.
        The new one starts on H2/2021.
        Using CASE WHEN instead of COALESCE to don't create strange combinations.
        */
        IF(acc.id_firestore IS NOT NULL, acc.final_attribution_app_type, aos.app_type) AS app_type,
        IF(acc.id_firestore IS NOT NULL, acc.final_attribution_source, aos.utm_source) AS utm_source,
        IF(acc.id_firestore IS NOT NULL, acc.final_attribution_medium, aos.utm_medium) AS utm_medium,
        IF(acc.id_firestore IS NOT NULL, acc.final_attribution_campaign, aos.utm_campaign) AS utm_campaign,
        IF(acc.id_firestore IS NOT NULL, acc.final_attribution_content, aos.utm_content) AS utm_content,
        IF(acc.id_firestore IS NOT NULL, acc.final_attribution_term, aos.utm_term) AS utm_term,
        IF(acc.id_firestore IS NOT NULL, acc.final_attribution_origin, 'old_attribution') AS final_attribution_origin,
        IF(acc.id_firestore IS NOT NULL, acc.final_attribution_branded = 'Branded',
            COALESCE(((UPPER(utm_campaign) LIKE '%BRANDED%'OR UPPER(utm_campaign) LIKE '%INSTITUCIONAL%') AND UPPER(utm_campaign) NOT LIKE '%NON-BRANDED%'), FALSE)) AS flg_branded
    FROM
        datalake_amplitude_offer.offer_submitted_events AS aos
    LEFT JOIN
        datalake_tracked_events.attribution_cross_channel AS acc
            ON aos.id_firestore = acc.id_firestore
            AND acc.event_name = 'offer_submitted'
),
offer_submitted_events AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id_user, id_house ORDER BY id_user, id_house, ts_event)
            AS rn_without_id_firestore,
        ROW_NUMBER() OVER (PARTITION BY id_firestore ORDER BY id_firestore, ts_event)
            AS rn_id_firestore,
        (id_firestore IS NOT NULL) AS has_id_firestore
    FROM
        enrich_attribution
),
old_pre_proposal AS (
    SELECT
        CAST(pp.id_offer_context AS INT) AS sk_offer,
        CAST(pp.id AS INT) AS id_offer,
        CAST(NULL AS INT) AS id_godfather,
        CAST(NULL AS VARCHAR(255)) AS id_firestore,
        country_code,
        CAST(pp.rent AS INT) AS last_offered_rent,
        CAST(pp.original_rent AS INT) AS original_rent,
        CAST(pp.original_condo AS INT) AS original_condo,
        CAST(pp.ts_last_analysis AS TIMESTAMP) AS dt_analysis,
        pp.edition AS editing,
        pp.status,
        CAST(pp.id_user AS INT) AS id_user,
        CAST(pp.id_house AS INT) AS id_property,
        CAST(pp.ts_created AS TIMESTAMP) AS dt_created,
        CAST(pp.ts_updated AS TIMESTAMP) AS dt_updated,
        CAST(now() AS TIMESTAMP) AS dt_timestamp,
        has_edition_update AS offer_submitted,
        CAST(pp.ts_first_sent AS TIMESTAMP) AS dt_first_sent,
        CAST(pp_aud.last_updated_date AS TIMESTAMP) AS last_updated_date,
        CAST(pp_aud.expiration_date AS TIMESTAMP) AS expiration_date,
        CAST(NULL AS DECIMAL(18,4)) AS first_rent_offered_by_tenant,
        CAST(NULL AS DECIMAL(18,4)) AS first_rent_offered_by_owner,
        last_rent_value_tenant AS last_rent_offered_by_tenant,
        last_rent_value_landlord AS last_rent_offered_by_owner,
        NULL AS number_of_tenants,
        NULL AS number_of_kids,
        pp.rejection_reason,
        NULL AS rental_reason,
        NULL AS rental_urgency,
        NULL AS tenant_description,
        NULL AS tenant_pets_info,
        NULL AS tenant_type,
        CAST('Other' AS VARCHAR(255)) AS type,
        NULL AS has_pets,
        FALSE AS is_instant_offer,
        NULL AS ts_email_sent_to_owner
    FROM
      datalake_ebdb_proposal.pre_proposal pp
    LEFT JOIN pre_proposal_aud pp_aud
        ON pp.id = pp_aud.id
),
new_offer AS (
    SELECT
        CAST(id_offer_context AS INT) AS sk_offer,
        CAST(id AS INT) AS id_offer,
        CAST(id_godfather AS INT) AS id_godfather,
        CAST(id_firestore AS VARCHAR(255)) AS id_firestore,
        country_code,
        CAST(last_offered_rent AS INT) AS last_offered_rent,
        CAST(original_rent AS INT) AS original_rent,
        CAST(original_condo AS INT) AS original_condo,
        CAST(ts_analyzed AS TIMESTAMP) AS dt_analysis,
        turn AS editing,
        status,
        CAST(id_client AS INT) AS id_user,
        CAST(id_house AS INT) AS id_property,
        CAST(ts_created AS TIMESTAMP) AS dt_created,
        CAST(ts_updated AS TIMESTAMP) AS dt_updated,
        CAST(now() AS TIMESTAMP) AS dt_timestamp,
        (ts_last_sent IS NOT NULL) AS offer_submitted,
        CAST(ts_first_sent AS TIMESTAMP) AS dt_first_sent,
        CAST(ts_updated AS TIMESTAMP) AS last_updated_date,
        CAST(ts_expired AS TIMESTAMP) AS expiration_date,
        CAST(first_rent_offered_by_tenant AS DECIMAL(18,4)) AS first_rent_offered_by_tenant,
        CAST(first_rent_offered_by_owner AS DECIMAL(18,4)) AS first_rent_offered_by_owner,
        CAST(last_rent_offered_by_tenant AS DECIMAL(18,4)) AS last_rent_offered_by_tenant,
        CAST(last_rent_offered_by_owner AS DECIMAL(18,4)) AS last_rent_offered_by_owner,
        number_of_tenants,
        number_of_kids,
        rejection_reason,
        rental_reason,
        rental_urgency,
        tenant_description,
        tenant_pets_info,
        tenant_type,
        type,
        has_pets,
        is_instant_offer,
        ts_email_sent_to_owner
    FROM
        datalake_offer.offer
),
all_offers AS (
    SELECT
        *
    FROM
        new_offer
    UNION
    SELECT
        *
    FROM
        old_pre_proposal
),
offer_enriched AS (
    SELECT
        o.*,
        IF(ose_id_firestore.id_firestore IS NOT NULL, ose_id_firestore.app_type, ose_wo_id_firestore.app_type) AS app_type,
        IF(ose_id_firestore.id_firestore IS NOT NULL, ose_id_firestore.utm_source, ose_wo_id_firestore.utm_source) AS utm_source,
        IF(ose_id_firestore.id_firestore IS NOT NULL, ose_id_firestore.utm_medium, ose_wo_id_firestore.utm_medium) AS utm_medium,
        IF(ose_id_firestore.id_firestore IS NOT NULL, ose_id_firestore.utm_campaign, ose_wo_id_firestore.utm_campaign) AS utm_campaign,
        IF(ose_id_firestore.id_firestore IS NOT NULL, ose_id_firestore.utm_content, ose_wo_id_firestore.utm_content) AS utm_content,
        IF(ose_id_firestore.id_firestore IS NOT NULL, ose_id_firestore.utm_term, ose_wo_id_firestore.utm_term) AS utm_term,
        IF(ose_id_firestore.id_firestore IS NOT NULL, ose_id_firestore.flg_branded, ose_wo_id_firestore.flg_branded) AS flg_branded,
        IF(ose_id_firestore.final_attribution_origin IS NOT NULL, ose_id_firestore.final_attribution_origin, ose_wo_id_firestore.final_attribution_origin) AS final_attribution_origin
    FROM
        all_offers AS o
    LEFT JOIN
        offer_submitted_events AS ose_wo_id_firestore
            ON ose_wo_id_firestore.has_id_firestore = FALSE
            AND ose_wo_id_firestore.rn_without_id_firestore = 1
            AND o.id_user = ose_wo_id_firestore.id_user
            AND o.id_property = ose_wo_id_firestore.id_house
    LEFT JOIN
        offer_submitted_events AS ose_id_firestore
            ON ose_id_firestore.has_id_firestore
            AND ose_id_firestore.rn_id_firestore = 1
            AND o.id_firestore = ose_id_firestore.id_firestore
),
taxonomy_demand AS (
    /*
        As flg_branded is used to define a relationship with offer, it is necessary to make sure that this CTE will be deduplicated 
        considering this column to. In this way offer: taxonomy will be 1:1
    */
    SELECT
        id,
		app_type,
        utm_source,
        utm_medium,
        branded = 'Branded' AS flg_branded,
        category AS mkt_category,
        flow AS mkt_flow,
        completion AS mkt_completion,
        channel AS mkt_channel,
        medium AS mkt_medium,
        origin AS mkt_origin,
        source AS mkt_source,
        platform AS mkt_platform
	FROM
		datalake_gsheets_clean.taxonomy_demand
	WHERE
		first_update_source = 'Inquilinos'
		AND flg_via_reschedule = 0
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY LOWER(app_type), LOWER(utm_source), LOWER(utm_medium), branded = 'Branded'
            ORDER BY LOWER(app_type), LOWER(utm_source), LOWER(utm_medium), branded = 'Branded', id) = 1
)
SELECT
    o.sk_offer,
    o.id_offer,
    o.id_godfather,
    o.id_firestore,
    o.id_user,
    o.id_property,
    o.country_code,
    o.editing,
    o.status,
    o.rejection_reason,
    o.type,
    o.app_type,
    o.utm_source,
    o.utm_medium,
    o.utm_campaign,
    o.utm_content,
    o.utm_term,
    o.final_attribution_origin,
    IF(td.mkt_flow IS NULL, 'Not Mapped', td.mkt_category) AS mkt_category,
    IF(td.mkt_flow IS NULL, 'Not Mapped', td.mkt_flow) AS mkt_flow,
    IF(td.mkt_flow IS NULL, 'Not Mapped', td.mkt_completion) AS mkt_completion,
    IF(td.mkt_flow IS NULL, 'Not Mapped', td.mkt_origin) AS mkt_origin,
    IF(td.mkt_flow IS NULL, 'Not Mapped', td.mkt_channel) AS mkt_channel,
    IF(td.mkt_flow IS NULL, 'Not Mapped', td.mkt_medium) AS mkt_medium,
    IF(td.mkt_flow IS NULL, 'Not Mapped', td.mkt_source) AS mkt_source,
    IF(td.mkt_flow IS NULL, 'Not Mapped', td.mkt_platform) AS mkt_platform,
    o.last_offered_rent,
    o.original_rent,
    o.original_condo,
    o.is_instant_offer,
    o.flg_branded,
    o.offer_submitted,
    o.first_rent_offered_by_tenant,
    o.first_rent_offered_by_owner,
    o.last_rent_offered_by_tenant,
    o.last_rent_offered_by_owner,
    CAST(o.number_of_tenants AS SMALLINT) AS number_of_tenants,
    CAST(o.number_of_kids AS SMALLINT) AS number_of_kids,
    o.rental_reason,
    o.rental_urgency,
    o.tenant_description,
    o.tenant_pets_info,
    o.tenant_type,
    CAST(o.has_pets AS BOOLEAN) AS has_pets,
    o.ts_email_sent_to_owner,
    o.last_updated_date,
    o.expiration_date,
    o.dt_analysis,
    o.dt_first_sent,
    o.dt_created,
    o.dt_updated,
    o.dt_timestamp
FROM
    offer_enriched AS o
LEFT JOIN
    taxonomy_demand AS td
        ON LOWER(COALESCE(td.app_type,'')) = LOWER(COALESCE(o.app_type,''))
        AND LOWER(COALESCE(td.utm_source,'')) = LOWER(COALESCE(o.utm_source,''))
        AND LOWER(COALESCE(td.utm_medium,'')) = LOWER(COALESCE(o.utm_medium,''))
        AND COALESCE(td.flg_branded, FALSE) = COALESCE(o.flg_branded, FALSE)