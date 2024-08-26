SELECT
    NULLIF(flag_imob, '') AS flag_partner,
    NULLIF(tier, '') AS tier,
    NULLIF(kind, '') AS kind,
    CAST(NULLIF(brokerage, '') AS FLOAT) AS brokerage,
    CAST(NULLIF(adm_5a, '') AS FLOAT) AS adm_5a,
    CAST(NULLIF(additional_comission_supply, '') AS FLOAT) AS additional_comission_supply,
    CAST(NULLIF(comission_supply, '') AS FLOAT) AS comission_supply,
    CAST(NULLIF(additional_comission_demand, '') AS FLOAT) AS additional_comission_demand,
    CAST(NULLIF(comission_demand, '') AS FLOAT) AS comission_demand,
    CAST(NULLIF(tier_start_date, '') AS DATE) AS dt_tier_started,
    CAST(NULLIF(tier_end_date, '') AS DATE) AS dt_tier_ended
FROM
    datalake_gsheets_raw.rede_5a_revenue_share_conditions
