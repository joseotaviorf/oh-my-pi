import s3fs
import petl


class S3FileReader():
    def __init__(self):
        self.s3fs = s3fs.S3FileSystem()

    def get_files_from_bucket(self, bucket):
        files = self.s3fs.ls(bucket, refresh=True)
        for f in files:
            print ("Processing file [" + f + "]")
            with self.s3fs.open(f, 'rb') as file:
                yield file, f.split('/')[1].lower().split('.')[0]

    @classmethod
    def get_tables_from_files(cls, filename):
        return petl.fromxlsx(filename=filename, data_only=True)
