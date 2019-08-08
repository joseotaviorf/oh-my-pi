WITH
matches AS (
  SELECT
    m.sk_house_listing,
    m.id_crawled_listing,
    SUM(CASE WHEN m."match" IN ('yes', 'yes-identical') THEN 1 ELSE 0 END) AS positive_matches,
    SUM(CASE WHEN m."match" IN ('yes-identical') THEN 1 ELSE 0 END) AS identical_matches,
    SUM(CASE WHEN m."match" IN ('no') THEN 1 ELSE 0 END) AS negative_matches,
    COUNT(*) AS total_matches
  FROM datalake_raw.crawler_matches m
  GROUP BY 1, 2
),
quintoandar_listings AS (
  SELECT
         l.sk_house_listing,
         l.house_bedrooms,
         l.ts_publication AS quintoandar_ts_publication,
         'https://www.quintoandar.com.br/imovel/' || l.id_house AS quintoandar_url,
         l.rent AS quintoandar_rent
  FROM public.dim_house_listing l
  WHERE status IN ('publicado') AND is_last_version
    AND l.ts_publication >= DATEADD('day', -14, CURRENT_DATE) -- our listings pulished in the last 7 days
),
quintoandar_join_crawled AS
(
  SELECT
    q.sk_house_listing,
    c.id_crawled_listing,
    q.quintoandar_rent - c.rent AS rent_difference,
    q.quintoandar_rent,
    c.rent AS crawled_rent,
    DATE(q.quintoandar_ts_publication) AS quintoandar_publication_date,
    c.first_time_updated_on AS crawler_first_time_updated_on,
    m.positive_matches,
    m.identical_matches,
    m.negative_matches,
    m.total_matches,
    q.quintoandar_url,
    c.url AS crawled_url
  FROM quintoandar_listings AS q
  JOIN matches AS m ON q.sk_house_listing = m.sk_house_listing
  JOIN datamarts.crawled_listings_last_30_days AS c ON m.id_crawled_listing = c.id_crawled_listing
)
SELECT
  *
FROM quintoandar_join_crawled
