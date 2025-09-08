#!/usr/bin/env python3
"""
XGBoost Training Script for SageMaker
This script demonstrates XGBoost training using AWS pre-built containers.
"""

import argparse
import json
import logging
import os
import pandas as pd
import numpy as np
import xgboost as xgb
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_squared_error, r2_score, accuracy_score
import joblib

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def load_data(data_path: str) -> tuple:
    """
    Load training and validation data for XGBoost.
    
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

def train_xgboost_model(X_train, y_train, hyperparameters: dict) -> xgb.Booster:
    """
    Train an XGBoost model.
    
    Args:
        X_train: Training features
        y_train: Training target
        hyperparameters: Model hyperparameters
        
    Returns:
        Trained XGBoost model
    """
    try:
        # Extract hyperparameters
        num_round = int(hyperparameters.get('num_round', 100))
        max_depth = int(hyperparameters.get('max_depth', 6))
        eta = float(hyperparameters.get('eta', 0.3))
        objective = hyperparameters.get('objective', 'reg:squarederror')
        subsample = float(hyperparameters.get('subsample', 0.8))
        colsample_bytree = float(hyperparameters.get('colsample_bytree', 0.8))
        eval_metric = hyperparameters.get('eval_metric', 'rmse')
        early_stopping_rounds = int(hyperparameters.get('early_stopping_rounds', 10))
        
        # Prepare XGBoost parameters
        params = {
            'max_depth': max_depth,
            'eta': eta,
            'objective': objective,
            'subsample': subsample,
            'colsample_bytree': colsample_bytree,
            'eval_metric': eval_metric
        }
        
        # Create DMatrix for training
        dtrain = xgb.DMatrix(X_train, label=y_train)
        
        # Create DMatrix for validation (if needed for early stopping)
        dval = xgb.DMatrix(X_train, label=y_train)  # Using training data for simplicity
        
        logger.info("Training XGBoost model...")
        logger.info(f"Parameters: {params}")
        logger.info(f"Number of boosting rounds: {num_round}")
        
        # Train the model
        model = xgb.train(
            params=params,
            dtrain=dtrain,
            num_boost_round=num_round,
            evals=[(dtrain, 'train')],
            early_stopping_rounds=early_stopping_rounds,
            verbose_eval=10
        )
        
        logger.info("XGBoost model training completed")
        return model
        
    except Exception as e:
        logger.error(f"Failed to train XGBoost model: {str(e)}")
        raise

def evaluate_model(model: xgb.Booster, X_val, y_val) -> dict:
    """
    Evaluate the trained XGBoost model.
    
    Args:
        model: Trained XGBoost model
        X_val: Validation features
        y_val: Validation target
        
    Returns:
        Dictionary containing evaluation metrics
    """
    try:
        # Create DMatrix for validation
        dval = xgb.DMatrix(X_val, label=y_val)
        
        # Make predictions
        y_pred = model.predict(dval)
        
        # Calculate metrics based on objective
        objective = model.get_dump()[0]  # Get objective from model
        
        if 'reg:' in str(objective):
            # Regression metrics
            mse = mean_squared_error(y_val, y_pred)
            rmse = np.sqrt(mse)
            r2 = r2_score(y_val, y_pred)
            
            metrics = {
                'mse': mse,
                'rmse': rmse,
                'r2_score': r2
            }
            
            logger.info(f"RMSE: {rmse:.4f}")
            logger.info(f"R² Score: {r2:.4f}")
            
        else:
            # Classification metrics
            # Convert probabilities to predictions if needed
            if len(y_pred.shape) > 1 and y_pred.shape[1] > 1:
                y_pred_class = np.argmax(y_pred, axis=1)
            else:
                y_pred_class = (y_pred > 0.5).astype(int)
            
            accuracy = accuracy_score(y_val, y_pred_class)
            
            metrics = {
                'accuracy': accuracy,
                'predictions': y_pred.tolist()
            }
            
            logger.info(f"Accuracy: {accuracy:.4f}")
        
        return metrics
        
    except Exception as e:
        logger.error(f"Failed to evaluate model: {str(e)}")
        raise

def save_model(model: xgb.Booster, model_dir: str) -> str:
    """
    Save the trained XGBoost model.
    
    Args:
        model: Trained XGBoost model
        model_dir: Directory to save the model
        
    Returns:
        Path to the saved model
    """
    try:
        # Create model directory if it doesn't exist
        os.makedirs(model_dir, exist_ok=True)
        
        # Save model in multiple formats for compatibility
        model_path_json = os.path.join(model_dir, 'xgboost-model.json')
        model_path_pkl = os.path.join(model_dir, 'xgboost-model.pkl')
        
        # Save as JSON (XGBoost native format)
        model.save_model(model_path_json)
        
        # Save as pickle for scikit-learn compatibility
        joblib.dump(model, model_path_pkl)
        
        logger.info(f"XGBoost model saved to: {model_path_json}")
        logger.info(f"XGBoost model (pickle) saved to: {model_path_pkl}")
        
        return model_path_json
        
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
    parser = argparse.ArgumentParser(description='Train an XGBoost model')
    
    parser.add_argument('--data-path', default='/opt/ml/input/data', help='Path to training data')
    parser.add_argument('--model-dir', default='/opt/ml/model', help='Directory to save the model')
    parser.add_argument('--num-round', type=int, default=100, help='Number of boosting rounds')
    parser.add_argument('--max-depth', type=int, default=6, help='Maximum depth of trees')
    parser.add_argument('--eta', type=float, default=0.3, help='Learning rate')
    parser.add_argument('--objective', default='reg:squarederror', help='XGBoost objective function')
    parser.add_argument('--subsample', type=float, default=0.8, help='Subsample ratio')
    parser.add_argument('--colsample-bytree', type=float, default=0.8, help='Column sample ratio')
    parser.add_argument('--eval-metric', default='rmse', help='Evaluation metric')
    parser.add_argument('--early-stopping-rounds', type=int, default=10, help='Early stopping rounds')
    
    args = parser.parse_args()
    
    try:
        logger.info("Starting XGBoost training process...")
        
        # Load data
        X_train, X_val, y_train, y_val = load_data(args.data_path)
        
        # Prepare hyperparameters
        hyperparameters = {
            'num_round': args.num_round,
            'max_depth': args.max_depth,
            'eta': args.eta,
            'objective': args.objective,
            'subsample': args.subsample,
            'colsample_bytree': args.colsample_bytree,
            'eval_metric': args.eval_metric,
            'early_stopping_rounds': args.early_stopping_rounds
        }
        
        # Train model
        model = train_xgboost_model(X_train, y_train, hyperparameters)
        
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
        
        logger.info("XGBoost training process completed successfully!")
        logger.info(f"Model saved to: {model_path}")
        logger.info(f"Metrics saved to: {metrics_path}")
        logger.info(f"Hyperparameters saved to: {hyperparams_path}")
        
    except Exception as e:
        logger.error(f"XGBoost training process failed: {str(e)}")
        raise

if __name__ == "__main__":
    main()