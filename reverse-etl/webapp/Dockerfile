FROM python:3.12-slim

# Install system dependencies for mssql-python
RUN apt-get update && \
    apt-get install -y --no-install-recommends libltdl7 libkrb5-3 libgssapi-krb5-2 libcurl4 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
