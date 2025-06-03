SELECT
    country_language,
    version,
    status,
    content,
    created_by_user,
    updated_by_user,
    approved_by_user,
    created_at AS ts_created,
    updated_at AS ts_updated,
    approved_at AS ts_approved
FROM
    datalake_journey_flow_test_raw.t_journey_content
