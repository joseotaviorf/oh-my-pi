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
all_offer_submitted_events AS (
    SELECT
        CAST(id_user AS BIGINT) AS id_user,
        CAST(id_house AS BIGINT) AS id_house,
        ep_id_firestore AS id_firestore,
        ts_event,
        up_app_type AS app_type,
        up_utm_source AS utm_source,
        up_utm_medium AS utm_medium,
        up_utm_campaign AS utm_campaign,
        up_utm_content AS utm_content,
        up_utm_term AS utm_term
    FROM
        datalake_amplitude_clean.170698_offer_submitted_events
    UNION
    SELECT
        CAST(id_user AS BIGINT) AS id_user,
        CAST(id_house AS BIGINT) AS id_house,
        ep_id_firestore AS id_firestore,
        ts_event,
        up_app_type AS app_type,
        up_utm_source AS utm_source,
        up_utm_medium AS utm_medium,
        up_utm_campaign AS utm_campaign,
        up_utm_content AS utm_content,
        up_utm_term AS utm_term
    FROM
        datalake_amplitude_clean.170135_offer_submitted_events
    UNION
    SELECT
        CAST(id_user AS BIGINT) AS id_user,
        CAST(id_house AS BIGINT) AS id_house,
        ep_id_firestore AS id_firestore,
        ts_event,
        up_app_type AS app_type,
        up_utm_source AS utm_source,
        up_utm_medium AS utm_medium,
        up_utm_campaign AS utm_campaign,
        up_utm_content AS utm_content,
        up_utm_term AS utm_term
    FROM datalake_amplitude_clean.183049_offer_submitted_events
),
offer_submitted_events AS (
    SELECT
        *,
        COALESCE(
            (
                (UPPER(utm_campaign) LIKE '%BRANDED%'
                    OR UPPER(utm_campaign) LIKE '%INSTITUCIONAL%')
                AND lower(utm_campaign) NOT LIKE '%non-branded%'
            ), FALSE
        ) AS is_branded,
        row_number() OVER (PARTITION BY id_user, id_house ORDER BY id_user, id_house, ts_event)
            AS rn_without_id_firestore,
        row_number() OVER (PARTITION BY id_firestore ORDER BY id_firestore, ts_event)
            AS rn_id_firestore,
        (id_firestore IS NOT NULL) AS has_id_firestore
    FROM
        all_offer_submitted_events
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
        pp.rejection_reason,
        CAST('Other' AS VARCHAR(255)) AS type,
        FALSE AS is_instant_offer
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
        rejection_reason,
        type,
        is_instant_offer
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
        CASE
            WHEN ose_id_firestore.id_firestore IS NOT NULL
                THEN ose_id_firestore.app_type
            ELSE ose_wo_id_firestore.app_type
        END AS app_type,
        CASE
            WHEN ose_id_firestore.id_firestore IS NOT NULL
                THEN ose_id_firestore.utm_source
            ELSE ose_wo_id_firestore.utm_source
        END AS utm_source,
        CASE
            WHEN ose_id_firestore.id_firestore IS NOT NULL
                THEN ose_id_firestore.utm_medium
            ELSE ose_wo_id_firestore.utm_medium
        END AS utm_medium,
        CASE
            WHEN ose_id_firestore.id_firestore IS NOT NULL
                THEN ose_id_firestore.utm_campaign
            ELSE ose_wo_id_firestore.utm_campaign
        END AS utm_campaign,
        CASE
            WHEN ose_id_firestore.id_firestore IS NOT NULL
                THEN ose_id_firestore.utm_content
            ELSE ose_wo_id_firestore.utm_content
        END AS utm_content,
        CASE
            WHEN ose_id_firestore.id_firestore IS NOT NULL
                THEN ose_id_firestore.utm_term
            ELSE ose_wo_id_firestore.utm_term
        END AS utm_term,
        CASE
            WHEN ose_id_firestore.id_firestore IS NOT NULL
                THEN ose_id_firestore.is_branded
            ELSE ose_wo_id_firestore.is_branded
        END AS flg_branded
    FROM
        all_offers o
    LEFT JOIN
        offer_submitted_events ose_wo_id_firestore
            ON ose_wo_id_firestore.has_id_firestore = FALSE
            AND ose_wo_id_firestore.rn_without_id_firestore = 1
            AND o.id_user = ose_wo_id_firestore.id_user
            AND o.id_property = ose_wo_id_firestore.id_house
    LEFT JOIN
        offer_submitted_events ose_id_firestore
            ON ose_id_firestore.has_id_firestore
            AND ose_id_firestore.rn_id_firestore = 1
            AND o.id_firestore = ose_id_firestore.id_firestore
),
taxonomy_demand AS (
    SELECT DISTINCT
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
        platform AS mkt_platform,
        row_number() OVER (PARTITION BY lower(app_type),
                                        lower(utm_source),
                                        lower(utm_medium),
                                        lower(branded)
                            ORDER BY lower(app_type),
                                     lower(utm_source),
                                     lower(utm_medium),
                                     lower(branded),
                                     id) AS rn
	FROM
		datalake_gsheets_clean.taxonomy_demand
	WHERE
		first_update_source = 'Inquilinos'
		AND flg_via_reschedule = 0
)
SELECT -- [ODS] This table was migrated from ODS flow and needs a future refactoring to remove castings and renamings
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
    CASE WHEN td.mkt_flow IS NULL THEN 'Not Mapped' ELSE td.mkt_category END AS mkt_category,
	CASE WHEN td.mkt_flow IS NULL THEN 'Not Mapped' ELSE td.mkt_flow END AS mkt_flow,
	CASE WHEN td.mkt_flow IS NULL THEN 'Not Mapped' ELSE td.mkt_completion END AS mkt_completion,
	CASE WHEN td.mkt_flow IS NULL THEN 'Not Mapped' ELSE td.mkt_origin END AS mkt_origin,
	CASE WHEN td.mkt_flow IS NULL THEN 'Not Mapped' ELSE td.mkt_channel END AS mkt_channel,
	CASE WHEN td.mkt_flow IS NULL THEN 'Not Mapped' ELSE td.mkt_medium END AS mkt_medium,
	CASE WHEN td.mkt_flow IS NULL THEN 'Not Mapped' ELSE td.mkt_source END AS mkt_source,
	CASE WHEN td.mkt_flow IS NULL THEN 'Not Mapped' ELSE td.mkt_platform END AS mkt_platform,
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
    o.last_updated_date,
    o.expiration_date,
    o.dt_analysis,
    o.dt_first_sent,
    o.dt_created,
    o.dt_updated,
    o.dt_timestamp
FROM
    offer_enriched o
LEFT JOIN taxonomy_demand td
    ON td.rn = 1
    AND lower(coalesce(td.app_type,'')) = lower(coalesce(o.app_type,''))
	AND lower(coalesce(td.utm_source,'')) = lower(coalesce(o.utm_source,''))
	AND lower(coalesce(td.utm_medium,'')) = lower(coalesce(o.utm_medium,''))
	AND coalesce(td.flg_branded, FALSE) = COALESCE(o.flg_branded, FALSE)