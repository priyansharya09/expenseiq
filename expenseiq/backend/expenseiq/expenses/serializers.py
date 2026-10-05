from rest_framework import serializers
from django.contrib.auth.models import User
from decimal import Decimal
from .models import (
    Transaction, Category, Contact, DebtRecord, Budget, RecurringTransaction,
    UserProfile, SplitGroup, GroupMember, GroupExpense, ExpenseShare,
    normalize_phone,
)
import datetime


class UserSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=6)
    phone = serializers.CharField(write_only=True, required=False, allow_blank=True, default='')

    class Meta:
        model = User
        fields = ['id', 'username', 'email', 'first_name', 'last_name', 'password', 'phone']

    def validate_username(self, value):
        """Validate that username is unique"""
        if User.objects.filter(username=value).exists():
            raise serializers.ValidationError("This username is already taken.")
        return value

    def validate_email(self, value):
        """Validate that email is unique"""
        if User.objects.filter(email=value).exists():
            raise serializers.ValidationError("This email is already registered.")
        return value

    def validate_phone(self, value):
        """Normalize and ensure the phone isn't already registered."""
        norm = normalize_phone(value)
        if norm and UserProfile.objects.filter(phone=norm).exists():
            raise serializers.ValidationError("This phone number is already registered.")
        return norm

    def create(self, validated_data):
        phone = validated_data.pop('phone', '')
        user = User.objects.create_user(**validated_data)
        UserProfile.objects.create(user=user, phone=phone)
        # Link any group memberships that were waiting on this phone number.
        if phone:
            GroupMember.objects.filter(phone=phone, linked_user__isnull=True).update(linked_user=user)
        return user

    def to_representation(self, instance):
        data = super().to_representation(instance)
        profile = getattr(instance, 'profile', None)
        data['phone'] = profile.phone if profile else ''
        return data


