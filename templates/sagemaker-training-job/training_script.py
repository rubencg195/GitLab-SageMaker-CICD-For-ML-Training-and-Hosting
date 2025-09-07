#!/usr/bin/env python3
"""
Sample Training Script for SageMaker
This script demonstrates a basic machine learning training pipeline.
"""

import argparse
import json
import logging
import os
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, classification_report
import joblib

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def load_data(data_path: str) -> tuple:
    """
    Load training and validation data.
    
    Args:
        data_path: Path to the data directory
        
    Returns:
        Tuple of (X_train, X_val, y_train, y_val)
    """
    try:
        # Load training data
        train_data_path = os.path.join(data_path, 'train.csv')
        train_df = pd.read_csv(train_data_path)
        
        # Load validation data
        val_data_path = os.path.join(data_path, 'validation.csv')
        val_df = pd.read_csv(val_data_path)
        
        # Separate features and target
        X_train = train_df.drop('target', axis=1)
        y_train = train_df['target']
        
        X_val = val_df.drop('target', axis=1)
        y_val = val_df['target']
        
        logger.info(f"Training data shape: {X_train.shape}")
        logger.info(f"Validation data shape: {X_val.shape}")
        
        return X_train, X_val, y_train, y_val
        
    except Exception as e:
        logger.error(f"Failed to load data: {str(e)}")
        raise

def train_model(X_train, y_train, hyperparameters: dict) -> object:
    """
    Train a machine learning model.
    
    Args:
        X_train: Training features
        y_train: Training target
        hyperparameters: Model hyperparameters
        
    Returns:
        Trained model
    """
    try:
        # Extract hyperparameters
        n_estimators = int(hyperparameters.get('n_estimators', 100))
        max_depth = int(hyperparameters.get('max_depth', 10))
        random_state = int(hyperparameters.get('random_state', 42))
        
        # Create and train model
        model = RandomForestClassifier(
            n_estimators=n_estimators,
            max_depth=max_depth,
            random_state=random_state
        )
        
        logger.info("Training model...")
        model.fit(X_train, y_train)
        
        logger.info("Model training completed")
        return model
        
    except Exception as e:
        logger.error(f"Failed to train model: {str(e)}")
        raise

def evaluate_model(model, X_val, y_val) -> dict:
    """
    Evaluate the trained model.
    
    Args:
        model: Trained model
        X_val: Validation features
        y_val: Validation target
        
    Returns:
        Dictionary containing evaluation metrics
    """
    try:
        # Make predictions
        y_pred = model.predict(X_val)
        
        # Calculate metrics
        accuracy = accuracy_score(y_val, y_pred)
        
        # Generate classification report
        report = classification_report(y_val, y_pred, output_dict=True)
        
        metrics = {
            'accuracy': accuracy,
            'precision': report['weighted avg']['precision'],
            'recall': report['weighted avg']['recall'],
            'f1_score': report['weighted avg']['f1-score']
        }
        
        logger.info(f"Model accuracy: {accuracy:.4f}")
        logger.info(f"Model precision: {metrics['precision']:.4f}")
        logger.info(f"Model recall: {metrics['recall']:.4f}")
        logger.info(f"Model F1-score: {metrics['f1_score']:.4f}")
        
        return metrics
        
    except Exception as e:
        logger.error(f"Failed to evaluate model: {str(e)}")
        raise

def save_model(model, model_dir: str) -> str:
    """
    Save the trained model.
    
    Args:
        model: Trained model
        model_dir: Directory to save the model
        
    Returns:
        Path to the saved model
    """
    try:
        # Create model directory if it doesn't exist
        os.makedirs(model_dir, exist_ok=True)
        
        # Save model
        model_path = os.path.join(model_dir, 'model.joblib')
        joblib.dump(model, model_path)
        
        logger.info(f"Model saved to: {model_path}")
        return model_path
        
    except Exception as e:
        logger.error(f"Failed to save model: {str(e)}")
        raise

def save_metrics(metrics: dict, model_dir: str) -> str:
    """
    Save model metrics.
    
    Args:
        metrics: Model metrics dictionary
        model_dir: Directory to save the metrics
        
    Returns:
        Path to the saved metrics file
    """
    try:
        # Create model directory if it doesn't exist
        os.makedirs(model_dir, exist_ok=True)
        
        # Save metrics
        metrics_path = os.path.join(model_dir, 'metrics.json')
        with open(metrics_path, 'w') as f:
            json.dump(metrics, f, indent=2)
        
        logger.info(f"Metrics saved to: {metrics_path}")
        return metrics_path
        
    except Exception as e:
        logger.error(f"Failed to save metrics: {str(e)}")
        raise

def main():
    """Main training function."""
    parser = argparse.ArgumentParser(description='Train a machine learning model')
    
    parser.add_argument('--data-path', default='/opt/ml/input/data', help='Path to training data')
    parser.add_argument('--model-dir', default='/opt/ml/model', help='Directory to save the model')
    parser.add_argument('--n-estimators', type=int, default=100, help='Number of estimators')
    parser.add_argument('--max-depth', type=int, default=10, help='Maximum depth')
    parser.add_argument('--random-state', type=int, default=42, help='Random state')
    
    args = parser.parse_args()
    
    try:
        logger.info("Starting training process...")
        
        # Load data
        X_train, X_val, y_train, y_val = load_data(args.data_path)
        
        # Prepare hyperparameters
        hyperparameters = {
            'n_estimators': args.n_estimators,
            'max_depth': args.max_depth,
            'random_state': args.random_state
        }
        
        # Train model
        model = train_model(X_train, y_train, hyperparameters)
        
        # Evaluate model
        metrics = evaluate_model(model, X_val, y_val)
        
        # Save model
        model_path = save_model(model, args.model_dir)
        
        # Save metrics
        metrics_path = save_metrics(metrics, args.model_dir)
        
        # Save hyperparameters
        hyperparams_path = os.path.join(args.model_dir, 'hyperparameters.json')
        with open(hyperparams_path, 'w') as f:
            json.dump(hyperparameters, f, indent=2)
        
        logger.info("Training process completed successfully!")
        logger.info(f"Model saved to: {model_path}")
        logger.info(f"Metrics saved to: {metrics_path}")
        logger.info(f"Hyperparameters saved to: {hyperparams_path}")
        
    except Exception as e:
        logger.error(f"Training process failed: {str(e)}")
        raise

if __name__ == "__main__":
    main()
