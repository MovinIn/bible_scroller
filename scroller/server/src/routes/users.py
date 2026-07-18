from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from src.database import get_db
from src.deps import require_user
from src.models import User
from src.schemas import UserOut

router = APIRouter(prefix="/users", tags=["users"])


class UserUpdate(BaseModel):
    display_name: str = Field(min_length=2, max_length=64)


def _to_out(user: User) -> UserOut:
    return UserOut(
        id=user.id,
        display_name=user.display_name,
        email=user.email,
        email_verified=user.email_verified,
        avatar_url=user.avatar_url,
    )


@router.get("/me", response_model=UserOut)
def get_me(user: User = Depends(require_user)) -> UserOut:
    return _to_out(user)


@router.patch("/me", response_model=UserOut)
def update_me(
    payload: UserUpdate,
    db: Session = Depends(get_db),
    user: User = Depends(require_user),
) -> UserOut:
    user.display_name = payload.display_name.strip()
    db.commit()
    db.refresh(user)
    return _to_out(user)
