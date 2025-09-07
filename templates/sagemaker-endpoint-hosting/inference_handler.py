#!/usr/bin/env python3
"""
SageMaker Endpoint Hosting Template
This is a template for creating SageMaker endpoint hosting with inference handlers.
Replace the placeholder code with your actual inference logic.
"""

import json
import logging
import os
import pickle
from pathlib import Path

import torch
import torch.nn as nn
import numpy as np
import pandas as pd
from flask import Flask, request, jsonify
import boto3
import sagemaker
from sagemaker.pytorch import PyTorchModel


# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global variables for model and app
model = None
app = Flask(__name__)


class SimpleModel(nn.Module):
    """Simple neural network model - replace with your actual model"""
    
    def __init__(self, input_size, hidden_size, num_classes):
        super(SimpleModel, self).__init__()
        self.fc1 = nn.Linear(input_size, hidden_size)
        self.fc2 = nn.Linear(hidden_size, hidden_size)
        self.fc3 = nn.Linear(hidden_size, num_classes)
        self.relu = nn.ReLU()
        self.dropout = nn.Dropout(0.2)
    
    def forward(self, x):
        x = self.relu(self.fc1(x))
        x = self.dropout(x)
        x = self.relu(self.fc2(x))
        x = self.dropout(x)
        x = self.fc3(x)
        return x


def model_fn(model_dir):
    """
    Load the model for inference
    This function is called by SageMaker when the endpoint starts
    """
    global model
    
    logger.info(f"Loading model from {model_dir}")
    
    # Load model configuration
    config_path = os.path.join(model_dir, 'model_config.json')
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            config = json.load(f)
    else:
        # Default configuration
        config = {
            'input_size': 10,
            'hidden_size': 64,
            'num_classes': 3
        }
    
    # Create model instance
    model = SimpleModel(
        input_size=config['input_size'],
        hidden_size=config['hidden_size'],
        num_classes=config['num_classes']
    )
    
    # Load model weights
    model_path = os.path.join(model_dir, 'model.pth')
    if os.path.exists(model_path):
        model.load_state_dict(torch.load(model_path, map_location='cpu'))
        logger.info("Model weights loaded successfully")
    else:
        logger.warning(f"Model weights not found at {model_path}")
    
    model.eval()
    return model


def input_fn(request_body, request_content_type):
    """
    Parse input data
    This function is called by SageMaker to parse the input data
    """
    logger.info(f"Received content type: {request_content_type}")
    
    if request_content_type == 'application/json':
        data = json.loads(request_body)
        
        # Handle different input formats
        if 'instances' in data:
            # Batch prediction format
            instances = data['instances']
        elif 'data' in data:
            # Single prediction format
            instances = [data['data']]
        else:
            # Direct array format
            instances = data if isinstance(data, list) else [data]
        
        # Convert to numpy array
        X = np.array(instances, dtype=np.float32)
        logger.info(f"Parsed input shape: {X.shape}")
        return X
    
    elif request_content_type == 'text/csv':
        # Handle CSV input
        from io import StringIO
        df = pd.read_csv(StringIO(request_body), header=None)
        X = df.values.astype(np.float32)
        logger.info(f"Parsed CSV input shape: {X.shape}")
        return X
    
    else:
        raise ValueError(f"Unsupported content type: {request_content_type}")


def predict_fn(input_data, model):
    """
    Make predictions
    This function is called by SageMaker to make predictions
    """
    logger.info(f"Making predictions for input shape: {input_data.shape}")
    
    with torch.no_grad():
        # Convert to tensor
        input_tensor = torch.tensor(input_data, dtype=torch.float32)
        
        # Make prediction
        outputs = model(input_tensor)
        predictions = torch.softmax(outputs, dim=1)
        
        # Convert to numpy
        predictions = predictions.numpy()
        
        logger.info(f"Generated predictions shape: {predictions.shape}")
        return predictions


def output_fn(prediction, content_type):
    """
    Format output data
    This function is called by SageMaker to format the output
    """
    logger.info(f"Formatting output for content type: {content_type}")
    
    if content_type == 'application/json':
        # Format as JSON
        if len(prediction.shape) == 1:
            # Single prediction
            result = {
                'prediction': prediction.tolist(),
                'predicted_class': int(np.argmax(prediction)),
                'confidence': float(np.max(prediction))
            }
        else:
            # Batch predictions
            result = {
                'predictions': prediction.tolist(),
                'predicted_classes': np.argmax(prediction, axis=1).tolist(),
                'confidences': np.max(prediction, axis=1).tolist()
            }
        
        return json.dumps(result)
    
    elif content_type == 'text/csv':
        # Format as CSV
        import io
        output = io.StringIO()
        pd.DataFrame(prediction).to_csv(output, index=False, header=False)
        return output.getvalue()
    
    else:
        raise ValueError(f"Unsupported content type: {content_type}")


# Flask app for local testing
@app.route('/ping', methods=['GET'])
def ping():
    """Health check endpoint"""
    return jsonify({'status': 'healthy'}), 200


@app.route('/invocations', methods=['POST'])
def invocations():
    """Prediction endpoint for local testing"""
    try:
        # Get input data
        input_data = input_fn(request.data, request.content_type)
        
        # Make prediction
        prediction = predict_fn(input_data, model)
        
        # Format output
        output = output_fn(prediction, request.content_type)
        
        return output, 200, {'Content-Type': request.content_type}
    
    except Exception as e:
        logger.error(f"Error during prediction: {str(e)}")
        return jsonify({'error': str(e)}), 500


def main():
    """Main function for local testing"""
    global model
    
    # Load model
    model_dir = os.environ.get('MODEL_DIR', '/opt/ml/model')
    model = model_fn(model_dir)
    
    # Run Flask app
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=True)


if __name__ == '__main__':
    main()
