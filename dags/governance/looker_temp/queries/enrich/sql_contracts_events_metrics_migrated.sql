SELECT
  sk_house_listing,
  MAX(sk_contract) AS sk_contract,
  COUNT(DISTINCT CASE WHEN sk_contract > 0 THEN sk_contract END) AS contracts,
  COUNT(DISTINCT CASE WHEN sk_booking > 0 THEN sk_booking END) AS bookings,
  COUNT(DISTINCT CASE WHEN sk_offer > 0 THEN sk_offer END) AS offers,
  COUNT(DISTINCT CASE WHEN sk_client > 0 THEN sk_client END) AS users
FROM dw_rent.fact_listing_rent_flows
GROUP BY
  1