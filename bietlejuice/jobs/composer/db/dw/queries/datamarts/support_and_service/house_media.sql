with
max_video_revision_by_house as (
  select
    aud.external_domain,
    aud.id_external_domain,
    max(cast(ts_revised as timestamp)) as ts_last_revised
  from datalake_kodak_clean_prod.video_aud aud
  join datalake_kodak_clean_prod.user_revision_entity ure on aud.rev = ure.id
  group by 1, 2
),
videos as (
  with
  listings_with_videos as (
    select
        v.id_external_domain as id_house,
        count(*) as number_of_videos
    from datalake_kodak_clean_prod.video v
    where v.external_domain = 'HOUSE'
      and v.id_source is not null
    group by 1
  )
  select
      v.id_house,
      v.number_of_videos,
      r.ts_last_revised
  from listings_with_videos v
  left join max_video_revision_by_house r
      on v.id_house = r.id_external_domain
),
max_photo_revision_by_house as (
  select
    aud.external_domain,
    aud.id_external_domain,
    max(cast(ts_revised as timestamp)) as ts_last_revised
  from datalake_kodak_clean_prod.photo_sphere_aud aud
  join datalake_kodak_clean_prod.user_revision_entity ure on aud.rev = ure.id
  group by 1, 2
),
photos as (
  with
  listings_with_photos as (
    select
        p.id_external_domain as id_house,
        filter(
          array_agg(
            replace(trim(lower(
              cast(json_extract(p.metadata, '$.description') as varchar)  -- extract json
            )), ' ', '-')  -- slugify strings by trim, lower, and replace spaces for hypens
          ) -- aggregate into an array
        , x -> x IS NOT NULL) as description_360_photos,  -- filter out null strings
        count(*) as number_of_360_photos
    from datalake_kodak_clean_prod.photo_sphere p
    where p.external_domain = 'HOUSE'
      and p.path is not null
    group by 1
  )
  select
      p.id_house,
      p.description_360_photos,
      p.number_of_360_photos,
      r.ts_last_revised
  from listings_with_photos p
  left join max_photo_revision_by_house r
      on p.id_house = r.id_external_domain
)
select
  coalesce(v.id_house, p.id_house) as id_house,
  coalesce(v.number_of_videos, 0) as number_of_videos,
  coalesce(p.number_of_360_photos, 0) as number_of_360_photos,
  slice(p.description_360_photos, 1, 40) as description_360_photos,
  v.ts_last_revised as ts_video_last_updated,
  p.ts_last_revised as ts_360_photos_last_updated,
  now() as ts_load
from videos v
full outer join photos p on v.id_house = p.id_house
