DROP VIEW IF EXISTS public.vw_imovel_liquidity_marketing_costs;
CREATE OR REPLACE VIEW public.vw_imovel_liquidity_marketing_costs
AS

WITH mkt_costs AS
(
  SELECT
  	h.date,
    h.id,
    p.version,
    h.status_history,
    
    COALESCE(
      NULLIF(count(1) FILTER(WHERE h.status_history::text = 'publicado'::text) OVER(PARTITION BY h.date), 0)
      , 1::bigint
    ) AS count_published_date,

    max(a.cost_per_published_listings) AS vl_total_day_cost_marketing_campaigns,

    CASE
      WHEN h.status_history::text = 'publicado'::text THEN
        max(a.cost_per_published_listings)
        / COALESCE(
            NULLIF(count(1) FILTER(WHERE h.status_history::text = 'publicado'::text) OVER(PARTITION BY h.date), 0)
            , 1::bigint
        )::numeric
      ELSE 0::numeric
    END AS vl_cost_marketing_campaigns_per_published_listings,

    max(g.cost_per_published_listings) AS vl_total_day_cost_marketing_ads,

    CASE
      WHEN h.status_history::text = 'publicado'::text THEN
      	max(g.cost_per_published_listings)
        / COALESCE(
        	NULLIF(count(1) FILTER(WHERE h.status_history::text = 'publicado'::text) OVER(PARTITION BY h.date), 0)
        	, 1::bigint
          )::numeric
      ELSE 0::numeric
    END AS vl_cost_marketing_ads_per_published_listings

  FROM
	imovel_status_full_history h
    
  inner join
	vw_property_listing p
	on p.id = h.id
	and h.date between coalesce(p.min_version_time, '1900-01-01') and coalesce(p.max_version_time, now()) 

  LEFT JOIN
  (
    SELECT
    	g.day::date AS date,
        sum(g.cost::numeric (14, 4)) / 1000000::numeric AS cost_per_published_listings
    FROM
    	google_ads_campaigns g
    WHERE
    	g.campaign_area::text = 'liquidity'::text
    GROUP BY
    	g.day
  ) g
  ON g.date = h.date

  LEFT JOIN
  (
    SELECT
    	f.date::date AS date,
        sum(f.spend::numeric (18, 4)) AS cost_per_published_listings
    FROM
    	facebook_ads_campaigns f
    WHERE
    	f.account_name::text = 'Acquisition & Liquidity'::text
    GROUP BY
    	f.date
  ) a ON a.date = h.date

  GROUP BY
	h.date,
	h.id,
    p.version,
	h.status_history
)
SELECT
  mkt_costs.id,
  mkt_costs.version,
  array_agg(mkt_costs.date::text) AS dates,
  sum(mkt_costs.vl_cost_marketing_campaigns_per_published_listings) AS
    vl_cost_marketing_campaigns_per_published_listings,
  sum(mkt_costs.vl_cost_marketing_ads_per_published_listings) AS
    vl_cost_marketing_ads_per_published_listings
FROM
  mkt_costs
GROUP BY
  mkt_costs.id,
  mkt_costs.version
;
