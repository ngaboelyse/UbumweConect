import boto3
import uuid
import mimetypes
import shutil
from pathlib import Path
from typing import Optional
from botocore.exceptions import ClientError
from app.config import settings

# Local fallback storage used when S3 credentials are not configured.
LOCAL_UPLOAD_DIR = Path("/app/uploads")


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

    def _store_local(self, data: bytes, filename: str, folder: str) -> str:
        """Persist the file under /app/uploads and return an API-served URL."""
        safe_folder = folder.replace("..", "_").strip("/")
        target_dir = LOCAL_UPLOAD_DIR / safe_folder
        target_dir.mkdir(parents=True, exist_ok=True)
        key = f"{uuid.uuid4()}_{filename}"
        (target_dir / key).write_bytes(data)
        return f"/files/{safe_folder}/{key}"

    def _get_public_url(self, key: str) -> str:
        return f"https://{self._bucket}.s3.{self._region}.amazonaws.com/{key}"

    async def upload_bytes(
        self,
        data: bytes,
        filename: str,
        folder: str = "uploads",
        content_type: str = "application/octet-stream",
    ) -> str:
        """Upload bytes to S3 (or local disk as fallback) and return public URL."""
        if not self.is_configured():
            return self._store_local(data, filename, folder)

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
            data = await file_object.read()
            return self._store_local(data, filename, folder)

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

    async def download_bytes(self, url: str) -> bytes:
        """Fetch a previously-uploaded file's bytes by its public URL.

        Supports the local-storage URLs this service returns (`/files/...`)
        and full S3 https URLs. Raises RuntimeError on failure.
        """
        if not url:
            raise RuntimeError("Empty URL")
        if url.startswith("/files/"):
            key = url.removeprefix("/files/").replace("..", "_")
            path = (LOCAL_UPLOAD_DIR / key).resolve()
            try:
                # Guard against path traversal outside the uploads dir.
                path.relative_to(LOCAL_UPLOAD_DIR.resolve())
            except ValueError:
                raise RuntimeError(f"Invalid file path: {url}")
            if not path.is_file():
                raise RuntimeError(f"File not found: {url}")
            return path.read_bytes()
        if url.startswith(("http://", "https://")):
            import httpx
            async with httpx.AsyncClient(timeout=30) as http:
                resp = await http.get(url)
                resp.raise_for_status()
                return resp.content
        raise RuntimeError(f"Unsupported file URL: {url}")

    def validate_file_type(self, filename: str, allowed_types: list) -> bool:
        ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
        return ext in allowed_types

    def validate_file_size(self, size_bytes: int, max_mb: int = 50) -> bool:
        return size_bytes <= max_mb * 1024 * 1024
