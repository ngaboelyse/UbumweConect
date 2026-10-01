from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, desc
from typing import List

from app.database import get_db
from app.models.user import User, UserRole
from app.models.chat import Message, Conversation
from app.models.translation import TranslationCache
from app.middleware.auth_middleware import get_current_user

router = APIRouter(prefix="/admin", tags=["Admin"])


async def require_admin(current_user: User = Depends(get_current_user)):
    if current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=403, detail="Admin access required")
    return current_user


@router.get("/dashboard/stats")
async def dashboard_stats(
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(require_admin),
):
    user_count = await db.scalar(select(func.count(User.id)))
    active_users = await db.scalar(select(func.count(User.id)).where(User.is_online == True))
    message_count = await db.scalar(select(func.count(Message.id)).where(Message.is_deleted == False))
    conversation_count = await db.scalar(select(func.count(Conversation.id)))
    translation_count = await db.scalar(select(func.count(TranslationCache.id)))
    cache_hits = await db.scalar(select(func.sum(TranslationCache.hit_count)))

    return {
        "total_users": user_count,
        "active_users_now": active_users,
        "total_messages": message_count,
        "total_conversations": conversation_count,
        "total_translations": translation_count,
        "translation_cache_hits": cache_hits or 0,
    }


@router.get("/users")
async def list_all_users(
    skip: int = 0,
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(require_admin),
):
    result = await db.execute(
        select(User).order_by(desc(User.created_at)).offset(skip).limit(limit)
    )
    users = result.scalars().all()
    total = await db.scalar(select(func.count(User.id)))
    return {
        "users": [{"id": str(u.id), "email": u.email, "username": u.username, "is_active": u.is_active, "role": u.role, "created_at": u.created_at} for u in users],
        "total": total,
        "skip": skip,
        "limit": limit,
    }


@router.put("/users/{user_id}/status")
async def toggle_user_status(
    user_id: str,
    active: bool,
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(require_admin),
):
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.is_active = active
    await db.commit()
    return {"user_id": user_id, "is_active": active}


@router.get("/analytics/languages")
async def language_analytics(
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(require_admin),
):
    result = await db.execute(
        select(User.preferred_language, func.count(User.id).label("count"))
        .group_by(User.preferred_language)
        .order_by(desc("count"))
    )
    stats = result.all()
    return {"language_distribution": [{"language": row[0], "count": row[1]} for row in stats]}


@router.get("/analytics/translations")
async def translation_analytics(
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(require_admin),
):
    result = await db.execute(
        select(
            TranslationCache.source_language,
            TranslationCache.target_language,
            func.count(TranslationCache.id).label("count"),
            func.sum(TranslationCache.hit_count).label("cache_hits"),
        )
        .group_by(TranslationCache.source_language, TranslationCache.target_language)
        .order_by(desc("count"))
    )
    rows = result.all()
    return {
        "translation_pairs": [
            {
                "source": row[0],
                "target": row[1],
                "total_translations": row[2],
                "cache_hits": row[3] or 0,
            }
            for row in rows
        ]
    }


@router.get("/system/health")
async def system_health(
    db: AsyncSession = Depends(get_db),
    admin: User = Depends(require_admin),
):
    db_ok = False
    try:
        await db.execute(select(func.now()))
        db_ok = True
    except Exception:
        pass

    return {
        "status": "healthy" if db_ok else "degraded",
        "database": "connected" if db_ok else "error",
        "version": "1.0.0",
    }
