# Kiln detector for Fargate ARM64 (prompt 38). Build context: the zip made in
# AWS/docs/local-verification.md ("M0"), which adds model/ from Model/scripts unchanged.
FROM public.ecr.aws/docker/library/python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1 \
    YOLO_CONFIG_DIR=/tmp/ultralytics MPLCONFIGDIR=/tmp/matplotlib

# opencv-python (an ultralytics dependency) needs libGL and glib at import time.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libgl1 libglib2.0-0 \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /app/requirements.txt
RUN pip install --index-url https://download.pytorch.org/whl/cpu torch==2.14.1 torchvision==0.29.1 \
 && pip install --prefer-binary -r /app/requirements.txt

COPY entrypoint.py /app/entrypoint.py
COPY model/ /app/model/

RUN useradd --create-home --uid 10001 detector
USER detector
WORKDIR /tmp

ENTRYPOINT ["python", "/app/entrypoint.py"]
