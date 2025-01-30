SELECT
    id,
    house_id AS id_house,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    house_id_mod AS mod_id_house,
    started_at_mod AS mod_ts_started,
    submitted_at_mod AS mod_ts_submitted,
    started_at AS ts_started,
    submitted_at AS ts_submitted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_test_raw.seller_documentation_aud