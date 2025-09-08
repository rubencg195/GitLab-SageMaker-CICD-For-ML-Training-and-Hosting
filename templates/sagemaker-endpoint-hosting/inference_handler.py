#!/usr/bin/env python3
"""
XGBoost Inference Handler for SageMaker
This script handles XGBoost model inference for deployed endpoints using AWS pre-built containers.
"""

import json
import logging
import os
import pickle
import numpy as np
import pandas as pd
import xgboost as xgb

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def model_fn(model_dir: str):
    """
    Load the XGBoost model from the model directory.
    
    Args:
        model_dir: Directory containing the model files
        
    Returns:
        Loaded XGBoost model
    """
    try:
        # Look for XGBoost model files
        model_files = [f for f in os.listdir(model_dir) if f.endswith(('.pkl', '.pickle', '.json', '.txt'))]
        logger.info(f"Found model files: {model_files}")
        
        # Try to load XGBoost model in different formats
        for model_file in model_files:
            model_path = os.path.join(model_dir, model_file)
            
            try:
                if model_file.endswith('.json'):
                    # XGBoost JSON format
                    model = xgb.Booster()
                    model.load_model(model_path)
                    logger.info(f"Loaded XGBoost model from JSON: {model_file}")
                    return model
                elif model_file.endswith(('.pkl', '.pickle')):
                    # Pickle format
                    with open(model_path, 'rb') as f:
                        model = pickle.load(f)
                    logger.info(f"Loaded XGBoost model from pickle: {model_file}")
                    return model
                elif model_file.endswith('.txt'):
                    # XGBoost text format
                    model = xgb.Booster()
                    model.load_model(model_path)
                    logger.info(f"Loaded XGBoost model from text: {model_file}")
                    return model
            except Exception as e:
                logger.warning(f"Failed to load model from {model_file}: {e}")
                continue
        
        # If no specific model file found, try default names
        default_paths = [
            os.path.join(model_dir, 'xgboost-model.json'),
            os.path.join(model_dir, 'model.json'),
            os.path.join(model_dir, 'xgboost-model.pkl'),
            os.path.join(model_dir, 'model.pkl')
        ]
        
        for model_path in default_paths:
            if os.path.exists(model_path):
                try:
                    if model_path.endswith('.json'):
                        model = xgb.Booster()
                        model.load_model(model_path)
                        logger.info(f"Loaded XGBoost model from: {model_path}")
                        return model
                    elif model_path.endswith('.pkl'):
                        with open(model_path, 'rb') as f:
                            model = pickle.load(f)
                        logger.info(f"Loaded XGBoost model from: {model_path}")
                        return model
                except Exception as e:
                    logger.warning(f"Failed to load model from {model_path}: {e}")
                    continue
        
        raise FileNotFoundError("No valid XGBoost model file found in model directory")
        
    except Exception as e:
        logger.error(f"Failed to load XGBoost model: {str(e)}")
        raise

