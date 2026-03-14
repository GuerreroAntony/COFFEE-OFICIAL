from pydantic import BaseModel, Field


class DeleteAccountRequest(BaseModel):
    confirm: bool


class SupportContactRequest(BaseModel):
    subject: str = Field(min_length=1, max_length=255)
    message: str = Field(min_length=1, max_length=5000)
