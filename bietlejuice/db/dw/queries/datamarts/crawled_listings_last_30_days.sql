SELECT
  *
FROM datamarts.all_crawled_listings_last_30_days
WHERE website IN ('imovelweb', 'vivareal', 'zapimoveis')  -- ignore olx
  AND COALESCE(rent, '') != ''  -- only listings for rent, not if only for sale
