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


PAYMENT_MODES = [
    ('cash', 'Cash'),
    ('upi', 'UPI'),
    ('neft', 'NEFT/IMPS/RTGS'),
    ('card_debit', 'Debit Card'),
    ('card_credit', 'Credit Card'),
    ('wallet', 'Wallet'),
    ('cheque', 'Cheque'),
    ('other', 'Other'),
]


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
    shared_amount = models.DecimalField(max_digits=12, decimal_places=2, default=0, help_text="Amount paid on behalf of others")
    payment_mode = models.CharField(max_length=20, choices=PAYMENT_MODES, null=True, blank=True, help_text="Payment method used")
    payment_app = models.CharField(max_length=50, null=True, blank=True, help_text="Specific app used (e.g., GPay)")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.user.username} | {self.name} | {self.amount}"

    class Meta:
        ordering = ['-date', '-created_at']


class Contact(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='contacts')
    name = models.CharField(max_length=100)
    phone = models.CharField(max_length=20, blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ['user', 'name']
        ordering = ['name']

    def __str__(self):
        return f'{self.name} ({self.phone})'


class DebtRecord(models.Model):
    DEBT_TYPES = [('lend', 'Lend'), ('borrow', 'Borrow')]

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='debt_records')
    contact = models.ForeignKey(Contact, on_delete=models.CASCADE, related_name='debt_records')
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    type = models.CharField(max_length=10, choices=DEBT_TYPES)
    description = models.CharField(max_length=255)
    date = models.DateField()
    is_settled = models.BooleanField(default=False)
    settled_date = models.DateField(null=True, blank=True)
    note = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-date', '-created_at']

    def __str__(self):
        return f'{self.type}: {self.amount} - {self.contact.name}'
