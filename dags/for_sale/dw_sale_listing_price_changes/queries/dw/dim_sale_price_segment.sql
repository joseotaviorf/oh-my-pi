SELECT DISTINCT
  DENSE_RANK() over (ORDER BY ticket_segmentation) AS sk_sale_price_segment,
  price_segment,
  CASE
    WHEN ticket_segmentation = 'High Ticket' 
      THEN 'HT'
    WHEN ticket_segmentation = 'Low Ticket'
      THEN 'LT'
  END AS price_segment_short
FROM 
  datalake_sale_listings.sale_listing_price_changes