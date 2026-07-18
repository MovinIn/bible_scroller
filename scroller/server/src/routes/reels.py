from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from src.book_ids import dbp_book_id, iq_verse_id
from src.database import get_db
from src.deps import get_optional_user, require_user
from src.models import Comment, CommentLike, Reel, ReelLike, User
from src.schemas import (
    BibleAudioOut,
    BibleVerseOut,
    BibleVersionOut,
    CommentCreate,
    CommentOut,
    LikeStatusOut,
    ReelFeedOut,
)
from src.services.bible_brain_service import get_bible_client
from src.services.reels import comment_to_out, get_feed, list_books, list_comments

router = APIRouter(prefix="/reels", tags=["reels"])


@router.get("", response_model=ReelFeedOut)
def feed(
    cursor: int | None = Query(default=None),
    before_id: int | None = Query(default=None, ge=1),
    from_id: int | None = Query(default=None, ge=1),
    book: str | None = Query(default=None, min_length=1),
    limit: int = Query(default=10, ge=1, le=50),
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
) -> ReelFeedOut:
    return get_feed(
        db,
        user,
        cursor=cursor,
        before_id=before_id,
        limit=limit,
        from_id=from_id,
        book=book,
    )


@router.get("/books", response_model=list[str])
def books(db: Session = Depends(get_db)) -> list[str]:
    return list_books(db)


@router.get("/{reel_id}/comments", response_model=list[CommentOut])
def get_comments(
    reel_id: int,
    db: Session = Depends(get_db),
    user: User | None = Depends(get_optional_user),
) -> list[CommentOut]:
    reel = db.get(Reel, reel_id)
    if reel is None:
        raise HTTPException(status_code=404, detail="Reel not found")
    return list_comments(db, user, reel_id)


@router.post("/{reel_id}/comments", response_model=CommentOut, status_code=201)
def create_comment(
    reel_id: int,
    payload: CommentCreate,
    db: Session = Depends(get_db),
    user: User = Depends(require_user),
) -> CommentOut:
    reel = db.get(Reel, reel_id)
    if reel is None:
        raise HTTPException(status_code=404, detail="Reel not found")

    parent_id = payload.parent_id
    if parent_id is not None:
        parent = db.get(Comment, parent_id)
        if parent is None or parent.reel_id != reel_id:
            raise HTTPException(status_code=400, detail="Invalid parent comment for this reel")

    comment = Comment(
        reel_id=reel_id,
        user_id=user.id,
        parent_id=parent_id,
        body=payload.body.strip(),
    )
    db.add(comment)
    db.commit()
    db.refresh(comment)
    comment.author = user
    return comment_to_out(comment, user, db)


@router.post("/{reel_id}/like", response_model=LikeStatusOut)
def like_reel(
    reel_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_user),
) -> LikeStatusOut:
    reel = db.get(Reel, reel_id)
    if reel is None:
        raise HTTPException(status_code=404, detail="Reel not found")

    existing = (
        db.query(ReelLike)
        .filter(ReelLike.reel_id == reel_id, ReelLike.user_id == user.id)
        .one_or_none()
    )
    if existing is None:
        db.add(ReelLike(reel_id=reel_id, user_id=user.id))
        db.commit()

    like_count = db.query(ReelLike).filter(ReelLike.reel_id == reel_id).count()
    return LikeStatusOut(liked=True, like_count=like_count)


@router.delete("/{reel_id}/like", response_model=LikeStatusOut)
def unlike_reel(
    reel_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_user),
) -> LikeStatusOut:
    reel = db.get(Reel, reel_id)
    if reel is None:
        raise HTTPException(status_code=404, detail="Reel not found")

    db.query(ReelLike).filter(ReelLike.reel_id == reel_id, ReelLike.user_id == user.id).delete()
    db.commit()
    like_count = db.query(ReelLike).filter(ReelLike.reel_id == reel_id).count()
    return LikeStatusOut(liked=False, like_count=like_count)


comments_router = APIRouter(prefix="/comments", tags=["comments"])


@comments_router.post("/{comment_id}/like", response_model=LikeStatusOut)
def like_comment(
    comment_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_user),
) -> LikeStatusOut:
    comment = db.get(Comment, comment_id)
    if comment is None:
        raise HTTPException(status_code=404, detail="Comment not found")

    existing = (
        db.query(CommentLike)
        .filter(CommentLike.comment_id == comment_id, CommentLike.user_id == user.id)
        .one_or_none()
    )
    if existing is None:
        db.add(CommentLike(comment_id=comment_id, user_id=user.id))
        db.commit()

    like_count = db.query(CommentLike).filter(CommentLike.comment_id == comment_id).count()
    return LikeStatusOut(liked=True, like_count=like_count)


@comments_router.delete("/{comment_id}/like", response_model=LikeStatusOut)
def unlike_comment(
    comment_id: int,
    db: Session = Depends(get_db),
    user: User = Depends(require_user),
) -> LikeStatusOut:
    comment = db.get(Comment, comment_id)
    if comment is None:
        raise HTTPException(status_code=404, detail="Comment not found")

    db.query(CommentLike).filter(
        CommentLike.comment_id == comment_id,
        CommentLike.user_id == user.id,
    ).delete()
    db.commit()
    like_count = db.query(CommentLike).filter(CommentLike.comment_id == comment_id).count()
    return LikeStatusOut(liked=False, like_count=like_count)


bible_router = APIRouter(prefix="/bible", tags=["bible"])


@bible_router.get("/versions", response_model=list[BibleVersionOut])
def bible_versions() -> list[BibleVersionOut]:
    versions = get_bible_client().get_versions()
    return [BibleVersionOut(version_id=v["version_id"], name=v["name"]) for v in versions]


@bible_router.get("/verse", response_model=BibleVerseOut)
def bible_verse(
    book: str = Query(...),
    chapter: int = Query(..., ge=1),
    start_verse: int = Query(..., ge=1),
    end_verse: int = Query(..., ge=1),
    version_id: str = Query(default="niv"),
) -> BibleVerseOut:
    if end_verse < start_verse:
        raise HTTPException(status_code=400, detail="end_verse must be >= start_verse")

    reference = (
        f"{book} {chapter}:{start_verse}"
        if start_verse == end_verse
        else f"{book} {chapter}:{start_verse}-{end_verse}"
    )
    try:
        text = get_bible_client().get_verse_text(
            book=book,
            chapter=chapter,
            start_verse=start_verse,
            end_verse=end_verse,
            version_id=version_id,
        )
    except Exception:
        # Invalid/missing Bible Brain credentials must not break browsing.
        text = f"[{reference} unavailable]"
    return BibleVerseOut(
        reference=reference,
        version_id=version_id.lower(),
        text=text,
        verse_id=iq_verse_id(book, chapter, start_verse),
    )


@bible_router.get("/audio", response_model=BibleAudioOut)
def bible_audio(
    book: str = Query(...),
    chapter: int = Query(..., ge=1),
    version_id: str = Query(default="niv"),
) -> BibleAudioOut:
    try:
        audio_url = get_bible_client().get_chapter_audio_url(
            book=book,
            chapter=chapter,
            version_id=version_id,
        )
    except Exception:
        audio_url = ""
    return BibleAudioOut(
        reference=f"{book} {chapter}",
        version_id=version_id.lower(),
        audio_url=audio_url,
        book_id=dbp_book_id(book),
        chapter_id=chapter,
    )
