import boto3
import uuid
import mimetypes
from typing import Optional
from botocore.exceptions import ClientError
from app.config import settings


class FileService:
    def __init__(self):
        self._client = None
        self._bucket = settings.AWS_S3_BUCKET
        self._region = settings.AWS_REGION

    def is_configured(self) -> bool:
        return bool(settings.AWS_ACCESS_KEY_ID and settings.AWS_SECRET_ACCESS_KEY)

    def _get_client(self):
        if not self._client:
            self._client = boto3.client(
                "s3",
                aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
                aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
                region_name=self._region,
            )
        return self._client

    def _get_public_url(self, key: str) -> str:
        return f"https://{self._bucket}.s3.{self._region}.amazonaws.com/{key}"

    async def upload_bytes(
        self,
        data: bytes,
        filename: str,
        folder: str = "uploads",
        content_type: str = "application/octet-stream",
    ) -> str:
        """Upload bytes to S3 and return public URL."""
        if not self.is_configured():
            raise RuntimeError("AWS S3 is not configured")

        key = f"{folder}/{uuid.uuid4()}_{filename}"
        client = self._get_client()
        client.put_object(
            Bucket=self._bucket,
            Key=key,
            Body=data,
            ContentType=content_type,
        )
        return self._get_public_url(key)

    async def upload_file_object(
        self,
        file_object,
        filename: str,
        folder: str = "uploads",
        user_id: Optional[str] = None,
    ) -> str:
        """Upload a file object (from FastAPI UploadFile) to S3."""
        if not self.is_configured():
            raise RuntimeError("AWS S3 is not configured")

        content_type, _ = mimetypes.guess_type(filename)
        content_type = content_type or "application/octet-stream"
        unique_filename = f"{uuid.uuid4()}_{filename}"
        key = f"{folder}/{user_id or 'anonymous'}/{unique_filename}"

        client = self._get_client()
        data = await file_object.read()
        client.put_object(
            Bucket=self._bucket,
            Key=key,
            Body=data,
            ContentType=content_type,
        )
        return self._get_public_url(key)

    async def delete_file(self, url: str) -> bool:
        """Delete a file from S3 by URL."""
        if not self.is_configured():
            return False
        try:
            prefix = f"https://{self._bucket}.s3.{self._region}.amazonaws.com/"
            key = url.replace(prefix, "")
            client = self._get_client()
            client.delete_object(Bucket=self._bucket, Key=key)
            return True
        except ClientError:
            return False

    def generate_presigned_url(self, key: str, expiration: int = 3600) -> str:
        """Generate a presigned URL for private file access."""
        client = self._get_client()
        return client.generate_presigned_url(
            "get_object",
            Params={"Bucket": self._bucket, "Key": key},
            ExpiresIn=expiration,
        )

    def validate_file_type(self, filename: str, allowed_types: list) -> bool:
        ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
        return ext in allowed_types

    def validate_file_size(self, size_bytes: int, max_mb: int = 50) -> bool:
        return size_bytes <= max_mb * 1024 * 1024
