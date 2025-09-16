SELECT
    -- ids
    id,
    event_id AS id_event,
    member_id AS id_member,
    event_slot_id AS id_event_slot,

    -- non-metrics
    status,

    -- timestamps
    TO_TIMESTAMP(created_at) AS ts_created,
    TO_TIMESTAMP(updated_at) AS ts_updated,
    NOW() AS ts_load

FROM
    datalake_workable_redshift_raw.attendances