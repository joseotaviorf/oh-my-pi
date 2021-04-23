----------------------------------------------------------------------------------------------------------------
-- Rule to assign a sk_booking to an id_offer.
-- OBS: not every offer comes from a booking.
-- If the sale flow has a visit completed before offer submission, it gets the closest visit to offer.
-- If the sale flow has only a booking before offer, it gets the closest booking to offer.
----------------------------------------------------------------------------------------------------------------
WITH booking_before_offer AS (
-- Looking for offers that had only a booking before offer submission and searching the closest id_booking of that booking
  WITH bk_aux AS (
      SELECT
        so.id AS id_offer,
        bs.id AS id_booking,
        bs.id_agent,
        TRUE AS flg_booking_before_offer,
        (unix_timestamp(so.ts_created)-unix_timestamp(bs.ts_created))/(3600) AS hours_booking_to_offer,
        (unix_timestamp(so.ts_created)-unix_timestamp(bs.ts_booking_utc))/(3600) AS hours_visit_to_offer,
        ROW_NUMBER() OVER (PARTITION BY so.id ORDER BY (unix_timestamp(so.ts_created)-unix_timestamp(bs.ts_created))) AS rw_booking
      FROM datalake_firestore.sale_offer so
      JOIN datalake_booking.booking bs
        ON bs.id_house = so.id_house
        AND bs.id_visitor = so.id_buyer
      WHERE
        bs.visit_intent = 'SALE'
        AND bs.type = 'Visita'
        AND bs.ts_created < so.ts_created
        AND (bs.visit_fup !='VaiNegociar' OR bs.visit_fup IS NULL)
      )
  SELECT
      bk.*
  FROM bk_aux bk
  WHERE rw_booking = 1
),
visit_before_offer AS (
-- Looking for offers that had a visit completed before offer submission and searching the closest id_booking of that visit
-- The visit_fup category = 'VaiNegociar' indicates that the visit was completed
    WITH vc_aux AS (
      SELECT
        so.id AS id_offer,
        bs.id AS id_booking,
        bs.id_agent,
        TRUE AS flg_visit_completed_before_offer,
        (unix_timestamp(so.ts_created)-unix_timestamp(bs.ts_created))/(3600) AS hours_booking_to_offer,
        (unix_timestamp(so.ts_created)-unix_timestamp(bs.ts_booking_utc))/(3600) AS hours_visit_to_offer,
        ROW_NUMBER() OVER (PARTITION BY so.id  ORDER BY (unix_timestamp(so.ts_created)-unix_timestamp(bs.ts_booking_utc))) AS rw_visit_completed
      FROM datalake_firestore.sale_offer so
      JOIN datalake_booking.booking bs
        ON bs.id_house = so.id_house
        AND bs.id_visitor = so.id_buyer
      WHERE
        bs.visit_intent = 'SALE'
        AND bs.type = 'Visita'
        AND bs.ts_booking_utc < so.ts_created
        AND bs.visit_fup ='VaiNegociar'
    )
    SELECT
        vc.*
    FROM vc_aux vc
    WHERE vc.rw_visit_completed = 1
),
relation_booking_offer AS (
  SELECT
    COALESCE(vo.id_offer, bo.id_offer) AS id_offer,
    COALESCE(vo.id_booking, bo.id_booking) AS id_booking,
    COALESCE(vo.id_agent, bo.id_agent) AS id_agent,
    COALESCE(vo.hours_booking_to_offer, bo.hours_booking_to_offer) AS hours_booking_to_offer,
    COALESCE(vo.hours_visit_to_offer, bo.hours_visit_to_offer) AS hours_visit_to_offer,
    COALESCE(bo.flg_booking_before_offer,vo.flg_visit_completed_before_offer) AS flg_booking_before_offer,
    vo.flg_visit_completed_before_offer
  FROM visit_before_offer vo
  FULL OUTER JOIN booking_before_offer bo
      ON bo.id_offer = vo.id_offer
),
rank_offers AS (
  SELECT
    so.id,
    ROW_NUMBER() OVER (PARTITION BY so.id_buyer ORDER BY so.ts_created) AS buyer_rank_offers,
    ROW_NUMBER() OVER (PARTITION BY so.id_house ORDER BY so.ts_created) AS house_rank_offers
  FROM datalake_firestore.sale_offer so
)
----------------------------------------------------------------------------------------------------------------
-- Offer submission info comes from firestore.sale_offer (offer submission service)
-- Other data are only tracked in the monday plataform where negotiation flows happens
-- If the both sources have the same info, it brings preferably the firestore.sale_offer info
----------------------------------------------------------------------------------------------------------------
SELECT
  so.id AS id_offer,
  so.id_sale_flow,
  so.id_buyer,
  so.id_house,
  so.id_owner,
  m.id_closing_specialist,
  m.id_consultant,
  rbo.id_booking,
  rbo.id_agent,
  so.sale_price,
  so.first_price_offered_by_buyer,
  so.last_price_offered_by_buyer,
  m.sale_price_agreed,
  so.brokerage_fee,
  so.earnest_value,
  so.fgts_value,
  so.financing_value,
  so.payment_entry_amount,
  so.itbi_price,
  so.registry_price,
  so.planned_payment_method,
  so.current_payment_method,
  m.financing_bank,
  m.status AS monday_status,
  m.offer_status,
  m.sale_agreement_status,
  m.sale_agreement_cancellation_reason,
  m.drop_reason,
  m.drop_reason_responsible,
  m.offer_acceptance_probability,
  so.first_discount_proposed,
  so.last_discount_proposed,
  COALESCE(rbo.flg_booking_before_offer,FALSE) AS flg_booking_before_offer,
  COALESCE(rbo.flg_visit_completed_before_offer,FALSE) AS flg_visit_completed_before_offer,
  rbo.hours_booking_to_offer,
  rbo.hours_visit_to_offer,
  DATEDIFF(m.dt_accepted, so.ts_created) AS days_offer_submitted_to_offer_accepted,
  DATEDIFF(m.dt_offer_dismissed, so.ts_created) AS days_offer_submitted_to_offer_dismissed,
  DATEDIFF(m.dt_sale_agreement_created, so.ts_created) AS days_offer_submitted_to_sale_agreement_created,
  DATEDIFF(m.dt_sale_agreement_signed, so.ts_created) AS days_offer_submitted_to_sale_agreement_signed,
  m.days_offer_accepted_to_offer_dismissed,
  m.days_offer_accepted_to_sale_agreement_created,
  m.days_offer_accepted_to_sale_agreement_signed,
  m.days_sale_agreement_created_to_sale_agreement_signed,
  so.has_used_negotiation_chat,
  so.has_used_fgts_in_payment,
  CASE WHEN rk.buyer_rank_offers = 1 THEN TRUE ELSE FALSE END AS is_buyer_first_offer,
  CASE WHEN rk.house_rank_offers = 1 THEN TRUE ELSE FALSE END AS is_house_first_offer,
  m.dt_accepted AS dt_offer_accepted,
  m.dt_offer_dismissed,
  m.dt_sale_agreement_created,
  m.dt_sale_agreement_signed,
  m.dt_sale_agreement_cancelled,
  m.dt_house_registry_started,
  m.dt_house_registry_ended,
  m.dt_sale_transacton_paid,
  so.ts_created AS ts_offer_submitted,
  so.ts_updated
FROM datalake_firestore.sale_offer so
LEFT JOIN datalake_firestore.monday m
  ON so.id = m.id_offer
LEFT JOIN relation_booking_offer rbo
  ON rbo.id_offer = so.id
LEFT JOIN rank_offers rk
  ON rk.id = so.id