# TODO Create table from dictionary or array.
import pyathenajdbc
from jobs.base.base_etl import BaseETL


class AthenaAmplitudeETL(BaseETL):
    def __init__(self, *args, **kwargs):
        super(AthenaAmplitudeETL, self).__init__(*args, **kwargs)
        self.amplitude_bucket = '5a-amplitude-events'

    def _execute_query(self, sql, s3_staging_dir=None):
        if s3_staging_dir is None:
            s3_staging_dir = 's3://{}/query_results/'.format(self.amplitude_bucket)

        conn = pyathenajdbc.connect(s3_staging_dir=s3_staging_dir, region_name='us-east-1')

        with conn.cursor() as cursor:
            cursor.execute(sql)
            try:
                df = pyathenajdbc.util.as_pandas(cursor)
            except ValueError:
                df = None

        return df

    def create_athena_table(self, database, table_name, schema, location, partitions=None, serde_options=None,
                            drop_if_exists=True):
        if drop_if_exists:
            self._execute_query("""DROP TABLE IF EXISTS {}.{}""".format(database, table_name))

        query = """CREATE EXTERNAL TABLE IF NOT EXISTS {}.{} ({}) """.format(database, table_name, schema)

        if partitions is not None:
            query += """PARTITIONED BY ({}) """.format(partitions)

        query += """ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe' """

        if serde_options is not None:
            query += """WITH SERDEPROPERTIES ({}) """.format(serde_options)

        query += """LOCATION '{}'""".format(location)

        print("Trying to create {}.{}...".format(database, table_name))

        self._execute_query(query)

        print("Table created! If it has partitions and you need them right now, run msck_repair_table function.")

    def msck_repair_table(self, database, table_name):
        self._execute_query("""MSCK REPAIR TABLE {}.{}""".format(database, table_name))

    def update_partitions(self, table, location):
        # An alternative approach would be to simply use an
        # "msck repair table fastly" statement but this is very slow at Athena.
        # we will pay to list all S3 keys, so try to be efficient with the location choice
        #
        #
        # if not location.endswith('/'):
        #     location += '/'
        #
        # bucket_path = 's3://{}/'.format(self.amplitude_bucket)
        # prefix = location[len(bucket_path):]
        #
        # all_keys = boto3.resource('s3').Bucket(self.amplitude_bucket).objects.filter(Prefix=prefix)
        #
        # objects = set([k.key for k in all_keys if k.key.endswith('.gz')])
        #
        # partitions = set()
        # for o in objects:
        #     partitions.add(o[:len(o) - o[::-1].find('/')])
        #
        # for p in list(partitions):
        #     pp = re.split('/|=', p)
        #
        #     sql = """ALTER TABLE {} ADD IF NOT EXISTS""".format(table)
        #     sql += """PARTITION (app = {}, event_type = '{}', server_upload_date = date '{}')""". \
        #         format(pp[1], pp[3], pp[5])
        #     sql += """LOCATION '{}'""".format(bucket_path + p)
        #
        #     print ("Adding new partition at {}".format(bucket_path + p))
        #     self._execute_query(sql)

        # TODO Need to figure out how to implement this one to be generic at location and partitions!
        raise NotImplementedError
