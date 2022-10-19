WITH
taxonomy AS (
    SELECT
	    id,
		app_type,
		utm_source,
		utm_medium,
		branded,
		mkt_channel,
		mkt_medium,
		mkt_origin,
		mkt_source
	FROM
	    datalake_gsheets_clean.taxonomy_portal_casa_mineira
),
events AS (
    SELECT
        id_device,
        COALESCE(
            CAST(GET_JSON_OBJECT(event_properties, '$.house_id') AS STRING),
            SPLIT(TRANSLATE(CAST(GET_JSON_OBJECT(event_properties, '$.top5_house_id') AS string), '[]', ''), ',')[0]
        ) AS id_house,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_source') AS STRING) AS utm_source,
        CAST(GET_JSON_OBJECT(user_properties, '$.utm_medium') AS STRING) AS utm_medium,
        CASE
            WHEN
                UPPER(CAST(GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS STRING)) LIKE '%BRANDED%'
                AND UPPER(CAST(GET_JSON_OBJECT(user_properties, '$.utm_campaign') AS STRING)) NOT LIKE '%NON-BRANDED%'
                    THEN 'Branded'
                    ELSE 'Outro'
        END AS branded,
        CAST(GET_JSON_OBJECT(user_properties , '$.platform') AS STRING) AS app_type,
        DATE(ts_event) AS dt_event
    FROM
        datalake_casa_mineira_amplitude_clean.329001_portal
    WHERE
        event_type IN ('search_page_viewed', 'listing_page_viewed')
        AND DATE(ts_event) = DATE('{year}-{month}-{day}')
)
SELECT
    DISTINCT
        evt.id_device,
        ct.city_name AS city_listing,
        uf.uf_initials AS uf_initials,
        n.neighborhood AS neighborhood,
        COALESCE(t.mkt_origin, 'Other') AS mkt_origin,
        COALESCE(t.mkt_channel, 'Not Mapped') AS mkt_channel,
        COALESCE(t.mkt_medium, 'Not Mapped') AS mkt_medium,
        COALESCE(t.mkt_source, 'Not Mapped') AS mkt_source,
        CASE
            WHEN h.id_real_estate_agency = '1'
                THEN 'imobiliaria'
                ELSE 'portal'
        END AS mkt_business,
        evt.dt_event,
        year(dt_event) as year,
        month(dt_event) as month,
        day(dt_event) as day
FROM
    events AS evt
LEFT JOIN
    datalake_casa_mineira_portal_clean.house AS h
        ON evt.id_house = h.id
LEFT JOIN
    datalake_casa_mineira_portal_clean.neighborhood AS n
        ON n.id = h.id_neighborhood
LEFT JOIN
    datalake_casa_mineira_portal_clean.city AS ct
        ON n.id_city = ct.id
LEFT JOIN
    datalake_casa_mineira_portal_clean.uf AS uf
        ON ct.id_uf = uf.id
LEFT JOIN
    taxonomy AS t
        ON LOWER(COALESCE(t.app_type, '')) = LOWER(COALESCE(evt.app_type, ''))
        AND LOWER(COALESCE(t.utm_source, '')) = LOWER(COALESCE(evt.utm_source, ''))
        AND LOWER(COALESCE(t.utm_medium, '')) = LOWER(COALESCE(evt.utm_medium, ''))
        AND LOWER(COALESCE(t.branded, '')) = LOWER(COALESCE(evt.branded, ''))