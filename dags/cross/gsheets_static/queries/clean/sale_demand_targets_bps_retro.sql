SELECT
    city_group,
    hub_offer,
    new_buyer_prospect,
    recovered_buyer_prospect,
    is_rede,
    TO_DATE(date, 'yyyy-MM-dd') AS dt_target
FROM
    datalake_gsheets_raw.sale_demand_targets_bps_retro
