FROM pytorch/pytorch:1.12.1-cuda11.3-cudnn8-runtime

# Set working directory
WORKDIR /opt/ml/code

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    nginx \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy inference code
COPY . .

# Set environment variables
ENV PYTHONPATH=/opt/ml/code
ENV PYTHONUNBUFFERED=TRUE
ENV MODEL_DIR=/opt/ml/model

# Create nginx configuration
RUN echo 'server { \
    listen 8080; \
    server_name localhost; \
    location / { \
        proxy_pass http://127.0.0.1:8000; \
        proxy_set_header Host $host; \
        proxy_set_header X-Real-IP $remote_addr; \
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; \
        proxy_set_header X-Forwarded-Proto $scheme; \
    } \
}' > /etc/nginx/sites-available/default

# Expose port
EXPOSE 8080

# Start nginx and gunicorn
CMD service nginx start && gunicorn --bind 0.0.0.0:8000 --workers 1 --timeout 60 inference_handler:app
