--drop view if exists vw_potential_listings_rep_leads;
--create or replace view vw_potential_listings_rep_leads as
SELECT
    f.id,
    bl.lead_type,
    bl.lead_origin,
    bl.reprocessed_flg,
    bl.utm_source,
    bl.utm_medium,
    bl.branded_lead
  FROM listing_flows_with_reprocessed_leads AS f
  JOIN rep_leads AS bl
    ON bl.lead_id = f.lead_id