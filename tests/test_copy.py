from jobs.base.base_etl import BaseETL, EnumDb


conn = BaseETL.get_connection(db_enum=EnumDb.BI_ODS, encoding='LATIN-1')
cur = conn.cursor()

with open('/tmp/example.csv') as f:
    l = f.readline()
    cur.copy_from(f, 'tmp_example', ',')# , columns=['city','region','email','id'])

conn.commit()
