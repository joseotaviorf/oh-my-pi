WITH customer_conversions AS (
    SELECT
         cc.id_customer,
         cc.id_dispatch,
         cc.id_dispatch_lot,
         cc.id_answer,
         d.status,
         d.id_campaign,
         a.nps_answer,
         a.nps_comment,
         ROUND(a.seconds_spent_answering/60.0,2) AS minutes_spent_answering,
         d.ts_created,
         a.ts_answer_sent
    FROM datalake_tracksale.customer_conversions cc
    INNER JOIN datalake_tracksale.dispatch d
        ON cc.id_dispatch_lot = d.id
    LEFT JOIN datalake_tracksale.answer a 
         ON cc.id_answer = a.id
),
answer_keys AS (
     SELECT
          id_answer,
          MAX(CASE WHEN tag_name = 'User Id' THEN CAST(tag_value AS BIGINT) 
            END) AS id_user,
          MAX(CASE WHEN tag_name = 'CPF' THEN tag_value 
            END) AS cpf
     FROM datalake_tracksale.answer_tags
     WHERE tag_name IN ('User Id','CPF')
     GROUP BY 1
),
ebdb_user AS (
     SELECT 
          ak.id_answer,
          ak.id_user
     FROM answer_keys ak
     INNER JOIN datalake_ebdb_clean.user u
          ON ak.id_user = u.id
     GROUP BY 1,2
),
ebdb_cpf AS (
     SELECT 
          ak.id_answer,
          ak.cpf
     FROM answer_keys ak
     INNER JOIN datalake_ebdb_customer_contact_identification.customer_contact_identification cci
        ON ak.cpf = cci.cpf
     GROUP BY 1,2
),
customer_keys AS (
     SELECT
          cc.id_customer,
          MAX(COALESCE(eu.id_user,cci_e.id_user, cci_p.id_user)) AS id_user,
          MAX(COALESCE(ec.cpf,cci_e.cpf,cci_p.cpf)) AS cpf
     FROM datalake_tracksale.customer_conversions cc
     LEFT JOIN ebdb_user eu
        ON eu.id_answer = cc.id_answer
     LEFT JOIN ebdb_cpf ec
        ON ec.id_answer = cc.id_answer
     LEFT JOIN datalake_ebdb_customer_contact_identification.customer_contact_identification cci_p
        ON cci_p.customer_contact = cc.customer_phone
        AND cci_p.channel = 'phone'
     LEFT JOIN datalake_ebdb_customer_contact_identification.customer_contact_identification cci_e
        ON cci_e.customer_contact = cc.customer_email
        AND cci_e.channel = 'email'    
     GROUP BY 1
)
SELECT
     cc.id_dispatch AS sk_nps_dispatch,
     cc.id_dispatch_lot AS sk_nps_dispatch_lot,
     cc.id_campaign AS sk_nps_campaign,
     cc.id_customer AS sk_nps_customer,
     COALESCE(ck.id_user,-1) AS sk_user,
     COALESCE(ck.cpf, -1) AS sk_personal_document,
     COALESCE(cc.id_answer, -1) AS sk_nps_answer,
     COALESCE(ad.id_house_listing, -1) AS sk_house_listing,
     COALESCE(ad.id_booking, -1) AS sk_booking,
     COALESCE(ad.id_tta, -1) AS sk_tta,
     COALESCE(ad.id_offer_context, -1) AS sk_offer,
     COALESCE(ad.id_contract, -1) AS sk_contract,
     COALESCE(CAST(date_format(cc.ts_created, 'yyyyMMdd') AS BIGINT), -1) AS sk_sent_date,
     COALESCE(CAST(date_format(cc.ts_answer_sent, 'yyyyMMdd') AS BIGINT), -1) AS sk_answered_date,
     COALESCE(cc.nps_answer, -1) AS score,
     COALESCE(minutes_spent_answering, -1) AS minutes_response_time,
     cc.status <> 'Finalizado' AS is_pending_survey,
     cc.id_answer IS NOT NULL AS is_answered,
     cc.nps_comment IS NOT NULL AS has_comment,
     current_timestamp as ts_load
FROM customer_conversions cc
LEFT JOIN customer_keys ck 
     ON ck.id_customer = cc.id_customer
LEFT JOIN datalake_nps_answer_drivers.answer_drivers ad
     ON cc.id_answer = ad.id_answer
