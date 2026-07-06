SELECT
    raw.id_event,
    raw.id_person,
    raw.id_user,
    raw.id_domain_user,
    raw.id_entity,
    raw.id_house,
    raw.application,
    raw.journey_step,
    raw.event_name,
    raw.event_properties,
    raw.user_properties,
    raw.ts_event,
    raw.ts_egw,
    MAKE_TIMESTAMP(
        YEAR(raw.ts_event),
        MONTH(raw.ts_event),
        DAY(raw.ts_event),
        HOUR(raw.ts_event),
        MINUTE(raw.ts_event),
        0
    ) AS ts_kafka,
    CURRENT_TIMESTAMP() AS ts_load,
    raw.year,
    raw.month,
    raw.day
FROM
    datalake_cdp_raw.transactional_events AS raw
