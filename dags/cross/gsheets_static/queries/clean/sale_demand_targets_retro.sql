SELECT
    city_group,
    hub_offer,
    visits_booked,
    visits_completed,
    offers_submitted,
    offers_accepted,
    ccv_signed,
    new_buyer_prospect,
    recovered_buyer_prospect,
    is_rede,
    TO_DATE(date, 'yyyy-MM-dd') AS dt_target
FROM
    datalake_gsheets_raw.sale_demand_targets_retro
