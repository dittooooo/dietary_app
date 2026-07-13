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

COPY workspace/src/nutritionist_agent/requirements.txt /tmp/nutritionist_agent_requirements.txt
RUN pip install --upgrade pip setuptools wheel \
    && pip install -r /tmp/nutritionist_agent_requirements.txt

CMD ["bash"]
