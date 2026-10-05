import re
from django.db import models
from django.contrib.auth.models import User


def normalize_phone(raw):
    """Reduce a phone number to a comparable key: digits only, last 10 (India mobile)."""
    if not raw:
        return ''
    digits = re.sub(r'\D', '', str(raw))
    return digits[-10:] if len(digits) >= 10 else digits


class Category(models.Model):
    KIND_CHOICES = [
        ('income', 'Income'),
        ('expense', 'Expense'),
        ('both', 'Both'),
    ]
    # user=None means a shared system default category visible to everyone;
    # a non-null user means a custom category owned by that user.
    user = models.ForeignKey(
        User, on_delete=models.CASCADE, related_name='categories',
        null=True, blank=True,
    )
    name = models.CharField(max_length=50)
    icon = models.CharField(max_length=10, default='📦')
    kind = models.CharField(max_length=10, choices=KIND_CHOICES, default='expense')

    def __str__(self):
        return self.name

    @property
    def is_custom(self):
        return self.user_id is not None

    class Meta:
        verbose_name_plural = 'Categories'
        constraints = [
            models.UniqueConstraint(fields=['user', 'name'], name='uniq_user_category'),
        ]


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


class Budget(models.Model):
    """A monthly spending budget, either overall (category=None) or per-category."""
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='budgets')
    category = models.ForeignKey(
        Category, on_delete=models.CASCADE, related_name='budgets',
        null=True, blank=True, help_text='Null = overall budget for the month',
    )
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    month = models.PositiveSmallIntegerField()
    year = models.PositiveSmallIntegerField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-year', '-month']
        constraints = [
            models.UniqueConstraint(
                fields=['user', 'category', 'month', 'year'],
                name='uniq_user_category_period_budget',
            ),
        ]

    def __str__(self):
        scope = self.category.name if self.category else 'Overall'
        return f'{self.user.username} | {scope} | {self.month}/{self.year}'


class RecurringTransaction(models.Model):
    """A rule that materializes into real Transactions when due (on app open)."""
    TYPE_CHOICES = [('income', 'Income'), ('expense', 'Expense')]
    FREQUENCY_CHOICES = [('weekly', 'Weekly'), ('monthly', 'Monthly')]

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='recurring_transactions')
    name = models.CharField(max_length=255)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    type = models.CharField(max_length=10, choices=TYPE_CHOICES)
    category = models.ForeignKey(Category, on_delete=models.SET_NULL, null=True, blank=True)
    payment_mode = models.CharField(max_length=20, choices=PAYMENT_MODES, null=True, blank=True)
    frequency = models.CharField(max_length=10, choices=FREQUENCY_CHOICES, default='monthly')
    next_run = models.DateField(help_text='Next date this rule should post a transaction')
    active = models.BooleanField(default=True)
    note = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['next_run']

    def __str__(self):
        return f'{self.user.username} | {self.name} | {self.frequency}'

    def advance(self):
        """Move next_run forward by one frequency period."""
        from datetime import timedelta
        if self.frequency == 'weekly':
            self.next_run = self.next_run + timedelta(days=7)
        else:  # monthly
            month = self.next_run.month + 1
            year = self.next_run.year
            if month > 12:
                month = 1
                year += 1
            import calendar
            day = min(self.next_run.day, calendar.monthrange(year, month)[1])
            self.next_run = self.next_run.replace(year=year, month=month, day=day)


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


# ─── User profile (phone, for group matching / Pass-2 cross-user sync) ───────────

class UserProfile(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='profile')
    phone = models.CharField(max_length=20, blank=True, default='', db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=['phone'], condition=~models.Q(phone=''),
                name='uniq_profile_phone',
            ),
        ]

    def __str__(self):
        return f'{self.user.username} profile'


# ─── Split groups (shared expenses among several people) ─────────────────────────

class SplitGroup(models.Model):
    """A named group (e.g. 'Flat') whose members share expenses."""
    owner = models.ForeignKey(User, on_delete=models.CASCADE, related_name='owned_groups')
    name = models.CharField(max_length=100)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f'{self.name} ({self.owner.username})'


class GroupMember(models.Model):
    """A person in a group. May map to a registered app user (linked_user) via phone."""
    group = models.ForeignKey(SplitGroup, on_delete=models.CASCADE, related_name='members')
    name = models.CharField(max_length=100)
    phone = models.CharField(max_length=20, blank=True, default='', help_text='Normalized phone key')
    linked_user = models.ForeignKey(
        User, on_delete=models.SET_NULL, null=True, blank=True,
        related_name='group_memberships',
    )
    is_owner = models.BooleanField(default=False, help_text='The member representing the group creator')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-is_owner', 'name']

    def __str__(self):
        return f'{self.name} in {self.group.name}'


class GroupExpense(models.Model):
    """An expense logged inside a group, split across its members via ExpenseShare rows."""
    group = models.ForeignKey(SplitGroup, on_delete=models.CASCADE, related_name='expenses')
    name = models.CharField(max_length=255)
    category = models.ForeignKey(Category, on_delete=models.SET_NULL, null=True, blank=True)
    amount = models.DecimalField(max_digits=12, decimal_places=2)
    paid_by = models.ForeignKey(GroupMember, on_delete=models.CASCADE, related_name='expenses_paid')
    date = models.DateField()
    note = models.TextField(blank=True, default='')
    created_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name='logged_group_expenses')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-date', '-created_at']

    def __str__(self):
        return f'{self.name} ({self.amount}) in {self.group.name}'


class ExpenseShare(models.Model):
    """How much one member owes for one group expense. Sum of shares == expense amount."""
    expense = models.ForeignKey(GroupExpense, on_delete=models.CASCADE, related_name='shares')
    member = models.ForeignKey(GroupMember, on_delete=models.CASCADE, related_name='shares')
    amount = models.DecimalField(max_digits=12, decimal_places=2)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=['expense', 'member'], name='uniq_expense_member_share'),
        ]

    def __str__(self):
        return f'{self.member.name} owes {self.amount} on {self.expense.name}'
