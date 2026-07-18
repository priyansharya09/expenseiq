#!/usr/bin/env python
"""
Test script to verify registration error handling
"""
import os
import sys
import django

# Add backend to path
sys.path.insert(0, r'd:\expenseiq\expenseiq\backend\expenseiq')
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'expenseiq.settings')
django.setup()

from django.test import TestCase
from rest_framework.test import APIClient
from rest_framework import status
from django.contrib.auth.models import User


def test_duplicate_username():
    """Test registration fails with duplicate username"""
    client = APIClient()
    
    # Create a user
    User.objects.create_user('testuser', email='test@example.com', password='pass123')
    
    # Try to register with same username
    response = client.post('/api/auth/register/', {
        'username': 'testuser',
        'email': 'different@example.com',
        'password': 'pass123'
    })
    
    print(f"Status: {response.status_code}")
    print(f"Response: {response.data}")
    assert response.status_code == status.HTTP_400_BAD_REQUEST
    assert 'username' in response.data
    print("✓ Duplicate username properly rejected")


def test_duplicate_email():
    """Test registration fails with duplicate email"""
    client = APIClient()
    
    # Create a user
    User.objects.create_user('user1', email='test@example.com', password='pass123')
    
    # Try to register with same email
    response = client.post('/api/auth/register/', {
        'username': 'different_user',
        'email': 'test@example.com',
        'password': 'pass123'
    })
    
    print(f"\nStatus: {response.status_code}")
    print(f"Response: {response.data}")
    assert response.status_code == status.HTTP_400_BAD_REQUEST
    assert 'email' in response.data
    print("✓ Duplicate email properly rejected")


def test_successful_registration():
    """Test successful registration"""
    client = APIClient()
    
    response = client.post('/api/auth/register/', {
        'username': 'newuser123',
        'email': 'newuser@example.com',
        'password': 'secure123'
    })
    
    print(f"\nStatus: {response.status_code}")
    print(f"Response: {response.data}")
    assert response.status_code == status.HTTP_201_CREATED
    assert 'access' in response.data
    assert 'refresh' in response.data
    assert response.data['user']['username'] == 'newuser123'
    print("✓ Successful registration works properly")


if __name__ == '__main__':
    print("Testing Registration Error Handling\n" + "="*40)
    
    try:
        test_duplicate_username()
        test_duplicate_email()
        test_successful_registration()
        print("\n" + "="*40)
        print("All tests passed! ✓")
    except AssertionError as e:
        print(f"\n✗ Test failed: {e}")
        sys.exit(1)
