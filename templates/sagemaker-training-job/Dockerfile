FROM pytorch/pytorch:1.12.1-cuda11.3-cudnn8-runtime

# Set working directory
WORKDIR /opt/ml/code

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy training code
COPY . .

# Set environment variables
ENV PYTHONPATH=/opt/ml/code
ENV PYTHONUNBUFFERED=TRUE

# Set the default command
ENTRYPOINT ["python", "training_script.py"]
