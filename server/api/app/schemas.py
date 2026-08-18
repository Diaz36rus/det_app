from pydantic import BaseModel, EmailStr, Field


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class LoginRequest(BaseModel):
    """login — email или телефон; email оставлен для совместимости."""
    password: str = Field(min_length=6)
    login: str | None = Field(default=None, min_length=3, max_length=255)
    email: EmailStr | None = None


class RefreshRequest(BaseModel):
    refresh_token: str


class PermissionOut(BaseModel):
    id: int
    code: str
    title: str
    group_name: str

    model_config = {"from_attributes": True}


class RoleOut(BaseModel):
    id: int
    name: str
    is_system: bool
    company_id: int | None
    permission_codes: list[str] = []

    model_config = {"from_attributes": True}


class RoleCreate(BaseModel):
    name: str = Field(min_length=2, max_length=120)
    permission_codes: list[str] = []


class RoleUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=120)
    permission_codes: list[str] | None = None


class BranchOut(BaseModel):
    id: int
    name: str
    company_id: int
    is_active: bool

    model_config = {"from_attributes": True}


class BranchCreate(BaseModel):
    name: str = Field(min_length=2, max_length=200)


class CompanyOut(BaseModel):
    id: int
    name: str
    slug: str
    is_active: bool

    model_config = {"from_attributes": True}


class CompanyCreate(BaseModel):
    name: str = Field(min_length=2, max_length=200)
    slug: str = Field(min_length=2, max_length=80)
    branch_name: str = Field(default="Основной филиал", min_length=2, max_length=200)


class UserOut(BaseModel):
    id: int
    email: EmailStr
    phone: str | None = None
    full_name: str
    is_active: bool
    is_platform_admin: bool
    company_id: int | None
    roles: list[str] = []
    branch_ids: list[int] = []
    permissions: list[str] = []


class UserCreate(BaseModel):
    email: EmailStr
    password: str = Field(min_length=6)
    full_name: str = Field(default="", max_length=200)
    phone: str | None = Field(default=None, max_length=32)
    role_ids: list[int] = []
    branch_ids: list[int] = []
