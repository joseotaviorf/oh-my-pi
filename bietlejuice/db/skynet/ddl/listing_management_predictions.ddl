CREATE EXTERNAL TABLE skynet_forno.listing_management_predictions(
sk_house_listing bigint,
prediction_possible boolean,
cnt_bookings double,
cnt_discarded double,
cnt_docs_approved double,
cnt_docs_completed double,
cnt_docs_sent double,
cnt_favorite_set double,
cnt_listing_views double,
cnt_offers double,
cnt_offers_accepted double,
cnt_schedule_views double,
cnt_visits double,
days integer,
prediction double,
date_of_computation string,
publication_date string
)
partitioned by(
  dt date
)
ROW FORMAT  serde 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://5a-skynet-forno/listing-mgmt/data/predictions';


CREATE EXTERNAL TABLE skynet.listing_management_predictions(
sk_house_listing bigint,
prediction_possible boolean,
cnt_bookings double,
cnt_discarded double,
cnt_docs_approved double,
cnt_docs_completed double,
cnt_docs_sent double,
cnt_favorite_set double,
cnt_listing_views double,
cnt_offers double,
cnt_offers_accepted double,
cnt_schedule_views double,
cnt_visits double,
days integer,
prediction double,
date_of_computation string,
publication_date string
)
partitioned by(
  dt date
)
ROW FORMAT  serde 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://5a-skynet/listing-mgmt/data/predictions';