from typing import Annotated
from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from os import environ as env
from sqlalchemy import create_engine, Column, Integer, String, Boolean
from sqlalchemy.orm import Session, sessionmaker, declarative_base, Session
from pydantic import BaseModel

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)

# Database connection
DATABASE_URL = env.get(
    "DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/todo"
)
engine = create_engine(DATABASE_URL)
Base = declarative_base()
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


# Create the database table
class TodoModel(Base):
    __tablename__ = "todos"
    todo_id = Column(Integer, primary_key=True, index=True)
    title = Column(String, index=True)
    description = Column(String, index=True)
    completed = Column(Boolean, default=False)


Base.metadata.create_all(bind=engine)


# Dependency to get the database session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


db_dependency = Annotated[Session, Depends(get_db)]


# Create the Todo schema
class Todo(BaseModel):
    title: str
    description: str | None = None
    completed: bool = False

    model_config = {"from_attributes": True}


# Simple route to test the application
@app.get("/todos/")
def read_todos(session: db_dependency) -> list[Todo]:
    todos = session.query(TodoModel).all()
    return [Todo.model_validate(todo) for todo in todos]


@app.post("/todos/", status_code=201)
def create_todo(todo: Todo, session: db_dependency) -> Todo:
    try:
        todo_model = TodoModel(**todo.model_dump())
        session.add(todo_model)
        session.commit()
        session.refresh(todo_model)
    except Exception as e:
        session.rollback()
        raise e
    return Todo.model_validate(todo_model)
