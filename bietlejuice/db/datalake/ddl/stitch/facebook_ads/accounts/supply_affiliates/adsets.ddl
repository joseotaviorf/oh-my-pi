CREATE EXTERNAL TABLE stitch.`facebook_ads_supply_affiliates_adsets`(
  `effective_status` string,
  `bid_info` struct<actions:int>,
  `targeting` struct<
    excluded_custom_audiences:array<
      struct<
        id:string,
        name:string
      >
    >,
    facebook_positions:array<string>,
    instagram_positions:array<string>,
    publisher_platforms:array<string>,
    age_min:int,
    device_platforms:array<string>,
    geo_locations:struct<
      location_types:array<string>,
      cities:array<
        struct<
          region:string,
          distance_unit:string,
          name:string,
          region_id:string,
          radius:int,
          key:string,
          country:string
        >
      >,
      custom_locations:array<
        struct<
          distance_unit:string,
          primary_city_id:int,
          region_id:int,
          radius:int,
          longitude:double,
          latitude:double,
          country:string
        >
      >
    >,
    age_max:int,
    messenger_positions:array<string>,
    audience_network_positions:array<string>,
    user_os:array<string>,
    user_device:array<string>,
    flexible_spec:array<
      struct<
        behaviors:array<
          struct<
            id:string,
              name:string
          >
        >,
        life_events:array<
          struct<
            id:string,
            name:string
          >
        >,
        family_statuses:array<
          struct<
            id:string,
            name:string
          >
        >
      >
    >,
    exclusions:struct<
      income:array<
        struct<
          id:string,
          name:string
        >
      >,
      behaviors:array<
        struct<
          id:string,
          name:string
        >
      >
    >,
    excluded_geo_locations:struct<
      location_types:array<string>,
      custom_locations:array<
        struct<
          distance_unit:string,
          primary_city_id:int,
          region_id:int,
          radius:int,
          longitude:double,
          latitude:double,
          country:string
        >
      >
    >
  >,
  `campaign_id` string,
  `daily_budget` double,
  `promoted_object` struct<
    custom_event_type:string,
    pixel_id:string
  >,
  `updated_time` string,
  `id` string,
  `name` string,
  `_sdc_table_version` int,
  `lifetime_budget` double,
  `created_time` string,
  `budget_remaining` double,
  `_sdc_received_at` string,
  `_sdc_sequence` bigint,
  `start_time` string,
  `account_id` string,
  `_sdc_batched_at` string,
  `_sdc_extracted_at` string)
ROW FORMAT SERDE
  'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
  'ignore.malformed.json' = 'true'
)
LOCATION
  's3://5a-datalake/stitch_data/facebook_ads_supply_affiliates/adsets/';