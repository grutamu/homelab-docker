FROM python:3.15-alpine
RUN pip install --no-cache-dir docker requests
COPY sync.py /app/sync.py
CMD ["python", "-u", "/app/sync.py"]
