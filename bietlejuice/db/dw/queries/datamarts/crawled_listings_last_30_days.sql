SELECT
  *
FROM datamarts.all_crawled_listings_last_120_days
WHERE DATE(first_time_updated_on) >= CURRENT_DATE - 30  -- only listings posted or updated in the last 30 days
