from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("S3Service")


class S3Service:
    def __init__(self, boto3_s3_resource):
        self.s3 = boto3_s3_resource

    @staticmethod
    def _split_s3_path(s3_path):
        split = s3_path.split("/")
        bucket_name = split[2]
        suffix = "/".join(split[3:])
        return bucket_name, suffix

    @logger
    def upload_file(self, file, file_path):
        """
        Upload a file to s3 giving raw file string and a full s3 path
        :param file: raw file string
        :param file_path: full path to the target s3 location, ex: "s3://bucket-name/path/to/file.txt"
        :return: None
        """
        bucket_name, key = self._split_s3_path(file_path)
        self.s3.Bucket(bucket_name).put_object(Key=key, Body=file.encode())

    @logger
    def list_objects(self, folder_path, with_size=False):
        """
        Recursively list all objects under a folder path in s3
        :param folder_path: full path to the target folder in s3, ex: "s3://bucket-name/path/to/folder/"
        :param with_size: boolean parameter to include size of the objects alongside with the paths
        :return: list of all the objects discovered under the folder
        """
        bucket_name, objects_filter = self._split_s3_path(folder_path)
        path_prefix = "s3://{}/".format(bucket_name)
        if with_size:
            return [
                (path_prefix + obj.key, obj.size)
                for obj in self.s3.Bucket(bucket_name).objects.filter(
                    Prefix=objects_filter
                )
            ]
        return [
            path_prefix + obj.key
            for obj in self.s3.Bucket(bucket_name).objects.filter(Prefix=objects_filter)
        ]
