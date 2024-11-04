-- These files are added in the bucket s3://amplitude-merged-users-external
-- by the Amplitude team.
CREATE TABLE datalake_amplitude_raw.183047_user_merge (
    scope int,
    merge_time bigint,
    merge_server_time bigint,
    amplitude_id bigint,
    merged_amplitude_id bigint
)
USING JSON
OPTIONS (
  path 's3://amplitude-merged-users-external.s3.data.quintoandar.com.br/183047'
)
