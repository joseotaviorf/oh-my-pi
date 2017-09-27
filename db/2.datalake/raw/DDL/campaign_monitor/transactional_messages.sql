create external table datalake_raw.cm_transactional_messages (
  canberesent boolean,
  clicks array<
          struct<
            date:string,
            ipaddress:string,
            mailclient:struct<
                         version:string,
                         name:string
                       >,
            emailaddress:string,
            url:string,
            geolocation:struct<
                          city:string,
                          countrycode:string,
                          region:string,
                          longitude:double,
                          countryname:string,
                          latitude:double
                        >
          >
         >,
  message struct<
            body:struct<
                   text:string,
                   html:string
                 >,
            to:array<string>,
            from:string,
            data:struct<
                   search_url:string,
                   thumbor_url:string,
                   gmaps_proxy_url:string,
                   alerts:string,
                   _metadata:string,
                   unsubscribe_link:string,
                   email:string
                 >,
            subject:string
          >,
  messageid string,
  opens array<
          struct<
            date:string,
            ipaddress:string,
            mailclient:struct<
                         version:string,
                         name:string
                       >,
            emailaddress:string,
            geolocation:struct<
                          city:string,
                          countrycode:string,
                          region:string,
                          longitude:double,
                          countryname:string,
                          latitude:double
                         >
          >
        >,
  recipient string,
  sentat string,
  smartemailid string,
  status string,
  totalclicks int,
  totalopens int,
  dt string
)
partitioned by (
  project string
)
row format serde
  'org.openx.data.jsonserde.JsonSerDe'
location
  's3://5a-datalake/raw/campaign_monitor/transactional_messages/'
;


msck repair table datalake_raw.cm_transactional_messages;
