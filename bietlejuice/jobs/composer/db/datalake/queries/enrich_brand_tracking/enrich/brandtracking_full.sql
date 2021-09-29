WITH 
full_tmp AS (
    SELECT
        t1.id_respondent as id_respondent,
        t1.id_question as id_question,
        t2.full_question as full_question,
        t1.answer as answer,
        t1.wave as wave,
        t1.year as year,
        t1.quarter as quarter
    FROM
        datalake_brand_tracking_clean.brandtracking_unpivoted t1
    LEFT JOIN
        datalake_gsheets_clean.ipsos_brandtracking_questions t2
    ON
        t1.id_question = SF_ALPHANUMERIC_SNAKE_CASE(t2.id_question)
    WHERE
        year = {year_previous_quarter}
        AND quarter = {previous_quarter}
),
flags AS (
    SELECT
        id_respondent,
        full_question,
        SUM(
            CASE
                WHEN answer like '%Conhecimento%'
                    THEN 1
                    ELSE 0
            END
        ) as awareness,
        SUM(
            CASE
                WHEN answer like '%Consideração%'
                    THEN 1
                    ELSE 0
            END
        ) as consideration,
        SUM(
            CASE 
                WHEN answer like '%Uso%'
                    THEN 1
                    ELSE 0
            END
        ) as usage,
        SUM(
            CASE 
                WHEN answer like '%Preferência%'
                THEN 1
                ELSE 0
            END
        ) as preference,
        year,
        quarter
    FROM
        full_tmp
    WHERE
        id_question like 'summary%'
    GROUP BY
        id_respondent,
        full_question,
        year,
        quarter
),
pivot_flags AS (
    SELECT
        *
    FROM
        flags
    PIVOT (
        regexp_replace(regexp_replace(sum(awareness),'^[1-9][0-9]*', TRUE), '0', FALSE) as awareness,
        regexp_replace(regexp_replace(sum(consideration),'^[1-9][0-9]*', TRUE), '0', FALSE) as consideration,
        regexp_replace(regexp_replace(sum(usage),'^[1-9][0-9]*', TRUE), '0', FALSE) as usage,
        regexp_replace(regexp_replace(sum(preference),'^[1-9][0-9]*', TRUE), '0', FALSE) as preference
        for full_question in (
            'QuintoAndar :' as quinto_andar,
            'Zap Imóveis :' as zap,
            'Imóvel Web :' as imovel_web,
            'Viva Real :' as viva_real,
            'OLX :' as olx,
            'Loft :' as loft,
            'Housi :' as housi
        )
    )
)
SELECT
    t1.id_respondent,
    t1.id_question,
    t1.full_question,
    t1.answer,
    t1.wave,
    t2.quinto_andar_awareness,
    t2.quinto_andar_consideration,
    t2.quinto_andar_usage,
    t2.quinto_andar_preference,
    t2.zap_awareness,
    t2.zap_consideration,
    t2.zap_usage,
    t2.zap_preference,
    t2.imovel_web_awareness,
    t2.imovel_web_consideration,
    t2.imovel_web_usage,
    t2.imovel_web_preference,
    t2.viva_real_awareness,
    t2.viva_real_consideration,
    t2.viva_real_usage,
    t2.viva_real_preference,
    t2.olx_awareness,
    t2.olx_consideration,
    t2.olx_usage,
    t2.olx_preference,
    t2.loft_awareness,
    t2.loft_consideration,
    t2.loft_usage,
    t2.loft_preference,
    t2.housi_awareness,
    t2.housi_consideration,
    t2.housi_usage,
    t2.housi_preference,
    t1.year,
    t1.quarter
FROM
    full_tmp t1
LEFT JOIN
    pivot_flags t2
ON
    t1.id_respondent = t2.id_respondent AND
    t1.year = t2.year AND
    t1.quarter = t2.quarter