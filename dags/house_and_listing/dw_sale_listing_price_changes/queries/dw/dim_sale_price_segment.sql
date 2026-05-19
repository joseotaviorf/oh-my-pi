SELECT DISTINCT
  DENSE_RANK() over (ORDER BY price_segment) AS sk_sale_price_segment,
  price_segment,
  CASE
    WHEN price_segment = 'High Ticket' 
      THEN 'HT'
    WHEN price_segment = 'Low Ticket'
      THEN 'LT'
  END AS price_segment_short
FROM 
  datalake_sale_listings.sale_listing_price_changes