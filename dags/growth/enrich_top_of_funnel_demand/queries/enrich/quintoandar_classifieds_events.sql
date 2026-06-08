WITH qac_events AS (
    SELECT
        id_amplitude,
        id_app,
        id_device,
        id_event,
        id_session,
        id_user,
        id_region,
        id_house,
        id_search,
        id_lead,
        id_source,
        id_publisher,
        search_rank,
        publisher_name,
        city,
        origin,
        uri,
        business_context,
        event_type,
        platform,
        is_qac,
        event_properties,
        user_properties,
        ts_event,
        year,
        month,
        day
    FROM
        datalake_amplitude_clean.170698_contact_broker_clicked_events
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION ALL
    SELECT
        id_amplitude,
        id_app,
        id_device,
        id_event,
        id_session,
        id_user,
        id_region,
        id_house,
        id_search,
        id_lead,
        id_source,
        id_publisher,
        search_rank,
        publisher_name,
        city,
        origin,
        uri,
        business_context,
        event_type,
        platform,
        is_qac,
        event_properties,
        user_properties,
        ts_event,
        year,
        month,
        day
    FROM
        datalake_amplitude_clean.170698_edit_account_info_clicked_events
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION ALL
    SELECT
        id_amplitude,
        id_app,
        id_device,
        id_event,
        id_session,
        id_user,
        id_region,
        id_house,
        id_search,
        id_lead,
        id_source,
        id_publisher,
        search_rank,
        publisher_name,
        city,
        origin,
        uri,
        business_context,
        event_type,
        platform,
        is_qac,
        event_properties,
        user_properties,
        ts_event,
        year,
        month,
        day
    FROM
        datalake_amplitude_clean.170698_classifieds_viewed_events
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION ALL
    SELECT
        id_amplitude,
        id_app,
        id_device,
        id_event,
        id_session,
        id_user,
        id_region,
        id_house,
        id_search,
        id_lead,
        id_source,
        id_publisher,
        search_rank,
        publisher_name,
        city,
        origin,
        uri,
        business_context,
        event_type,
        platform,
        is_qac,
        event_properties,
        user_properties,
        ts_event,
        year,
        month,
        day
    FROM
        datalake_amplitude_clean.170698_lead_intent_events
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION ALL
    SELECT
        id_amplitude,
        id_app,
        id_device,
        id_event,
        id_session,
        id_user,
        id_region,
        id_house,
        id_search,
        id_lead,
        id_source,
        id_publisher,
        search_rank,
        publisher_name,
        city,
        origin,
        uri,
        business_context,
        event_type,
        platform,
        is_qac,
        event_properties,
        user_properties,
        ts_event,
        year,
        month,
        day
    FROM
        datalake_amplitude_clean.170698_lead_intent_confirmed_events
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
qac_region AS (
    SELECT
        qac_plugin.house_id AS id_house,
        MAX(region_city.id_region) AS id_region
    FROM
        vespucio_classifieds.classifieds_house_id AS qac_plugin
    INNER JOIN
        vespucio_prod_delta.listings AS listings
            ON qac_plugin.source_id = listings.source_id
    INNER JOIN
        vespucio_prod_delta.house_compounds AS compounds
            ON listings.dejavuid = compounds.dejavuid
    INNER JOIN
        core_region.region AS region_city
            ON LOWER(region_city.city_region_name) = LOWER(compounds.address.city)
                AND region_city.state_abbreviation = compounds.address.state_code
                AND region_city.level = 'Cidade'
    GROUP BY
        qac_plugin.house_id
)
SELECT
    qac.id_amplitude,
    qac.id_app,
    qac.id_device,
    qac.id_event,
    qac.id_session,
    qac.id_user,
    COALESCE(
        CAST(qac.id_region AS STRING),
        CAST(qac_region.id_region AS STRING),
        '-1'
    ) AS id_region,
    CAST(qac.id_house AS STRING) AS id_house,
    qac.id_search,
    qac.id_lead,
    qac.id_source,
    qac.id_publisher,
    qac.search_rank,
    qac.publisher_name,
    qac.city,
    qac.origin,
    qac.uri,
    qac.business_context,
    qac.event_type,
    qac.platform,
    qac.is_qac,
    qac.event_properties,
    qac.user_properties,
    qac.ts_event,
    qac.year,
    qac.month,
    qac.day
FROM
    qac_events AS qac
LEFT JOIN
    qac_region
        ON CAST(qac.id_house AS STRING) = qac_region.id_house
