FROM python:3.12-slim
WORKDIR /app
COPY MAF/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt
COPY MAF ./MAF
COPY companion/prompts ./companion/prompts
CMD ["python", "-m", "uvicorn", "MAF.app:app", "--host", "0.0.0.0", "--port", "3001"]
