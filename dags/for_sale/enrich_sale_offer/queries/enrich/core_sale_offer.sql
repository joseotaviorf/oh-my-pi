WITH 
  firestore_sale_offer_clean AS (
  SELECT     
        soa.id,
        CAST(GET_JSON_OBJECT(soa.updated_message, '$.submitterId') AS BIGINT) AS id_buyer,
        CAST(GET_JSON_OBJECT(soa.updated_message, '$.house.id') AS BIGINT) AS id_house,
        CAST(GET_JSON_OBJECT(soa.updated_message, '$.house.ownerId') AS BIGINT) AS id_owner,
        CAST(GET_JSON_OBJECT(soa.updated_message, '$.changedBy') AS BIGINT) AS id_monday_user_last_revision,
        CAST(GET_JSON_OBJECT(soa.updated_message, '$.brokerageFee') AS FLOAT) AS brokerage_fee,
        CAST(GET_JSON_OBJECT(soa.updated_message, '$.deedPrice') AS BIGINT) AS deed_price,
        CAST(GET_JSON_OBJECT(soa.updated_message, '$.earnestValue') AS BIGINT) AS earnest_value,
        CAST(GET_JSON_OBJECT(soa.updated_message, '$.fgtsValue') AS BIGINT) AS fgts_value,
        CAST(GET_JSON_OBJECT(soa.updated_message, '$.financingValue') AS BIGINT) AS financing_value,
        CAST(GET_JSON_OBJECT(soa.updated_message, '$.itbiPrice') AS BIGINT) AS itbi_price,
        CAST(GET_JSON_OBJECT(soa.updated_message, '$.offerPrice') AS BIGINT) AS first_price_offered_by_buyer,
        CAST(GET_JSON_OBJECT(soa.updated_message, '$.salePrice') AS BIGINT) AS sale_price,
        CAST(GET_JSON_OBJECT(soa.updated_message, '$.registryPrice') AS BIGINT) AS registry_price,
        GET_JSON_OBJECT(soa.updated_message, '$.paymentMethod') AS planned_payment_method,
        CAST(GET_JSON_OBJECT(soa.updated_message, '$.updatedOfferPrice') AS BIGINT) AS last_price_offered_by_buyer,
        GET_JSON_OBJECT(soa.updated_message, '$.paymentOptions.paymentMethod') AS current_payment_method,
        GET_JSON_OBJECT(soa.updated_message, '$.paymentOptions.creditStatus') AS credit_status,
        CAST(GET_JSON_OBJECT(soa.updated_message, '$.paymentOptions.entryAmount') AS BIGINT) AS payment_entry_amount,
        GET_JSON_OBJECT(soa.updated_message, '$.paymentOptions.paymentType') AS payment_type,
        GET_JSON_OBJECT(soa.updated_message, '$.status') AS status,
        GET_JSON_OBJECT(soa.updated_message, '$.statusClosing') AS status_closing,
        GET_JSON_OBJECT(soa.updated_message, '$.statusReason') AS status_reason,
        GET_JSON_OBJECT(soa.updated_message, '$.turn') AS turn,
        CAST(GET_JSON_OBJECT(soa.updated_message, '$.createNegotiationChat') AS BOOLEAN) AS has_used_negotiation_chat,
        COALESCE(CAST(GET_JSON_OBJECT(soa.updated_message, '$.paymentOptions.fgts') AS BOOLEAN), FALSE) AS has_used_fgts_in_payment,
        DATE(GET_JSON_OBJECT(soa.updated_message, '$.tenantLeaveDate')) AS dt_tenant_left,
        CAST(CAST(GET_JSON_OBJECT(soa.updated_message, '$.createdAt._seconds') AS BIGINT) AS TIMESTAMP) AS ts_created,   
        soa.ts_updated,
        CAST(GET_JSON_OBJECT(soa.updated_message, '$.text1.value') AS BIGINT) AS id_agent_firestore
  FROM  datalake_firestore_clean.sale_offer AS soa
  QUALIFY 
        ROW_NUMBER() OVER (PARTITION BY soa.id ORDER BY soa.ts_updated DESC) = 1
)
, firestore_sale_offer AS (
  SELECT
      soa.id,
      concat(soa.id_buyer,'_',soa.id_house) AS id_sale_flow,
      soa.id_buyer,
      soa.id_house,
      soa.id_owner,
      soa.id_monday_user_last_revision,
      soa.brokerage_fee,
      soa.deed_price,
      soa.earnest_value,
      soa.fgts_value,
      soa.financing_value,
      soa.itbi_price,
      soa.first_price_offered_by_buyer,
      soa.sale_price,
      soa.registry_price,
      soa.planned_payment_method,
      COALESCE(soa.last_price_offered_by_buyer,soa.first_price_offered_by_buyer) AS last_price_offered_by_buyer,
      soa.current_payment_method,
      soa.credit_status,
      soa.payment_entry_amount,
      soa.payment_type,
      soa.status,
      soa.status_closing,
      soa.status_reason,
      soa.turn,
      (soa.sale_price - soa.first_price_offered_by_buyer)/NULLIF(soa.sale_price,0) AS first_discount_proposed,
      (soa.sale_price - soa.last_price_offered_by_buyer)/NULLIF(soa.sale_price,0) AS last_discount_proposed,
      COALESCE(soa.has_used_negotiation_chat,FALSE) AS has_used_negotiation_chat,
      COALESCE(soa.has_used_fgts_in_payment,FALSE) AS has_used_fgts_in_payment,
      soa.dt_tenant_left,
      soa.ts_created,
      soa.ts_updated,
      NOW() AS ts_load,
      soa.id_agent_firestore AS id_agent
  FROM
      firestore_sale_offer_clean AS soa
  WHERE 
      soa.status <> 'DRAFT'
)
, sale_offer AS (
        WITH
        latest_sales_flow AS (
            SELECT
                sf.*,
                buyer.id_external AS buyer_id_external,
                seller.id_external AS seller_id_external
            FROM
                datalake_sales_flow_clean.sales_flow sf
            LEFT JOIN datalake_sales_flow_clean.users AS seller
            ON sf.id_seller = seller.id
            LEFT JOIN datalake_sales_flow_clean.users AS buyer
            ON sf.id_buyer = buyer.id
            QUALIFY
                ROW_NUMBER() OVER (PARTITION BY sf.id ORDER BY sf.ts_updated DESC) = 1
        ),
        latest_offer AS (
            SELECT *
            FROM datalake_sales_flow_clean.offer
            QUALIFY
                ROW_NUMBER() OVER (PARTITION BY id_firestore ORDER BY ts_updated DESC) = 1
        ),
        first_offer_aud AS (
            SELECT *
            FROM datalake_sales_flow_clean.offer_aud
            WHERE offer_price IS NOT NULL
            QUALIFY
                ROW_NUMBER() OVER (PARTITION BY id_firestore ORDER BY ts_updated) = 1
        ),
        latest_reject_reason AS (
            SELECT *
            FROM datalake_sales_flow_clean.reject_reason
            QUALIFY
                ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) = 1
        ),
        latest_payment AS (
            SELECT *
            FROM datalake_sales_flow_clean.payment
            QUALIFY
                ROW_NUMBER() OVER (PARTITION BY id_sales_flow ORDER BY ts_updated DESC) = 1
        ),
        first_payment_aud AS (
            SELECT *,
                payment_method AS planned_payment_method
            FROM datalake_sales_flow_clean.payment_aud
            QUALIFY
                ROW_NUMBER() OVER (PARTITION BY id_sales_flow ORDER BY ts_updated ASC) = 1
        ),
        latest_monopoly_sale_revision AS (
            SELECT *
            FROM datalake_monopoly_clean.sale_revision
            QUALIFY
                ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_event DESC) = 1
        ),
        latest_brokerage AS (
            SELECT
                id_sales_flow,
                quinto_andar_brokerage_split,
                brokerage_fee,
                brokerage_fee_payer
            FROM datalake_sales_flow_clean.brokerage
            QUALIFY
                ROW_NUMBER() OVER(PARTITION BY id_sales_flow ORDER BY ts_updated DESC) = 1
        ),
        latest_house AS (
            SELECT *
            FROM datalake_sales_flow_clean.house
            QUALIFY
                ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) = 1
        ),
        flow_type AS (
            SELECT
                o.id_firestore AS id_offer,
                sf.flow_type
            FROM
                datalake_sales_flow_clean.offer_aud AS o
            LEFT JOIN
                latest_sales_flow AS sf
                    ON sf.id = o.id_sales_flow
            GROUP BY
                o.id_firestore,
                sf.flow_type
        ),
        offers AS (
            SELECT
                l.id_firestore AS id_offer,
                l.id_sales_flow,
                l.sale_price,
                f.offer_price AS first_price_offered_by_buyer,
                l.offer_price AS last_price_offered_by_buyer,
                l.registry_price,
                l.itbi_price,
                l.ts_created,
                l.ts_updated,                
                CASE
                    WHEN l.sale_price IS NULL OR f.offer_price IS NULL
                        THEN NULL
                    ELSE 1-1.00*f.offer_price/l.sale_price
                END AS first_discount_proposed,
                CASE
                    WHEN l.sale_price IS NULL OR l.offer_price IS NULL
                        THEN NULL
                    ELSE 1-1.00*l.offer_price/l.sale_price
                END AS last_discount_proposed
            FROM
                latest_offer AS l
            LEFT JOIN
                first_offer_aud AS f
                    ON l.id_firestore = f.id_firestore
            LEFT JOIN
                latest_reject_reason AS lre
                    ON l.id_reject_reason = lre.id
        ),
        sales_flow AS (
            SELECT
                sf.id,
                sf.id_house,
                sf.buyer_id_external AS id_buyer,
                sf.seller_id_external AS id_seller,
                sf.flow_type,
                sf.status,
                sf.is_canceled,
                sf.ts_canceled
            FROM
                latest_sales_flow AS sf
            INNER JOIN
                offers AS sfo
                    ON sfo.id_sales_flow = sf.id
        ),
        payment AS (
            SELECT
                p.id_sales_flow,
                p.payment_method,
                fpm.planned_payment_method,
                p.fgts_value,
                p.entry_amount,
                p.down_payment_value,
                CASE WHEN p.payment_method LIKE '%USING_FGTS'
                    THEN TRUE
                    ELSE FALSE
                END AS has_used_fgts_in_payment
            FROM
                latest_payment AS p
            INNER JOIN
                first_payment_aud AS fpm
                    ON p.id = fpm.id
            INNER JOIN
                offers AS sfo
                    ON sfo.id_sales_flow = p.id_sales_flow
        ),
        monopoly AS (
            SELECT
                id_external_offer AS id_offer,
                financed_amount AS financing_value
            FROM
                latest_monopoly_sale_revision
        ),
        brokerage AS (
            SELECT * FROM latest_brokerage
        ),
        house AS (
            SELECT
                h.id,
                h.id_external
            FROM
                latest_house AS h
        ),
        agent AS (
            SELECT 
                s.id_sales_flow,
                s.id_user AS id_agent,                
                ROW_NUMBER() OVER (
                    PARTITION BY s.id_sales_flow 
                    ORDER BY s.ts_updated DESC
                ) as row_num
            FROM 
                datalake_sales_flow_clean.specialist AS s
            WHERE 
                s.kind = 'AGENT'
        )
