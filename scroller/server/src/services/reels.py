from __future__ import annotations

from sqlalchemy import func
from sqlalchemy.orm import Session, joinedload

from src.models import Comment, CommentLike, Reel, ReelLike, User
from src.schemas import CommentOut, ReelFeedOut, ReelOut, UserOut


def _user_out(user: User) -> UserOut:
    return UserOut(
        id=user.id,
        display_name=user.display_name,
        email=user.email,
        email_verified=user.email_verified,
        avatar_url=user.avatar_url,
    )


def _batch_reel_stats(
    db: Session,
    reel_ids: list[int],
    user_id: int | None,
) -> tuple[dict[int, int], dict[int, int], set[int]]:
    if not reel_ids:
        return {}, {}, set()

    like_counts = {
        reel_id: int(count)
        for reel_id, count in db.query(ReelLike.reel_id, func.count(ReelLike.id))
        .filter(ReelLike.reel_id.in_(reel_ids))
        .group_by(ReelLike.reel_id)
        .all()
    }
    comment_counts = {
        reel_id: int(count)
        for reel_id, count in db.query(Comment.reel_id, func.count(Comment.id))
        .filter(Comment.reel_id.in_(reel_ids))
        .group_by(Comment.reel_id)
        .all()
    }
    liked_by_me: set[int] = set()
    if user_id is not None:
        liked_by_me = {
            reel_id
            for (reel_id,) in db.query(ReelLike.reel_id)
            .filter(ReelLike.reel_id.in_(reel_ids), ReelLike.user_id == user_id)
            .all()
        }
    return like_counts, comment_counts, liked_by_me


def reel_to_out(
    reel: Reel,
    user: User | None,
    db: Session,
    *,
    like_count: int | None = None,
    comment_count: int | None = None,
    liked_by_me: bool | None = None,
) -> ReelOut:
    if like_count is None:
        like_count = db.query(func.count(ReelLike.id)).filter(ReelLike.reel_id == reel.id).scalar() or 0
    if comment_count is None:
        comment_count = db.query(func.count(Comment.id)).filter(Comment.reel_id == reel.id).scalar() or 0
    if liked_by_me is None:
        liked_by_me = False
        if user is not None:
            liked_by_me = (
                db.query(ReelLike.id)
                .filter(ReelLike.reel_id == reel.id, ReelLike.user_id == user.id)
                .first()
                is not None
            )
    return ReelOut(
        id=reel.id,
        reference=reel.reference,
        book=reel.book,
        chapter=reel.chapter,
        start_verse=reel.start_verse,
        end_verse=reel.end_verse,
        slug=reel.slug,
        image_url=reel.image_url,
        iq_book_id=reel.iq_book_id,
        like_count=like_count,
        comment_count=comment_count,
        liked_by_me=liked_by_me,
    )


def _reels_to_out(db: Session, user: User | None, reels: list[Reel]) -> list[ReelOut]:
    reel_ids = [reel.id for reel in reels]
    user_id = user.id if user is not None else None
    like_counts, comment_counts, liked_set = _batch_reel_stats(db, reel_ids, user_id)
    return [
        reel_to_out(
            reel,
            user,
            db,
            like_count=like_counts.get(reel.id, 0),
            comment_count=comment_counts.get(reel.id, 0),
            liked_by_me=reel.id in liked_set,
        )
        for reel in reels
    ]


def _has_reel_before(db: Session, reel_id: int) -> bool:
    return db.query(Reel.id).filter(Reel.id < reel_id).first() is not None


def get_feed(
    db: Session,
    user: User | None,
    *,
    cursor: int | None,
    before_id: int | None,
    limit: int,
    from_id: int | None = None,
    book: str | None = None,
) -> ReelFeedOut:
    if before_id is not None:
        query = db.query(Reel).filter(Reel.id < before_id).order_by(Reel.id.desc())
        reels = query.limit(limit + 1).all()
        has_more = len(reels) > limit
        page = list(reversed(reels[:limit]))
        next_cursor = page[-1].id if page else None
        prev_cursor = page[0].id if page and has_more else None
        return ReelFeedOut(
            items=_reels_to_out(db, user, page),
            next_cursor=next_cursor,
            prev_cursor=prev_cursor,
        )

    query = db.query(Reel).order_by(Reel.id.asc())
    if book is not None:
        first = (
            db.query(Reel)
            .filter(Reel.book == book.strip())
            .order_by(Reel.id.asc())
            .first()
        )
        if first is None:
            return ReelFeedOut(items=[], next_cursor=None, prev_cursor=None)
        query = query.filter(Reel.id >= first.id)
    elif from_id is not None:
        query = query.filter(Reel.id >= from_id)
    if cursor is not None:
        query = query.filter(Reel.id > cursor)

    reels = query.limit(limit + 1).all()
    has_more = len(reels) > limit
    page = reels[:limit]
    next_cursor = page[-1].id if has_more and page else None
    prev_cursor = page[0].id if page and _has_reel_before(db, page[0].id) else None
    return ReelFeedOut(
        items=_reels_to_out(db, user, page),
        next_cursor=next_cursor,
        prev_cursor=prev_cursor,
    )


def list_books(db: Session) -> list[str]:
    rows = (
        db.query(Reel.book, Reel.iq_book_id)
        .distinct()
        .order_by(Reel.iq_book_id.asc(), Reel.book.asc())
        .all()
    )
    seen: set[str] = set()
    books: list[str] = []
    for book, _iq in rows:
        if book in seen:
            continue
        seen.add(book)
        books.append(book)
    return books


def comment_to_out(comment: Comment, user: User | None, db: Session) -> CommentOut:
    like_count = db.query(func.count(CommentLike.id)).filter(CommentLike.comment_id == comment.id).scalar() or 0
    liked_by_me = False
    if user is not None:
        liked_by_me = (
            db.query(CommentLike.id)
            .filter(CommentLike.comment_id == comment.id, CommentLike.user_id == user.id)
            .first()
            is not None
        )
    return CommentOut(
        id=comment.id,
        reel_id=comment.reel_id,
        parent_id=comment.parent_id,
        body=comment.body,
        like_count=like_count,
        liked_by_me=liked_by_me,
        created_at=comment.created_at,
        author=_user_out(comment.author),
    )


def list_comments(db: Session, user: User | None, reel_id: int) -> list[CommentOut]:
    comments = (
        db.query(Comment)
        .options(joinedload(Comment.author))
        .filter(Comment.reel_id == reel_id)
        .order_by(Comment.created_at.asc())
        .all()
    )
    return [comment_to_out(comment, user, db) for comment in comments]
