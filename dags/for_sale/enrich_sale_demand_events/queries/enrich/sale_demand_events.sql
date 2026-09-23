WITH bookings AS (
  SELECT
    esv.id_booking,
    esv.id_sale_flow,
    esv.ts_booking_created,
    esv.ts_visit_completed,
    esv.ts_visit_canceled,
    esv.id_house,
    esv.id_region,
    esv.id_buyer,
    esv.id_seller,
    esv.id_agent,
    CAST(NULL AS BIGINT) AS sk_company_supply, -- deprecated: removed from sale_visit (enrich_company deprecation)
    CAST(NULL AS BIGINT) AS sk_company_demand, -- deprecated: removed from sale_visit (enrich_company deprecation)
    esv.id_business_unit,
    esv.sale_type
  FROM
    datalake_sale_visit.sale_visit AS esv
),
offers AS (
  SELECT
    eso.id_offer,
    CONCAT(eso.id_buyer,'_', eso.id_house) AS id_sale_flow,
    eso.ts_offer_submitted,
    eso.ts_offer_accepted AS dt_offer_accepted,
    eso.ts_sale_agreement_created AS dt_sale_agreement_created,
    eso.ts_sale_agreement_signed AS dt_sale_agreement_signed,
    eso.ts_offer_dismissed AS dt_offer_dismissed,
    eso.id_booking,
    eso.id_house,
    eso.id_region,
    eso.id_buyer,
    eso.id_owner AS id_seller,
    eso.id_agent,
    eso.id_company_supply AS sk_company_supply,
    eso.id_company_demand AS sk_company_demand,
    eso.id_business_unit,
    eso.sale_type
  FROM
    datalake_sale_offer.sale_offer AS eso
),
events AS (
    SELECT -- Visit Booked
        DATE(ts_booking_created) AS dt_event,
        id_sale_flow,
        1 AS sk_event_type,
        'VISIT_BOOKED' AS event_name,
        id_booking,
        NULL AS id_offer,
        id_house,
        id_region,
        id_buyer,
        id_seller,
        id_agent,
        sk_company_supply,
        sk_company_demand,
        id_business_unit,
        sale_type,
        ts_booking_created AS ts_event
    FROM
        bookings
    WHERE
        ts_booking_created IS NOT NULL
    UNION ALL
    SELECT -- Visit Completed
        DATE(ts_visit_completed) AS dt_event,
        id_sale_flow,
        2 AS sk_event_type,
        'VISIT_COMPLETED' AS event_name,
        id_booking,
        NULL AS id_offer,
        id_house,
        id_region,
        id_buyer,
        id_seller,
        id_agent,
        sk_company_supply,
        sk_company_demand,
        id_business_unit,
        sale_type,
        ts_visit_completed AS ts_event
    FROM
        bookings
    WHERE
        ts_visit_completed IS NOT NULL
    UNION ALL
    SELECT -- Offer Submitted
        DATE(ts_offer_submitted) AS dt_event,
        id_sale_flow,
        3 AS sk_event_type,
        'OFFER_SUBMITTED' AS event_name,
        id_booking,
        id_offer,
        id_house,
        id_region,
        id_buyer,
        id_seller,
        id_agent,
        sk_company_supply,
        sk_company_demand,
        id_business_unit,
        sale_type,
        ts_offer_submitted AS ts_event
    FROM
        offers
    WHERE
        ts_offer_submitted IS NOT NULL
    UNION ALL
    SELECT -- Offer Accepted
        DATE(dt_offer_accepted) AS dt_event,
        id_sale_flow,
        4 AS sk_event_type,
        'OFFER_ACCEPTED' AS event_name,
        id_booking,
        id_offer,
        id_house,
        id_region,
        id_buyer,
        id_seller,
        id_agent,
        sk_company_supply,
        sk_company_demand,
        id_business_unit,
        sale_type,
        dt_offer_accepted AS ts_event
    FROM
        offers
    WHERE
        dt_offer_accepted IS NOT NULL
    UNION ALL
    SELECT -- Sale Agreement Created
        DATE(dt_sale_agreement_created) AS dt_event,
        id_sale_flow,
        5 AS sk_event_type,
        'SALE_AGREEMENT_CREATED' AS event_name,
        id_booking,
        id_offer,
        id_house,
        id_region,
        id_buyer,
        id_seller,
        id_agent,
        sk_company_supply,
        sk_company_demand,
        id_business_unit,
        sale_type,
        CAST(dt_sale_agreement_created AS TIMESTAMP) AS ts_event
    FROM
        offers
    WHERE
        dt_sale_agreement_created IS NOT NULL
    UNION ALL
    SELECT -- Sale Agreement Signed
        DATE(dt_sale_agreement_signed) AS dt_event,
        id_sale_flow,
        6 AS sk_event_type,
        'SALE_AGREEMENT_SIGNED' AS event_name,
        id_booking,
        id_offer,
        id_house,
        id_region,
        id_buyer,
        id_seller,
        id_agent,
        sk_company_supply,
        sk_company_demand,
        id_business_unit,
        sale_type,
        dt_sale_agreement_signed AS ts_event
    FROM
        offers
    WHERE
        dt_sale_agreement_signed IS NOT NULL
    UNION ALL
    SELECT -- Visit canceled
        DATE(ts_visit_canceled) AS dt_event,
        id_sale_flow,
        7 AS sk_event_type,
        'VISIT_CANCELLED' AS event_name,
        id_booking,
        -1 AS id_offer,
        id_house,
        id_region,
        id_buyer,
        id_seller,
        id_agent,
        sk_company_supply,
        sk_company_demand,
        id_business_unit,
        sale_type,
        ts_visit_canceled AS ts_event
    FROM
        bookings
    WHERE
        ts_visit_canceled IS NOT NULL
    UNION ALL
    SELECT -- Offer dismissed
        DATE(dt_offer_dismissed) AS dt_event,
        id_sale_flow,
        8 AS sk_event_type,
        'OFFER_REJECTED' AS event_name,
        id_booking,
        id_offer,
        id_house,
        id_region,
        id_buyer,
        id_seller,
        id_agent,
        sk_company_supply,
        sk_company_demand,
        id_business_unit,
        sale_type,
        CAST(dt_offer_dismissed AS TIMESTAMP) AS ts_event
    FROM
        offers
    WHERE
        dt_offer_dismissed IS NOT NULL
)
SELECT
  sk_event_type,
  sk_company_supply,
  sk_company_demand,
  id_sale_flow,
  id_agent,
  id_booking,
  id_business_unit,
  id_buyer,
  id_house,
  id_offer,
  id_region,
  id_seller,
  event_name,
  sale_type,
  dt_event,
  ts_event
FROM
  events
