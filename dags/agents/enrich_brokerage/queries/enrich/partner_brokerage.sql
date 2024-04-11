WITH partner_brokerage_fee AS (
    SELECT
        id_offer_agent,
        json_output,
        get_json_object(
            json_output,
            '$.quintoandar-model-partner-brokerage-fee'
        ) AS partner_brokerage_fee,
        ts_created
    FROM
        datalake_nazare_clean.revenue_share_by_participant AS nrev
    WHERE
        DATE(nrev.ts_created) <= DATE('{year}-{month}-{day}')
    QUALIFY
        1 = ROW_NUMBER() OVER(PARTITION BY id_offer_agent ORDER BY ts_created DESC)
)
SELECT 
    no.id_external AS id_offer,
    na.id_external AS id_user_agent,
    noa.id_offer_agent,
    na.name,
    na.email,
    noa.agent_role,
    pbf.partner_brokerage_fee,
    pbf.json_output,
    no.dt_cancellation,
    no.ts_created,
    no.ts_updated,
    YEAR(no.ts_updated) AS year,
    MONTH(no.ts_updated) AS month,
    DAY(no.ts_updated) AS day
FROM 
    datalake_nazare_clean.offer AS no
LEFT JOIN 
    datalake_nazare_clean.offer_agent AS noa
        ON no.id_offer = noa.id_offer
LEFT JOIN
    datalake_nazare_clean.agent AS na
        ON na.id_agent = noa.id_agent
LEFT JOIN
    partner_brokerage_fee AS pbf
        ON pbf.id_offer_agent = noa.id_offer_agent
WHERE
    DATE(no.ts_updated) = DATE('{year}-{month}-{day}')