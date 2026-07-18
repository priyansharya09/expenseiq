from rest_framework import serializers
from django.contrib.auth.models import User
from .models import Transaction, Category, Contact, DebtRecord
import datetime


class UserSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, min_length=6)

    class Meta:
        model = User
        fields = ['id', 'username', 'email', 'first_name', 'last_name', 'password']

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

    def create(self, validated_data):
        user = User.objects.create_user(**validated_data)
        return user


class CategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = Category
        fields = ['id', 'name', 'icon']


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
