from django.db import models
from django.contrib.auth.models import User


class Category(models.Model):
    CATEGORY_TYPES = [
        ('food', 'Food & Dining'),
        ('transport', 'Transport'),
        ('shopping', 'Shopping'),
        ('health', 'Health'),
        ('entertainment', 'Entertainment'),
        ('salary', 'Salary'),
        ('freelance', 'Freelance'),
        ('utilities', 'Utilities'),
        ('education', 'Education'),
        ('other', 'Other'),
    ]
    name = models.CharField(max_length=50, choices=CATEGORY_TYPES, unique=True)
    icon = models.CharField(max_length=10, default='📦')

    def __str__(self):
        return self.name

    class Meta:
        verbose_name_plural = 'Categories'


class Transaction(models.Model):
    TYPE_CHOICES = [
        ('income', 'Income'),
        ('expense', 'Expense'),
    ]

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='transactions')
    name = models.CharField(max_length=255)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    type = models.CharField(max_length=10, choices=TYPE_CHOICES)
    category = models.ForeignKey(Category, on_delete=models.SET_NULL, null=True, blank=True)
    date = models.DateField()
    note = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.user.username} | {self.name} | {self.amount}"

    class Meta:
        ordering = ['-date', '-created_at']
