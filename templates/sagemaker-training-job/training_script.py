#!/usr/bin/env python3
"""
SageMaker Training Job Template
This is a template for creating SageMaker training jobs.
Replace the placeholder code with your actual training logic.
"""

import argparse
import json
import os
import sys
from pathlib import Path

import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, Dataset
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
import boto3
import sagemaker
from sagemaker.pytorch import PyTorch


class CustomDataset(Dataset):
    """Custom dataset class for your training data"""
    
    def __init__(self, data, labels):
        self.data = data
        self.labels = labels
    
    def __len__(self):
        return len(self.data)
    
    def __getitem__(self, idx):
        return torch.tensor(self.data[idx], dtype=torch.float32), torch.tensor(self.labels[idx], dtype=torch.long)


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


def load_data(data_dir):
    """Load and preprocess training data"""
    # TODO: Replace with your actual data loading logic
    print(f"Loading data from {data_dir}")
    
    # Example: Load CSV data
    # data_path = os.path.join(data_dir, 'train.csv')
    # df = pd.read_csv(data_path)
    
    # For demonstration, create synthetic data
    np.random.seed(42)
    X = np.random.randn(1000, 10)  # 1000 samples, 10 features
    y = np.random.randint(0, 3, 1000)  # 3 classes
    
    return X, y


def train_model(model, train_loader, val_loader, epochs, learning_rate, device):
    """Train the model"""
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=learning_rate)
    
    model.train()
    for epoch in range(epochs):
        total_loss = 0
        for batch_idx, (data, target) in enumerate(train_loader):
            data, target = data.to(device), target.to(device)
            
            optimizer.zero_grad()
            output = model(data)
            loss = criterion(output, target)
            loss.backward()
            optimizer.step()
            
            total_loss += loss.item()
            
            if batch_idx % 10 == 0:
                print(f'Epoch {epoch}, Batch {batch_idx}, Loss: {loss.item():.4f}')
        
        # Validation
        model.eval()
        val_loss = 0
        correct = 0
        with torch.no_grad():
            for data, target in val_loader:
                data, target = data.to(device), target.to(device)
                output = model(data)
                val_loss += criterion(output, target).item()
                pred = output.argmax(dim=1, keepdim=True)
                correct += pred.eq(target.view_as(pred)).sum().item()
        
        val_accuracy = 100. * correct / len(val_loader.dataset)
        print(f'Epoch {epoch}, Validation Loss: {val_loss:.4f}, Validation Accuracy: {val_accuracy:.2f}%')
        model.train()


def save_model(model, model_dir):
    """Save the trained model"""
    model_path = os.path.join(model_dir, 'model.pth')
    torch.save(model.state_dict(), model_path)
    print(f"Model saved to {model_path}")


def main():
    parser = argparse.ArgumentParser(description='SageMaker Training Job')
    parser.add_argument('--data-dir', type=str, default='/opt/ml/input/data/training',
                       help='Directory containing training data')
    parser.add_argument('--model-dir', type=str, default='/opt/ml/model',
                       help='Directory to save the trained model')
    parser.add_argument('--epochs', type=int, default=10,
                       help='Number of training epochs')
    parser.add_argument('--batch-size', type=int, default=32,
                       help='Batch size for training')
    parser.add_argument('--learning-rate', type=float, default=0.001,
                       help='Learning rate for optimizer')
    parser.add_argument('--hidden-size', type=int, default=64,
                       help='Hidden layer size')
    
    args = parser.parse_args()
    
    # Set device
    device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
    print(f"Using device: {device}")
    
    # Load data
    X, y = load_data(args.data_dir)
    
    # Split data
    X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.2, random_state=42)
    
    # Create datasets
    train_dataset = CustomDataset(X_train, y_train)
    val_dataset = CustomDataset(X_val, y_val)
    
    # Create data loaders
    train_loader = DataLoader(train_dataset, batch_size=args.batch_size, shuffle=True)
    val_loader = DataLoader(val_dataset, batch_size=args.batch_size, shuffle=False)
    
    # Create model
    input_size = X.shape[1]
    num_classes = len(np.unique(y))
    model = SimpleModel(input_size, args.hidden_size, num_classes).to(device)
    
    print(f"Model created with {sum(p.numel() for p in model.parameters())} parameters")
    
    # Train model
    train_model(model, train_loader, val_loader, args.epochs, args.learning_rate, device)
    
    # Save model
    save_model(model, args.model_dir)
    
    print("Training completed successfully!")


if __name__ == '__main__':
    main()
