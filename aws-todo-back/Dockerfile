FROM python:3.10-slim

WORKDIR /app

COPY . /app
RUN apt-get update && apt-get install -y gcc libpq-dev
RUN pip install -r requirements.txt