FROM python:3.12.6-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /tmp

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY graphrag-local-ollama/requirements.txt /tmp/requirements.txt
RUN pip install --upgrade pip setuptools wheel \
    && pip install -r /tmp/requirements.txt

COPY workspace/src/nutrition_agent_v2/requirements.txt /tmp/nutrition_agent_v2_requirements.txt
RUN pip install -r /tmp/nutrition_agent_v2_requirements.txt

COPY graphrag-local-ollama /opt/graphrag-local-ollama
RUN pip install -e /opt/graphrag-local-ollama

CMD ["bash"]
