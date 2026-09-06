FROM python:3.12-slim
WORKDIR /app/graphRag/workspace
COPY graphRag/workspace/src/nutritionist_agent/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt
COPY graphRag/workspace/src/nutritionist_agent ./src/nutritionist_agent
CMD ["python", "-m", "uvicorn", "src.nutritionist_agent.app:app", "--host", "0.0.0.0", "--port", "8000"]