def input_fn(request_body: str, content_type: str):
    """
    Parse input data from the request for XGBoost inference.
    
    Args:
        request_body: Raw request body
        content_type: Content type of the request
        
    Returns:
        Parsed input data as DMatrix for XGBoost
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
                        input_array = np.array(instances)
                    elif isinstance(instances[0], dict):
                        # List of dictionaries format
                        input_array = pd.DataFrame(instances).values
                    else:
                        # Single instance format
                        input_array = np.array([instances])
                    return xgb.DMatrix(input_array)
                else:
                    raise ValueError("Invalid instances format")
            elif 'features' in data:
                # Single instance format
                features = data['features']
                if isinstance(features, list):
                    input_array = np.array([features])
                    return xgb.DMatrix(input_array)
                else:
                    raise ValueError("Invalid features format")
            else:
                # Direct array format
                if isinstance(data, list):
                    input_array = np.array(data)
                    return xgb.DMatrix(input_array)
                else:
                    raise ValueError("Invalid input format")
        
        elif content_type == 'text/csv':
            # Parse CSV input
            from io import StringIO
            df = pd.read_csv(StringIO(request_body), header=None)
            input_array = df.values
            return xgb.DMatrix(input_array)
        
        else:
            raise ValueError(f"Unsupported content type: {content_type}")
            
    except Exception as e:
        logger.error(f"Failed to parse input: {str(e)}")
        raise

def predict_fn(input_data, model):
    """
    Make predictions using the XGBoost model.
    
    Args:
        input_data: Parsed input data as DMatrix
        model: Loaded XGBoost model
        
    Returns:
        Model predictions
    """
    try:
        # Make predictions
        predictions = model.predict(input_data)
        
        # Handle different prediction types
        if len(predictions.shape) == 1:
            # Single output
            predictions = predictions.reshape(-1, 1)
        
        # Get prediction probabilities if available (for classification)
        try:
            # Try to get prediction probabilities for classification
            if hasattr(model, 'get_booster'):
                booster = model.get_booster()
                # Check if it's a classification model
                if 'softmax' in str(booster.get_dump()[0]) or 'multi:softprob' in str(booster.get_dump()[0]):
                    probabilities = model.predict(input_data, output_margin=False)
                    return {
                        'predictions': predictions.tolist(),
                        'probabilities': probabilities.tolist()
                    }
        except Exception as e:
            logger.debug(f"Could not get probabilities: {e}")
        
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
            if isinstance(predictions[0], list):
                # Multi-dimensional predictions
                return '\n'.join([','.join(map(str, pred)) for pred in predictions])
            else:
                # Single-dimensional predictions
                return '\n'.join(map(str, predictions))
        else:
            raise ValueError(f"Unsupported output content type: {content_type}")
            
    except Exception as e:
        logger.error(f"Failed to format output: {str(e)}")
        raise

def health_check():
    """
    Health check function for the XGBoost endpoint.
    
    Returns:
        Health status
    """
    try:
        # Check if model directory exists
        model_dir = os.environ.get('SM_MODEL_DIR', '/opt/ml/model')
        if not os.path.exists(model_dir):
            return {'status': 'unhealthy', 'reason': 'Model directory not found'}
        
        # Check if model files exist
        model_files = [f for f in os.listdir(model_dir) if f.endswith(('.pkl', '.pickle', '.json', '.txt'))]
        if not model_files:
            return {'status': 'unhealthy', 'reason': 'No XGBoost model files found'}
        
        # Try to load the model
        try:
            model = model_fn(model_dir)
            return {
                'status': 'healthy', 
                'model_loaded': True,
                'model_type': 'XGBoost',
                'model_files': model_files
            }
        except Exception as e:
            return {'status': 'unhealthy', 'reason': f'Failed to load XGBoost model: {str(e)}'}
            
    except Exception as e:
        return {'status': 'unhealthy', 'reason': f'Health check failed: {str(e)}'}

# Example usage for testing
if __name__ == "__main__":
    # Test the inference functions
    model_dir = "/opt/ml/model"
    
    try:
        # Load model
        model = model_fn(model_dir)
        
        # Test input parsing
        test_input = '{"instances": [[1, 2, 3, 4, 5], [6, 7, 8, 9, 10]]}'
        input_data = input_fn(test_input, 'application/json')
        
        # Make predictions
        predictions = predict_fn(input_data, model)
        
        # Format output
        output = output_fn(predictions, 'application/json')
        
        print("XGBoost inference test completed successfully!")
        print(f"Input data shape: {input_data.num_row()}x{input_data.num_col()}")
        print(f"Predictions: {predictions}")
        print(f"Output: {output}")
        
    except Exception as e:
        print(f"Test failed: {e}")
        # Create a dummy model for testing if no real model exists
        print("Creating dummy XGBoost model for testing...")
        
        # Create dummy data
        X = np.random.rand(100, 5)
        y = np.random.rand(100)
        
        # Train a simple XGBoost model
        dtrain = xgb.DMatrix(X, label=y)
        params = {
            'objective': 'reg:squarederror',
            'max_depth': 3,
            'eta': 0.1,
            'n_estimators': 10
        }
        model = xgb.train(params, dtrain, num_boost_round=10)
        
        # Test with dummy model
        test_input = '{"instances": [[1, 2, 3, 4, 5], [6, 7, 8, 9, 10]]}'
        input_data = input_fn(test_input, 'application/json')
        predictions = predict_fn(input_data, model)
        output = output_fn(predictions, 'application/json')
        
        print("Dummy XGBoost model test completed successfully!")
        print(f"Predictions: {predictions}")
        print(f"Output: {output}")