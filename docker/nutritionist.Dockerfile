FROM python:3.12-slim
WORKDIR /app/graphRag
COPY graphRag/nutritionist_agent/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt
COPY graphRag/nutritionist_agent ./nutritionist_agent
CMD ["python", "-m", "uvicorn", "nutritionist_agent.app:app", "--host", "0.0.0.0", "--port", "8000"]