SELECT
        off.id_offer,
        sf.id_buyer,
        sf.id_seller,
        sf.id_house,
        sf.id AS id_sales_flow,
        sf.status,
        sf.is_canceled,
        sf.ts_canceled,
        off.ts_created AS ts_offer_created,
        off.sale_price AS sale_listing_price,
        off.first_price_offered_by_buyer,
        off.last_price_offered_by_buyer,
        off.ts_updated AS ts_offer_updated,
        p.has_used_fgts_in_payment,
        CASE WHEN ft.flow_type = 'DEFAULT'
            THEN TRUE
            ELSE FALSE
        END AS has_used_negotiation_chat,
        off.last_discount_proposed,
        off.first_discount_proposed,
        p.payment_method,
        p.planned_payment_method,
        off.registry_price,
        off.itbi_price,
        p.entry_amount,
        mpl.financing_value,
        p.fgts_value,
        p.down_payment_value,
        COALESCE(b.brokerage_fee, 0.06::DECIMAL(5,4)) AS brokerage_fee,
        CONCAT(sf.id_buyer,'_', h.id_external) AS id_sale_flow,
        a.id_agent
    FROM
        offers AS off
    LEFT JOIN
        sales_flow AS sf
            ON sf.id = off.id_sales_flow
    LEFT JOIN
        flow_type AS ft
            ON ft.id_offer = off.id_offer
    LEFT JOIN
        payment AS p
            ON p.id_sales_flow = off.id_sales_flow
    LEFT JOIN
        monopoly AS mpl
            ON off.id_offer = mpl.id_offer
    LEFT JOIN
        brokerage AS b
            ON b.id_sales_flow = off.id_sales_flow
    LEFT JOIN
        house AS h
            ON h.id = sf.id_house
    LEFT JOIN
        agent AS a
            ON a.id_sales_flow = sf.id
            AND a.row_num = 1
)
, unified_offers AS (
    SELECT 
            COALESCE(vo.id_offer, g.id) AS id_offer,
            vo.id_sales_flow AS id_sales_flow,
            COALESCE(vo.id_sale_flow, g.id_sale_flow) AS id_sale_flow,            
            COALESCE(vo.id_house, g.id_house) AS id_house,
            COALESCE(vo.id_buyer, g.id_buyer) AS id_buyer,            
            COALESCE(vo.id_seller, g.id_owner) AS id_owner,
            COALESCE(vo.id_agent, g.id_agent) AS id_agent,
            vo.status AS status,            
            COALESCE(vo.payment_method, g.current_payment_method) AS current_payment_method,
            --COALESCE(vo.planned_payment_method, g.planned_payment_method) AS planned_payment_method,

            ROUND(COALESCE(vo.sale_listing_price, g.sale_price), 2) AS sale_price,
            ROUND(COALESCE(vo.first_price_offered_by_buyer, g.first_price_offered_by_buyer), 2) AS first_price_offered_by_buyer,
            ROUND(COALESCE(vo.last_price_offered_by_buyer, g.last_price_offered_by_buyer), 2) AS last_price_offered_by_buyer,
            ROUND(COALESCE(vo.last_discount_proposed, g.last_discount_proposed), 2) AS last_discount_proposed,
            ROUND(COALESCE(vo.first_discount_proposed, g.first_discount_proposed), 2) AS first_discount_proposed,
            ROUND(COALESCE(vo.registry_price, g.registry_price), 2) AS registry_price,
            ROUND(COALESCE(vo.itbi_price, g.itbi_price), 2) AS itbi_price,
            ROUND(COALESCE(vo.entry_amount, g.payment_entry_amount), 2) AS payment_entry_amount,
            ROUND(COALESCE(vo.financing_value, g.financing_value), 2) AS financing_value,
            ROUND(COALESCE(vo.fgts_value, g.fgts_value), 2) AS fgts_value,
            ROUND(COALESCE(vo.down_payment_value, g.earnest_value), 2) AS earnest_value,
            ROUND(COALESCE(vo.brokerage_fee, g.brokerage_fee), 2) AS giroffer_brokerage_fee,

            COALESCE(vo.has_used_fgts_in_payment, g.has_used_fgts_in_payment) AS has_used_fgts_in_payment,
            COALESCE(vo.has_used_negotiation_chat, g.has_used_negotiation_chat) AS has_used_negotiation_chat,
            vo.is_canceled AS is_canceled,
            
            COALESCE(vo.ts_offer_created, g.ts_created) AS ts_offer_created,
            COALESCE(vo.ts_offer_updated, g.ts_updated) AS ts_updated,            
            vo.ts_canceled AS ts_canceled
            
    FROM firestore_sale_offer AS g
    FULL OUTER JOIN sale_offer AS vo ON vo.id_offer = g.id

)

SELECT 
        *
FROM    
        unified_offers