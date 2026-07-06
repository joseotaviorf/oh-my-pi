SELECT
    id,
    external_id AS id_external,
    address_data_id AS id_address_data,
    land_tenure,
    house_registration_status,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    has_seller_debt_payments,
    land_tenure_mod AS mod_land_tenure,
    house_registration_status_mod AS mod_house_registration_status,
    has_seller_debt_payments_mod AS mod_has_seller_debt_payments,
    external_id_mod AS mod_id_external,
    address_data_id_mod AS mod_id_address_data,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.house_aud
