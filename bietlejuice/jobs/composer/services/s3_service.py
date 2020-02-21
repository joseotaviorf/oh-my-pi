import re

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("S3Service")


class S3Service:
    def __init__(self, s3_resource):
        """
        Handle the execution of common tasks on S3.
        :param s3_resource: boto3 s3 resource. It can be got with boto3.resource('s3')
        """
        self.s3_resource = s3_resource

    @staticmethod
    def _split_s3_path(s3_path):
        if not isinstance(s3_path, str) or not re.match("s3://.+/.*", s3_path):
            raise ValueError(
                "m=_split_s3_path, s3_path={}, msg=given s3_path is not a valid s3 path".format(
                    s3_path
                )
            )
        split = s3_path.split("/")
        bucket_name = split[2]
        suffix = "/".join(split[3:])
        return bucket_name, suffix

    @logger
    def upload_file(self, file_content, s3_file_path):
        """
        Upload a file to s3 giving raw file string and a full s3 path
        :param file_content: raw file content string
        :param s3_file_path: full path to the target s3 location, ex: "s3://bucket-name/path/to/file.txt"
        :return: None
        """
        bucket_name, key = self._split_s3_path(s3_file_path)
        self.s3_resource.Bucket(bucket_name).put_object(
            Key=key, Body=file_content.encode()
        )

    @logger
    def list_objects(self, s3_folder_path, include_size=False):
        """
        Recursively list all objects under a folder path in s3
        :param s3_folder_path: full path to the target folder in s3, ex: "s3://bucket-name/path/to/folder/"
        :param include_size: boolean parameter to include size of the objects alongside with the paths
        :return: list of all the objects discovered under the folder
        """
        bucket_name, objects_filter = self._split_s3_path(s3_folder_path)
        path_prefix = "s3://{}/".format(bucket_name)
        if include_size:
            return [
                (path_prefix + obj.key, obj.size)
                for obj in self.s3_resource.Bucket(bucket_name).objects.filter(
                    Prefix=objects_filter + "/"
                )
            ]
        return [
            path_prefix + obj.key
            for obj in self.s3_resource.Bucket(bucket_name).objects.filter(
                Prefix=objects_filter + "/"
            )
        ]
