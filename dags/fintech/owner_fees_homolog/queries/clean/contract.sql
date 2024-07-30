SELECT
    id,
    house_id AS id_house,
    external_id AS id_external,
    admin_fee_option_id AS id_admin_fee_option,
    real_state_agent_share,
    rent,
    validity_date AS dt_validity,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_owner_fees_homolog_raw.contract
WHERE
    MAKE_DATE(year,month,day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
