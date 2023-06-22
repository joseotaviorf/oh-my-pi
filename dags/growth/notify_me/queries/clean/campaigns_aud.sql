SELECT
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    name AS campaign_name,
    name_mod AS mod_campaign_name,
    external_reference,
    external_reference_mod AS mod_external_reference,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_notify_me_raw.campaigns_aud
WHERE
	DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')