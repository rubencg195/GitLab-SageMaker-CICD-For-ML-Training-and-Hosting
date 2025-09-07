#!/usr/bin/env python3
"""
Inference Script for SageMaker
This script handles model inference for deployed endpoints.
"""

import json
import logging
import os
import joblib
import numpy as np
import pandas as pd

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def model_fn(model_dir: str):
    """
    Load the model from the model directory.
    
    Args:
        model_dir: Directory containing the model files
        
    Returns:
        Loaded model
    """
    try:
        model_path = os.path.join(model_dir, 'model.joblib')
        model = joblib.load(model_path)
        logger.info("Model loaded successfully")
        return model
        
    except Exception as e:
        logger.error(f"Failed to load model: {str(e)}")
        raise

def input_fn(request_body: str, content_type: str):
    """
    Parse input data from the request.
    
    Args:
        request_body: Raw request body
        content_type: Content type of the request
        
    Returns:
        Parsed input data
    """
    try:
        if content_type == 'application/json':
            # Parse JSON input
            data = json.loads(request_body)
            
            # Handle different input formats
            if 'instances' in data:
                # Batch prediction format
                instances = data['instances']
                if isinstance(instances, list) and len(instances) > 0:
                    if isinstance(instances[0], list):
                        # List of lists format
                        return np.array(instances)
                    elif isinstance(instances[0], dict):
                        # List of dictionaries format
                        return pd.DataFrame(instances).values
                    else:
                        # Single instance format
                        return np.array([instances])
                else:
                    raise ValueError("Invalid instances format")
            elif 'features' in data:
                # Single instance format
                features = data['features']
                if isinstance(features, list):
                    return np.array([features])
                else:
                    raise ValueError("Invalid features format")
            else:
                # Direct array format
                if isinstance(data, list):
                    return np.array(data)
                else:
                    raise ValueError("Invalid input format")
        
        elif content_type == 'text/csv':
            # Parse CSV input
            from io import StringIO
            df = pd.read_csv(StringIO(request_body), header=None)
            return df.values
        
        else:
            raise ValueError(f"Unsupported content type: {content_type}")
            
    except Exception as e:
        logger.error(f"Failed to parse input: {str(e)}")
        raise

def predict_fn(input_data, model):
    """
    Make predictions using the model.
    
    Args:
        input_data: Parsed input data
        model: Loaded model
        
    Returns:
        Model predictions
    """
    try:
        # Make predictions
        predictions = model.predict(input_data)
        
        # Get prediction probabilities if available
        if hasattr(model, 'predict_proba'):
            probabilities = model.predict_proba(input_data)
            return {
                'predictions': predictions.tolist(),
                'probabilities': probabilities.tolist()
            }
        else:
            return {
                'predictions': predictions.tolist()
            }
            
    except Exception as e:
        logger.error(f"Failed to make predictions: {str(e)}")
        raise

def output_fn(prediction, content_type: str):
    """
    Format the prediction output.
    
    Args:
        prediction: Model prediction
        content_type: Desired content type for output
        
    Returns:
        Formatted output
    """
    try:
        if content_type == 'application/json':
            return json.dumps(prediction)
        elif content_type == 'text/csv':
            # Convert predictions to CSV format
            predictions = prediction['predictions']
            return '\n'.join(map(str, predictions))
        else:
            raise ValueError(f"Unsupported output content type: {content_type}")
            
    except Exception as e:
        logger.error(f"Failed to format output: {str(e)}")
        raise

def health_check():
    """
    Health check function for the endpoint.
    
    Returns:
        Health status
    """
    try:
        # Check if model directory exists
        model_dir = os.environ.get('SM_MODEL_DIR', '/opt/ml/model')
        if not os.path.exists(model_dir):
            return {'status': 'unhealthy', 'reason': 'Model directory not found'}
        
        # Check if model file exists
        model_path = os.path.join(model_dir, 'model.joblib')
        if not os.path.exists(model_path):
            return {'status': 'unhealthy', 'reason': 'Model file not found'}
        
        # Try to load the model
        try:
            model = model_fn(model_dir)
            return {'status': 'healthy', 'model_loaded': True}
        except Exception as e:
            return {'status': 'unhealthy', 'reason': f'Failed to load model: {str(e)}'}
            
    except Exception as e:
        return {'status': 'unhealthy', 'reason': f'Health check failed: {str(e)}'}

# Example usage for testing
if __name__ == "__main__":
    # Test the inference functions
    model_dir = "/opt/ml/model"
    
    # Load model
    model = model_fn(model_dir)
    
    # Test input parsing
    test_input = '{"instances": [[1, 2, 3, 4, 5], [6, 7, 8, 9, 10]]}'
    input_data = input_fn(test_input, 'application/json')
    
    # Make predictions
    predictions = predict_fn(input_data, model)
    
    # Format output
    output = output_fn(predictions, 'application/json')
    
    print("Test completed successfully!")
    print(f"Input data shape: {input_data.shape}")
    print(f"Predictions: {predictions}")
    print(f"Output: {output}")
