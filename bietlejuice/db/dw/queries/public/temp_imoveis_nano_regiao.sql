/*
 * Query to save the regions of each listing used during nano region test
*/
insert into temp_imoveis_nano_regiao
select distinct
    dhl.sk_house_listing,
    sk_region
from dim_house_listing dhl
    join fact_house_listing_flows fhl
        using(sk_house_listing)
where sk_region in (45,2491,2492,2493,2494,2495)