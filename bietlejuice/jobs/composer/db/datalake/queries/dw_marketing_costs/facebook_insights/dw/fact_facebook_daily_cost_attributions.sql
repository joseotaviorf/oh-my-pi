SELECT 
    sk_ad,
    id_ad,
    id_account,
    id_campaign,
    id_adset,
    REPLACE(CONCAT_WS(',',COLLECT_LIST(TO_JSON(map(impression_device,impressions)))), '}},{{', ',') AS impressions,
    REPLACE(CONCAT_WS(',',COLLECT_LIST(TO_JSON(map(impression_device,reach)))), '}},{{', ',') AS reach,
    REPLACE(CONCAT_WS(',',COLLECT_LIST(TO_JSON(map(impression_device,inline_link_clicks)))), '}},{{', ',') AS inline_link_clicks,
    REPLACE(CONCAT_WS(',',COLLECT_LIST(TO_JSON(map(impression_device,spend)))), '}},{{', ',') AS spend,
    fi.year,
    fi.month,
    fi.day,
    dt_start,
    dt_stop
FROM
    datalake_marketing_costs.facebook_insights AS fi
JOIN
    dw_marketing_costs_staging.dim_facebook_ad AS stg_dim
        ON fi.ad_name = stg_dim.ad_name
        AND fi.adset_name = stg_dim.adset_name
        AND fi.campaign_name = stg_dim.campaign_name
        AND fi.acc = stg_dim.account_name
WHERE 
    fi.year = {year}
    AND fi.month = {month}
    AND fi.day = {day}
GROUP BY
    1,2,3,4,5,10,11,12,13,14
