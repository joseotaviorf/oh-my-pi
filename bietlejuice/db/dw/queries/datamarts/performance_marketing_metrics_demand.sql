with
bookings as (
	select
        date,
        city_group,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        count(distinct sk_booking) as bookings,
        count(distinct case when rk = 1 then sk_booking else null end) as first_bookings
	from(
        SELECT
            dd.date,
            dr.city_group,
            a.sk_booking,
            a.mkt_origin,
            a.mkt_channel,
            a.mkt_medium,
            a.mkt_source,
            row_number() over(partition by sk_client order by a.dt_created) as rk
        FROM
            dim_booking a
        join fact_listing_rent_flows flrf
            using(sk_booking)
        join dim_date dd
            on flrf.sk_booking_created_date = dd.sk_date
        join dim_region dr
            using(sk_region)
        WHERE
            sk_booking > 0
            and a.visit_intent = 'RENT'
            and a.type = 'Visita'
	) o
	where date >= date('2020-01-01')
	group by 1,2,3,4,5,6
),
offers as (
    select
        date,
        city_group,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        count(distinct sk_offer) as offers,
        count(distinct case when rk = 1 then sk_offer else null end) as first_offers
    from(
        SELECT
            dd.date,
            dr.city_group,
            a.sk_offer,
            a.mkt_origin,
            a.mkt_channel,
            a.mkt_medium,
            a.mkt_source,
            row_number() over(partition by id_user order by dt_first_sent) as rk
        FROM
            dim_offer a
        join fact_listing_rent_flows flrf
            using(sk_offer)
        join dim_date dd
            on flrf.sk_offer_submitted_date = dd.sk_date
        join dim_region dr
            using(sk_region)
        WHERE sk_offer > 0
    ) o
    where date >= date('2020-01-01')
    group by 1,2,3,4,5,6
),
demand_daily_spent as (
    select
        dd.date,
        co.city_group,
        co.mkt_origin,
        co.mkt_channel,
        co.mkt_medium,
        co.mkt_source,
        sum(co.cost::float) as spent
    from marketing.fact_marketing_daily_costs co
    join dim_date dd
        on dd.sk_date = co.sk_date
    where
        co.mkt_origin = 'Tenants PWA'
        and dd.date >= date('2020-01-01')
    group by 1, 2, 3, 4, 5, 6
),
demand_daily_targets as (
    select
        str.date::date,
        str.city_group,
        'Tenants PWA' as mkt_origin,
        str.mkt_channel,
        str.mkt_medium,
        '' as mkt_source,
        sum(nullif(budget,'')) as budget,
        sum(nullif(visits_booked_target,'')) as visits_booked_target,
        sum(nullif(offer_sent_target,'')) as offer_sent_target,
        sum(nullif(first_offer_sent_target,'')) as first_offer_sent_target
    from datalake_raw.gsheets_demand_targets_replanning str
    where str.date::date >= date('2020-01-01')
    group by 1, 2, 3, 4, 5, 6
)
select
    coalesce(b.date, o.date, dds.date, ddt.date) as date,
    coalesce(b.city_group, o.city_group, dds.city_group, ddt.city_group) as city_group,
    coalesce(b.mkt_origin, o.mkt_origin, dds.mkt_origin, ddt.mkt_origin) as mkt_origin,
    coalesce(b.mkt_channel, o.mkt_channel, dds.mkt_channel, ddt.mkt_channel) as mkt_channel,
    coalesce(b.mkt_medium, o.mkt_medium, dds.mkt_medium, ddt.mkt_medium) as mkt_medium,
    coalesce(b.mkt_source, o.mkt_source, dds.mkt_source, ddt.mkt_source) as mkt_source,
    sum(dds.spent) as spent,
    sum(ddt.budget) as budget,
    sum(b.bookings) as visits_booked,
    sum(b.first_bookings) as first_bookings,
    sum(ddt.visits_booked_target) as visits_booked_target,
    sum(o.offers) as offer_sent,
    sum(o.first_offers) as first_offer_sent,
    sum(ddt.offer_sent_target) as offer_sent_target,
    sum(ddt.first_offer_sent_target) as first_offer_sent_target
from bookings b
full outer join offers o
    on  b.date = o.date
    and b.city_group = o.city_group
    and b.mkt_origin = o.mkt_origin
    and b.mkt_channel = o.mkt_channel
    and b.mkt_medium = o.mkt_medium
    and b.mkt_source = o.mkt_source
full outer join demand_daily_spent dds
    on  b.date = dds.date
    and b.city_group = dds.city_group
    and b.mkt_origin = dds.mkt_origin
    and b.mkt_channel = dds.mkt_channel
    and b.mkt_medium = dds.mkt_medium
    and b.mkt_source = dds.mkt_source
full outer join demand_daily_targets ddt
    on  b.date = ddt.date
    and b.city_group = ddt.city_group
    and b.mkt_origin = ddt.mkt_origin
    and b.mkt_channel = ddt.mkt_channel
    and b.mkt_medium = ddt.mkt_medium
    and b.mkt_source = ddt.mkt_source
group by 1, 2, 3, 4, 5, 6