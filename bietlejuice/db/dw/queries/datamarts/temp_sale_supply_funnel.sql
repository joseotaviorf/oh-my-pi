-- Search the in revision table the first date when listing was modified
with quali_aux as (
    SELECT 
            cast(lbcaud.imovelid as varchar) as id_house, 
            CAST(REPLACE(LEFT(from_unixtime(cast(min(ure.ts_revision) as bigint)/1000), 10), '-', '') AS BIGINT) as dt_lbcaud_creation -- convert in sk_date
    FROM 
        datalake_ebdb_raw_prod.ListingBusinessContext_AUD lbcaud -- not in clean yet
    JOIN datalake_ebdb_clean_prod.user_revision_entity ure
        ON ure.id = lbcaud.rev
    WHERE 
        lbcaud.businesscontext = 'SALE' 
    GROUP BY 1
)
 -- Search the in revision table the first date when listing was published
, fl_aux as (
    SELECT 
            cast (lbcaud.imovelid as varchar) as id_house, 
            CAST(REPLACE(LEFT(from_unixtime(cast(min(ure.ts_revision) as bigint)/1000), 10), '-', '') AS BIGINT) as dt_lbcaud_first_publication 
    FROM 
        datalake_ebdb_raw_prod.ListingBusinessContext_AUD lbcaud -- not in clean yet
    JOIN datalake_ebdb_clean_prod.user_revision_entity ure 
        ON ure.id = lbcaud.rev
    WHERE 
        lbcaud.businessContext = 'SALE' 
        AND lbcaud.status = 'PUBLISHED'
    GROUP BY 1
)
-- Search the creation date when in House table
, house_lbc as (
     SELECT 
        cast(h.id as varchar) as id_house, 
        CAST(REPLACE(LEFT(h.dt_creation, 10), '-', '') AS BIGINT) as dt_house_creation,
        CAST(REPLACE(LEFT(lbc.ts_created, 10), '-', '') AS BIGINT) as dt_lbc_created,
        CAST(REPLACE(LEFT(lbc.ts_first_publication, 10), '-', '') AS BIGINT) as dt_lbc_first_publication
    FROM datalake_ebdb_clean_prod.house h 
    LEFT JOIN datalake_ebdb_clean_prod.listing_business_context lbc
        ON lbc.id_house = h.id
    WHERE (lbc.business_context = 'SALE' OR lbc.business_context IS NULL)
)
-- Fix sk_qualified_date and sk_first_listing_date
, aux_q_fl_dt as (
SELECT
    sale.sk_house_listing_flow,
    sale.sk_house_listing,
    CASE 
        WHEN lbc.status IS NULL OR COALESCE(h.dt_lbc_created,h.dt_house_creation) IS NULL 
            THEN 'NOT QUALIFIED YET' 
        ELSE lbc.status 
    END AS lead_status,
    CASE 
        WHEN sale.sk_lead_date >= 20200301 AND sale.sk_user_lead_affiliate > 0 
            THEN true 
        ELSE dl.is_for_sale 
    END AS lead_sale,
    CASE 
        WHEN sale.sk_lead_date >= 20200301 AND sale.sk_user_lead_affiliate > 0 
            THEN true 
        ELSE dl.is_for_rent 
    END AS lead_rent,
    CASE
        WHEN lead_sale = true and lead_rent = false 
            THEN 'Sale'
        WHEN lead_sale = false and lead_rent = true 
            THEN 'Rent'
        WHEN lead_sale = true and lead_rent = true 
            THEN 'Hybrid'
        WHEN lead_sale = false and lead_rent = false 
            THEN 'Not identified'
        WHEN sale.sk_lead = -1 OR (lead_sale IS NULL AND lead_rent IS NULL) 
            THEN 'Organic'
        ELSE 'Unknown'
    END AS lead_origin_context,
    CASE
        WHEN lbc.status is null 
            THEN -1 
        WHEN  sale.sk_qualified_date < 20191201
                AND lbc.status IN ('PUBLISHED', 'SUSPENDED', 'UNPUBLISHED', 'EDITING','OPTED_OUT') 
                    AND COALESCE(h.dt_lbc_created, quali_aux.dt_lbcaud_creation, h.dt_house_creation) > 20191201
            THEN COALESCE(h.dt_lbc_created, quali_aux.dt_lbcaud_creation, h.dt_house_creation)
        WHEN sale.sk_qualified_date < 20191201 
                AND lbc.status IN ('PUBLISHED', 'SUSPENDED', 'UNPUBLISHED', 'EDITING', 'OPTED_OUT') 
            THEN 20191202
        ELSE COALESCE(h.dt_lbc_created, sale.sk_qualified_date)    
    END AS sk_qualified_date,
    CASE 
        WHEN sale.sk_first_listing_date < 20191202 
                AND lbc.status IN ('PUBLISHED', 'SUSPENDED', 'UNPUBLISHED') 
                    AND  COALESCE(h.dt_lbc_first_publication, fl_aux.dt_lbcaud_first_publication, h.dt_lbc_created) > 20191201
            THEN COALESCE(h.dt_lbc_first_publication, fl_aux.dt_lbcaud_first_publication, h.dt_lbc_created)
        WHEN sale.sk_first_listing_date < 20191202 
                AND lbc.status IN ('PUBLISHED', 'SUSPENDED', 'UNPUBLISHED')
            THEN 20191202
        WHEN lbc.status IN ('EDITING','OPTED_OUT')
            THEN -1
        ELSE COALESCE(h.dt_lbc_first_publication, fl_aux.dt_lbcaud_first_publication, sale.sk_first_listing_date)
    END AS sk_first_listing_date
FROM 
    sale.fact_listing_flows AS sale 
JOIN dim_lead AS dl 
    ON dl.sk_lead = sale.sk_lead
JOIN dim_user du 
    ON du.sk_user = sale.sk_user_house_registrant 
LEFT JOIN house_lbc h 
    ON h.id_house = LEFT(sale.sk_house_listing, 9)
LEFT JOIN datalake_ebdb_clean_prod.listing_business_context lbc
    ON lbc.id_house = LEFT(sale.sk_house_listing, 9)
LEFT JOIN  fl_aux 
    ON fl_aux.id_house = LEFT(sale.sk_house_listing, 9)
LEFT JOIN  quali_aux
    ON quali_aux.id_house = LEFT(sale.sk_house_listing, 9)
WHERE (lbc.business_context = 'SALE' OR lbc.business_context IS NULL)
)
-- Final base
SELECT 
    sale.sk_lead,
    sale.sk_house_listing,
    CAST(LEFT(sale.sk_house_listing, 9) AS BIGINT) AS id_house,
    sk_region,
    qfl.lead_origin_context,
    qfl.lead_sale,
    qfl.lead_rent,
    qfl.lead_status,
    CASE 
        WHEN lead_origin_context = 'Rent' -- in this context lead starts in qualified step
            THEN qfl.sk_qualified_date
        WHEN qfl.sk_qualified_date < 0 AND (sale.sk_lead_date BETWEEN 0 AND 20191202)
            THEN 20191202
        WHEN qfl.sk_qualified_date > 0 AND (sale.sk_lead_date < 20191202 OR sale.sk_lead_date > qfl.sk_qualified_date)
            THEN qfl.sk_qualified_date
        ELSE sale.sk_lead_date
    END AS sk_lead_date,
    CASE 
        WHEN lead_origin_context = 'Rent' -- in this context lead starts in qualified step
            THEN qfl.sk_qualified_date
        WHEN qfl.sk_qualified_date < 0 AND (sale.sk_prospect_date BETWEEN 0 AND 20191202)
            THEN 20191202
        WHEN qfl.sk_qualified_date > 0 AND (sale.sk_prospect_date < 20191202 OR sale.sk_prospect_date > qfl.sk_qualified_date)
            THEN qfl.sk_qualified_date
        ELSE sale.sk_prospect_date
    END AS sk_prospect_date,
    qfl.sk_qualified_date,
    CASE
        WHEN qfl.sk_first_listing_date < 0 AND (sale.sk_opportunity_date BETWEEN 0 AND qfl.sk_qualified_date)
            THEN -1
        WHEN qfl.sk_first_listing_date > 0 AND sale.sk_opportunity_date < qfl.sk_qualified_date
            THEN GREATEST(qfl.sk_qualified_date, qfl.sk_first_listing_date)
        WHEN qfl.sk_first_listing_date > 0 AND sale.sk_opportunity_date > qfl.sk_first_listing_date
            THEN qfl.sk_first_listing_date
        ELSE sale.sk_opportunity_date 
    END AS sk_opportunity_date,
    CASE 
        WHEN qfl.sk_first_listing_date > 0 AND qfl.sk_qualified_date > qfl.sk_first_listing_date
            THEN qfl.sk_qualified_date
        ELSE qfl.sk_first_listing_date
    END AS sk_first_listing_date,
    sale.mkt_origin,
    sale.mkt_channel,
    sale.mkt_medium,
    sale.mkt_source,
    CASE
	    WHEN lower(dl.utm_campaign) ~ '.*(sale|girafa|vender).*' OR sale.sk_user_lead_affiliate in (912255, 360754, 1711931) 
	        THEN 'Sale'
	    WHEN (dl.utm_campaign is NULL OR dl.utm_campaign='') 
	        THEN 'Organic'
	   ELSE 'Rental'
	END AS mkt_campaign_context,
    CASE
        WHEN sale.mkt_completion = 'Full Self-Service' AND sale.has_isales_intervention = false 
            THEN 'FSS' 
        WHEN sale.mkt_origin = 'B2B' AND sale.is_b2b = true 
            THEN  'B2B'
        WHEN sale.has_isales_intervention = true AND du.dados_vendedor_id > 0 
            THEN 'IS Int'
        WHEN sale.has_isales_intervention = true AND dl.sales_company in ('ATENTO','ACTION_LINE') 
            THEN 'IS Ext'
        ELSE 'Other'
    END AS sourcing_ops
FROM 
    sale.fact_listing_flows AS sale 
JOIN dim_lead AS dl 
    ON dl.sk_lead = sale.sk_lead
JOIN aux_q_fl_dt AS qfl
    ON sale.sk_house_listing_flow = qfl.sk_house_listing_flow
LEFT JOIN dim_user du 
    ON du.sk_user = sale.sk_user_house_registrant
