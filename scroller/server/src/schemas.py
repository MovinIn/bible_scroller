from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class UserOut(BaseModel):
    id: str
    display_name: str
    email: str | None = None
    email_verified: bool = False
    avatar_url: str | None = None


class ReelOut(BaseModel):
    id: int
    reference: str
    book: str
    chapter: int
    start_verse: int
    end_verse: int
    slug: str
    image_url: str
    iq_book_id: str
    like_count: int
    comment_count: int
    liked_by_me: bool


class ReelFeedOut(BaseModel):
    items: list[ReelOut]
    next_cursor: int | None
    prev_cursor: int | None = None


class CommentOut(BaseModel):
    id: int
    reel_id: int
    parent_id: int | None = None
    body: str
    like_count: int
    liked_by_me: bool
    created_at: datetime
    author: UserOut


class CommentCreate(BaseModel):
    body: str = Field(min_length=1, max_length=2000)
    parent_id: int | None = None


class LikeStatusOut(BaseModel):
    liked: bool
    like_count: int


class BibleVersionOut(BaseModel):
    version_id: str
    name: str


class BibleVerseOut(BaseModel):
    reference: str
    version_id: str
    text: str
    verse_id: str


class BibleAudioOut(BaseModel):
    reference: str
    version_id: str
    audio_url: str
    book_id: str
    chapter_id: int
