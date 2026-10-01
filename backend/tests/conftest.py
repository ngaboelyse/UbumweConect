"""
Pytest configuration and shared fixtures for Ubumwe Connect backend tests.
"""
import asyncio
import pytest
import pytest_asyncio
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker

from app.main import app
from app.database import Base, get_db

# Each pytest session gets a brand-new SQLite file (under pytest's tmp dir),
# so stale data from previous runs can never cause 409 conflicts.


@pytest.fixture(scope="session")
def db_file(tmp_path_factory):
    """Create a unique test database file for this session."""
    return tmp_path_factory.mktemp("db") / "test.sqlite"


@pytest.fixture(scope="session")
def event_loop():
    """Create a single event loop for all tests."""
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest_asyncio.fixture(scope="session")
async def test_engine(db_file):
    """Create test database engine."""
    test_database_url = f"sqlite+aiosqlite:///{db_file}"
    engine = create_async_engine(test_database_url, echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()


@pytest_asyncio.fixture(autouse=True)
async def reset_tables(test_engine):
    """Give every test a clean database (endpoints commit, so per-test
    transactions can't roll back — we recreate the schema instead)."""
    async with test_engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    yield


@pytest_asyncio.fixture
async def db_session(test_engine):
    """Create a fresh DB session for each test, rolled back after."""
    async_session = async_sessionmaker(test_engine, expire_on_commit=False)
    async with async_session() as session:
        yield session
        await session.rollback()


@pytest_asyncio.fixture
async def async_client(db_session):
    """Async HTTP test client with DB dependency overridden."""
    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        yield client
    app.dependency_overrides.clear()


@pytest_asyncio.fixture
async def test_user(async_client) -> dict:
    """Create and return a test user."""
    response = await async_client.post("/api/v1/auth/register", json={
        "email": "testuser@example.com",
        "username": "test_user",
        "display_name": "Test User",
        "password": "SecurePass@123",
        "preferred_language": "english"
    })
    assert response.status_code == 201
    return response.json()


@pytest_asyncio.fixture
async def test_user_tokens(test_user) -> dict:
    """Return access and refresh tokens for test user."""
    return {
        "access_token": test_user["access_token"],
        "refresh_token": test_user["refresh_token"]
    }


@pytest_asyncio.fixture
async def auth_headers(test_user_tokens) -> dict:
    """Return Authorization headers for authenticated requests."""
    return {"Authorization": f"Bearer {test_user_tokens['access_token']}"}


@pytest_asyncio.fixture
async def second_user(async_client) -> dict:
    """Create a second test user."""
    response = await async_client.post("/api/v1/auth/register", json={
        "email": "seconduser@example.com",
        "username": "second_user",
        "display_name": "Second User",
        "password": "SecurePass@123",
        "preferred_language": "kinyarwanda"
    })
    assert response.status_code == 201
    return response.json()["user"]


@pytest_asyncio.fixture
async def second_user_headers(async_client, second_user) -> dict:
    """Return Authorization headers for the second user."""
    # The register response includes tokens for the second user
    response = await async_client.post("/api/v1/auth/login", json={
        "email": "seconduser@example.com",
        "password": "SecurePass@123"
    })
    assert response.status_code == 200
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest_asyncio.fixture
async def conversation(async_client, auth_headers, second_user) -> dict:
    """Create a test conversation between two users."""
    response = await async_client.post(
        "/api/v1/conversations",
        json={"participant_ids": [second_user["id"]], "type": "direct"},
        headers=auth_headers
    )
    assert response.status_code == 201
    return response.json()


class MockCompletion:
    """Mock OpenAI completion response."""
    def __init__(self, content: str):
        self.choices = [MockChoice(content)]


class MockChoice:
    def __init__(self, content: str):
        self.message = MockMessage(content)


class MockMessage:
    def __init__(self, content: str):
        self.content = content