class CategorySerializer(serializers.ModelSerializer):
    is_custom = serializers.BooleanField(read_only=True)

    class Meta:
        model = Category
        fields = ['id', 'name', 'icon', 'kind', 'is_custom']

    def validate_name(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError('Category name cannot be empty.')
        return value


class TransactionSerializer(serializers.ModelSerializer):
    category_name = serializers.CharField(source='category.name', read_only=True)
    category_icon = serializers.CharField(source='category.icon', read_only=True)
    self_amount = serializers.SerializerMethodField()

    class Meta:
        model = Transaction
        fields = [
            'id', 'name', 'amount', 'type', 'category', 'category_name',
            'category_icon', 'date', 'note', 'shared_amount', 'payment_mode',
            'payment_app', 'self_amount', 'created_at', 'updated_at'
        ]
        read_only_fields = ['created_at', 'updated_at', 'self_amount']

    def get_self_amount(self, obj):
        return obj.amount - obj.shared_amount

    def validate(self, data):
        amount = data.get('amount', 0)
        shared_amount = data.get('shared_amount', 0)
        if shared_amount < 0:
            raise serializers.ValidationError({"shared_amount": "Shared amount cannot be negative."})
        if shared_amount > amount:
            raise serializers.ValidationError({"shared_amount": "Shared amount cannot be greater than total amount."})
        return data

    def validate_amount(self, value):
        if value <= 0:
            raise serializers.ValidationError("Amount must be greater than zero.")
        return value

    def validate_date(self, value):
        if value > datetime.date.today():
            raise serializers.ValidationError("Date cannot be in the future.")
        return value


class BulkTransactionSerializer(serializers.Serializer):
    """Serializer for validating a single row from XLS bulk upload."""
    name = serializers.CharField(max_length=255)
    amount = serializers.DecimalField(max_digits=12, decimal_places=2)
    type = serializers.ChoiceField(choices=['income', 'expense'])
    category = serializers.CharField(max_length=50, default='other')
    date = serializers.DateField(input_formats=['%Y-%m-%d', '%d/%m/%Y', '%d-%m-%Y', '%m/%d/%Y'])
    note = serializers.CharField(max_length=500, required=False, default='', allow_blank=True)
    shared_amount = serializers.DecimalField(max_digits=12, decimal_places=2, required=False, default=0)
    payment_mode = serializers.CharField(max_length=20, required=False, allow_blank=True, allow_null=True)
    payment_app = serializers.CharField(max_length=50, required=False, allow_blank=True, allow_null=True)

    def validate_amount(self, value):
        if value <= 0:
            raise serializers.ValidationError("Amount must be greater than zero.")
        return value


class MonthlySummarySerializer(serializers.Serializer):
    month = serializers.IntegerField()
    year = serializers.IntegerField()
    total_income = serializers.DecimalField(max_digits=12, decimal_places=2)
    total_expense = serializers.DecimalField(max_digits=12, decimal_places=2)
    balance = serializers.DecimalField(max_digits=12, decimal_places=2)
    transaction_count = serializers.IntegerField()


class ContactSerializer(serializers.ModelSerializer):
    net_balance = serializers.SerializerMethodField()
    unsettled_count = serializers.SerializerMethodField()

    class Meta:
        model = Contact
        fields = ['id', 'name', 'phone', 'net_balance', 'unsettled_count', 'created_at']
        read_only_fields = ['id', 'created_at']

    def get_net_balance(self, obj):
        from django.db.models import Sum, Q, DecimalField
        from django.db.models.functions import Coalesce
        records = obj.debt_records.filter(is_settled=False)
        lent = records.filter(type='lend').aggregate(total=Coalesce(Sum('amount'), 0, output_field=DecimalField()))['total']
        borrowed = records.filter(type='borrow').aggregate(total=Coalesce(Sum('amount'), 0, output_field=DecimalField()))['total']
        return float(lent - borrowed)  # positive = they owe you

    def get_unsettled_count(self, obj):
        return obj.debt_records.filter(is_settled=False).count()


class DebtRecordSerializer(serializers.ModelSerializer):
    contact_name = serializers.CharField(source='contact.name', read_only=True)
    contact_phone = serializers.CharField(source='contact.phone', read_only=True)

    class Meta:
        model = DebtRecord
        fields = ['id', 'contact', 'contact_name', 'contact_phone', 'amount', 'type', 'description', 'date', 'is_settled', 'settled_date', 'note', 'created_at', 'updated_at']
        read_only_fields = ['id', 'created_at', 'updated_at']

    def validate_amount(self, value):
        if value <= 0:
            raise serializers.ValidationError('Amount must be positive.')
        return value


class BudgetSerializer(serializers.ModelSerializer):
    category_name = serializers.CharField(source='category.name', read_only=True)
    category_icon = serializers.CharField(source='category.icon', read_only=True)
    spent = serializers.SerializerMethodField()
    remaining = serializers.SerializerMethodField()
    pct = serializers.SerializerMethodField()

    class Meta:
        model = Budget
        fields = [
            'id', 'category', 'category_name', 'category_icon', 'amount',
            'month', 'year', 'spent', 'remaining', 'pct', 'created_at',
        ]
        read_only_fields = ['id', 'created_at']

    def _spent(self, obj):
        from django.db.models import Sum
        qs = Transaction.objects.filter(
            user=obj.user, type='expense', date__month=obj.month, date__year=obj.year,
        )
        if obj.category_id:
            qs = qs.filter(category_id=obj.category_id)
        return qs.aggregate(total=Sum('amount'))['total'] or 0

    def get_spent(self, obj):
        return float(self._spent(obj))

    def get_remaining(self, obj):
        return float(obj.amount) - float(self._spent(obj))

    def get_pct(self, obj):
        amount = float(obj.amount)
        return round(float(self._spent(obj)) / amount * 100, 1) if amount else 0

    def validate_amount(self, value):
        if value <= 0:
            raise serializers.ValidationError('Budget amount must be greater than zero.')
        return value


class RecurringTransactionSerializer(serializers.ModelSerializer):
    category_name = serializers.CharField(source='category.name', read_only=True)
    category_icon = serializers.CharField(source='category.icon', read_only=True)

    class Meta:
        model = RecurringTransaction
        fields = [
            'id', 'name', 'amount', 'type', 'category', 'category_name', 'category_icon',
            'payment_mode', 'frequency', 'next_run', 'active', 'note', 'created_at',
        ]
        read_only_fields = ['id', 'created_at']

    def validate_amount(self, value):
        if value <= 0:
            raise serializers.ValidationError('Amount must be greater than zero.')
        return value


# ─── Split Group serializers ─────────────────────────────────────────────────────

class GroupMemberSerializer(serializers.ModelSerializer):
    is_app_user = serializers.SerializerMethodField()

    class Meta:
        model = GroupMember
        fields = ['id', 'name', 'phone', 'is_owner', 'linked_user', 'is_app_user']
        read_only_fields = ['id', 'is_owner', 'linked_user']

    def get_is_app_user(self, obj):
        return obj.linked_user_id is not None


class ExpenseShareSerializer(serializers.ModelSerializer):
    member_name = serializers.CharField(source='member.name', read_only=True)

    class Meta:
        model = ExpenseShare
        fields = ['id', 'member', 'member_name', 'amount']
        read_only_fields = ['id']


class GroupExpenseSerializer(serializers.ModelSerializer):
    shares = ExpenseShareSerializer(many=True)
    paid_by_name = serializers.CharField(source='paid_by.name', read_only=True)
    category_name = serializers.CharField(source='category.name', read_only=True)
    category_icon = serializers.CharField(source='category.icon', read_only=True)

    class Meta:
        model = GroupExpense
        fields = [
            'id', 'group', 'name', 'category', 'category_name', 'category_icon',
            'amount', 'paid_by', 'paid_by_name', 'date', 'note', 'shares', 'created_at',
        ]
        read_only_fields = ['id', 'created_at']

    def validate_amount(self, value):
        if value <= 0:
            raise serializers.ValidationError('Amount must be greater than zero.')
        return value

    def validate(self, data):
        request = self.context.get('request')
        group = data.get('group') or getattr(self.instance, 'group', None)
        if request and group and group.owner_id != request.user.id:
            raise serializers.ValidationError('You do not have access to this group.')

        paid_by = data.get('paid_by') or getattr(self.instance, 'paid_by', None)
        if group and paid_by and paid_by.group_id != group.id:
            raise serializers.ValidationError({'paid_by': 'Payer is not a member of this group.'})

        shares = data.get('shares')
        amount = data.get('amount', getattr(self.instance, 'amount', None))
        if shares is not None:
            if not shares:
                raise serializers.ValidationError({'shares': 'At least one member must be included in the split.'})
            total = Decimal('0')
            for s in shares:
                member = s['member']
                if group and member.group_id != group.id:
                    raise serializers.ValidationError({'shares': f'{member.name} is not a member of this group.'})
                if s['amount'] < 0:
                    raise serializers.ValidationError({'shares': 'Share amounts cannot be negative.'})
                total += s['amount']
            # Allow a cent of rounding slack per member for equal splits.
            if amount is not None and abs(total - amount) > Decimal('0.01') * len(shares):
                raise serializers.ValidationError(
                    {'shares': f'Shares must add up to the total ({amount}); got {total}.'}
                )
        return data

    def create(self, validated_data):
        shares = validated_data.pop('shares')
        expense = GroupExpense.objects.create(**validated_data)
        ExpenseShare.objects.bulk_create([
            ExpenseShare(expense=expense, **s) for s in shares
        ])
        return expense

    def update(self, instance, validated_data):
        shares = validated_data.pop('shares', None)
        for key, value in validated_data.items():
            setattr(instance, key, value)
        instance.save()
        if shares is not None:
            instance.shares.all().delete()
            ExpenseShare.objects.bulk_create([
                ExpenseShare(expense=instance, **s) for s in shares
            ])
        return instance


class SplitGroupSerializer(serializers.ModelSerializer):
    members = GroupMemberSerializer(many=True, required=False)
    expense_count = serializers.SerializerMethodField()
    total_spent = serializers.SerializerMethodField()
    balances = serializers.SerializerMethodField()

    class Meta:
        model = SplitGroup
        fields = ['id', 'name', 'members', 'expense_count', 'total_spent', 'balances', 'created_at']
        read_only_fields = ['id', 'created_at']

    def get_expense_count(self, obj):
        return obj.expenses.count()

    def get_total_spent(self, obj):
        from django.db.models import Sum
        return float(obj.expenses.aggregate(t=Sum('amount'))['t'] or 0)

    def get_balances(self, obj):
        """Net position per member: (total paid) - (total owed). Positive = others owe them."""
        from django.db.models import Sum
        out = []
        for m in obj.members.all():
            paid = m.expenses_paid.aggregate(t=Sum('amount'))['t'] or 0
            owed = m.shares.aggregate(t=Sum('amount'))['t'] or 0
            out.append({
                'member': m.id,
                'name': m.name,
                'is_owner': m.is_owner,
                'net': round(float(paid) - float(owed), 2),
            })
        return out

    def create(self, validated_data):
        members = validated_data.pop('members', [])
        request = self.context.get('request')
        owner = request.user
        group = SplitGroup.objects.create(owner=owner, **validated_data)

        owner_profile = getattr(owner, 'profile', None)
        GroupMember.objects.create(
            group=group,
            name=(owner.first_name or owner.username),
            phone=owner_profile.phone if owner_profile else '',
            linked_user=owner,
            is_owner=True,
        )
        for m in members:
            self._create_member(group, m.get('name', ''), m.get('phone', ''))
        return group

    @staticmethod
    def _create_member(group, name, phone):
        norm = normalize_phone(phone)
        linked = None
        if norm:
            profile = UserProfile.objects.filter(phone=norm).select_related('user').first()
            linked = profile.user if profile else None
        return GroupMember.objects.create(
            group=group, name=name, phone=norm, linked_user=linked,
        )
