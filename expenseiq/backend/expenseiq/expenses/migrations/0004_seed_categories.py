from django.db import migrations


# Default system categories: (name, icon, kind)
DEFAULT_CATEGORIES = [
    # Income
    ('Salary', '💰', 'income'),
    ('Freelance', '💼', 'income'),
    ('Business', '📈', 'income'),
    ('Investment', '📊', 'income'),
    ('Gift', '🎁', 'income'),
    ('Other Income', '💵', 'income'),
    # Expense
    ('Food', '🍔', 'expense'),
    ('Transport', '🚗', 'expense'),
    ('Shopping', '🛍', 'expense'),
    ('Health', '💊', 'expense'),
    ('Entertainment', '🎬', 'expense'),
    ('Utilities', '💡', 'expense'),
    ('Education', '📚', 'expense'),
    ('Rent', '🏠', 'expense'),
    ('Groceries', '🛒', 'expense'),
    ('Other', '📦', 'both'),
]

# Backfill kind for any pre-existing (old choices-based) rows.
LEGACY_KIND = {
    'salary': 'income',
    'freelance': 'income',
    'other': 'both',
}


def seed(apps, schema_editor):
    Category = apps.get_model('expenses', 'Category')

    # 1. Backfill kind on existing system rows based on their old name.
    for cat in Category.objects.filter(user__isnull=True):
        lowered = cat.name.strip().lower()
        cat.kind = LEGACY_KIND.get(lowered, 'expense')
        cat.save(update_fields=['kind'])

    # 2. Ensure the full default set exists (idempotent, case-insensitive match).
    existing = {c.name.strip().lower() for c in Category.objects.filter(user__isnull=True)}
    for name, icon, kind in DEFAULT_CATEGORIES:
        if name.strip().lower() not in existing:
            Category.objects.create(user=None, name=name, icon=icon, kind=kind)


def noop(apps, schema_editor):
    pass


class Migration(migrations.Migration):

    dependencies = [
        ('expenses', '0003_budget_recurringtransaction_category_kind_and_more'),
    ]

    operations = [
        migrations.RunPython(seed, noop),
    ]
