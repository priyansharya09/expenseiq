from django.test import TestCase
from django.contrib.auth.models import User
from django.urls import reverse
from rest_framework.test import APITestCase, APIClient
from rest_framework import status
from decimal import Decimal
import datetime
import io
import openpyxl

from .models import Transaction, Category


# ─── Model Tests ────────────────────────────────────────────────────────────────

class CategoryModelTest(TestCase):
    def test_category_str(self):
        cat = Category.objects.create(name='food', icon='🍔')
        self.assertEqual(str(cat), 'food')

    def test_category_unique_name(self):
        Category.objects.create(name='food', icon='🍔')
        with self.assertRaises(Exception):
            Category.objects.create(name='food', icon='🍕')


class TransactionModelTest(TestCase):
    def setUp(self):
        self.user = User.objects.create_user('testuser', password='testpass123')
        self.cat = Category.objects.create(name='food', icon='🍔')

    def test_transaction_str(self):
        tx = Transaction.objects.create(
            user=self.user, name='Lunch', amount=Decimal('250.00'),
            type='expense', category=self.cat, date=datetime.date.today()
        )
        self.assertIn('testuser', str(tx))
        self.assertIn('Lunch', str(tx))

    def test_transaction_ordering(self):
        tx1 = Transaction.objects.create(
            user=self.user, name='Old', amount=100, type='expense',
            category=self.cat, date=datetime.date(2024, 1, 1)
        )
        tx2 = Transaction.objects.create(
            user=self.user, name='New', amount=200, type='income',
            category=self.cat, date=datetime.date(2024, 6, 1)
        )
        txns = list(Transaction.objects.filter(user=self.user))
        self.assertEqual(txns[0], tx2)  # newest first


# ─── Auth API Tests ─────────────────────────────────────────────────────────────

class AuthAPITest(APITestCase):
    def setUp(self):
        self.client = APIClient()
        self.register_url = '/api/auth/register/'
        self.login_url = '/api/auth/login/'

    def test_register_success(self):
        data = {'username': 'newuser', 'email': 'new@example.com', 'password': 'secure123'}
        res = self.client.post(self.register_url, data)
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertIn('access', res.data)
        self.assertIn('refresh', res.data)

    def test_register_duplicate_username(self):
        User.objects.create_user('dupeuser', password='pass123')
        data = {'username': 'dupeuser', 'password': 'pass123'}
        res = self.client.post(self.register_url, data)
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_register_short_password(self):
        data = {'username': 'user1', 'password': '123'}
        res = self.client.post(self.register_url, data)
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_login_success(self):
        User.objects.create_user('loginuser', password='loginpass123')
        res = self.client.post(self.login_url, {'username': 'loginuser', 'password': 'loginpass123'})
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertIn('access', res.data)

    def test_login_wrong_password(self):
        User.objects.create_user('user2', password='correct')
        res = self.client.post(self.login_url, {'username': 'user2', 'password': 'wrong'})
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_protected_endpoint_without_token(self):
        res = self.client.get('/api/transactions/')
        self.assertEqual(res.status_code, status.HTTP_401_UNAUTHORIZED)


# ─── Transaction API Tests ──────────────────────────────────────────────────────

class TransactionAPITest(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user('apiuser', password='apipass123')
        self.other_user = User.objects.create_user('otheruser', password='otherpass123')
        self.cat = Category.objects.create(name='food', icon='🍔')
        self.client = APIClient()
        # Get JWT token
        res = self.client.post('/api/auth/login/', {'username': 'apiuser', 'password': 'apipass123'})
        self.token = res.data['access']
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {self.token}')
        self.url = '/api/transactions/'

    def _make_tx(self, user=None, **kwargs):
        defaults = {
            'user': user or self.user, 'name': 'Test Tx', 'amount': Decimal('500'),
            'type': 'expense', 'category': self.cat, 'date': datetime.date.today()
        }
        defaults.update(kwargs)
        return Transaction.objects.create(**defaults)

    def test_create_expense(self):
        data = {'name': 'Lunch', 'amount': '250.00', 'type': 'expense',
                'category': self.cat.id, 'date': str(datetime.date.today())}
        res = self.client.post(self.url, data)
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res.data['name'], 'Lunch')

    def test_create_income(self):
        data = {'name': 'Salary', 'amount': '50000', 'type': 'income',
                'category': self.cat.id, 'date': str(datetime.date.today())}
        res = self.client.post(self.url, data)
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res.data['type'], 'income')

    def test_create_negative_amount_fails(self):
        data = {'name': 'Bad', 'amount': '-100', 'type': 'expense',
                'category': self.cat.id, 'date': str(datetime.date.today())}
        res = self.client.post(self.url, data)
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_create_future_date_fails(self):
        data = {'name': 'Future', 'amount': '100', 'type': 'expense',
                'category': self.cat.id, 'date': '2099-01-01'}
        res = self.client.post(self.url, data)
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_list_only_own_transactions(self):
        self._make_tx()
        self._make_tx(user=self.other_user, name='OtherUserTx')
        res = self.client.get(self.url)
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        names = [t['name'] for t in res.data['results']]
        self.assertNotIn('OtherUserTx', names)

    def test_filter_by_type(self):
        self._make_tx(type='income')
        self._make_tx(type='expense')
        res = self.client.get(self.url + '?type=income')
        for t in res.data['results']:
            self.assertEqual(t['type'], 'income')

    def test_filter_by_month_year(self):
        self._make_tx(date=datetime.date(2024, 3, 15))
        self._make_tx(date=datetime.date(2024, 6, 10))
        res = self.client.get(self.url + '?month=3&year=2024')
        for t in res.data['results']:
            self.assertTrue(t['date'].startswith('2024-03'))

    def test_update_transaction(self):
        tx = self._make_tx()
        res = self.client.patch(f'{self.url}{tx.id}/', {'name': 'Updated Name'})
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(res.data['name'], 'Updated Name')

    def test_delete_transaction(self):
        tx = self._make_tx()
        res = self.client.delete(f'{self.url}{tx.id}/')
        self.assertEqual(res.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(Transaction.objects.filter(id=tx.id).exists())

    def test_cannot_delete_others_transaction(self):
        tx = self._make_tx(user=self.other_user)
        res = self.client.delete(f'{self.url}{tx.id}/')
        self.assertEqual(res.status_code, status.HTTP_404_NOT_FOUND)

    def test_summary_endpoint(self):
        today = datetime.date.today()
        self._make_tx(type='income', amount=Decimal('10000'))
        self._make_tx(type='expense', amount=Decimal('3000'))
        res = self.client.get(f'{self.url}summary/?month={today.month}&year={today.year}')
        self.assertEqual(res.status_code, status.HTTP_200_OK)
        self.assertEqual(Decimal(str(res.data['total_income'])), Decimal('10000'))
        self.assertEqual(Decimal(str(res.data['total_expense'])), Decimal('3000'))
        self.assertEqual(Decimal(str(res.data['balance'])), Decimal('7000'))


# ─── Bulk Upload Tests ──────────────────────────────────────────────────────────

class BulkUploadTest(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user('bulkuser', password='bulkpass123')
        self.client = APIClient()
        res = self.client.post('/api/auth/login/', {'username': 'bulkuser', 'password': 'bulkpass123'})
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {res.data["access"]}')
        self.url = '/api/transactions/bulk-upload/'

    def _make_xlsx(self, rows):
        wb = openpyxl.Workbook()
        ws = wb.active
        ws.append(['Date', 'Name', 'Amount', 'Type', 'Category', 'Note'])
        for r in rows:
            ws.append(r)
        buf = io.BytesIO()
        wb.save(buf)
        buf.seek(0)
        buf.name = 'test.xlsx'
        return buf

    def test_xlsx_upload_success(self):
        today = str(datetime.date.today())
        rows = [
            [today, 'Grocery', 1500, 'expense', 'food', ''],
            [today, 'Salary', 50000, 'income', 'salary', 'Monthly'],
        ]
        f = self._make_xlsx(rows)
        res = self.client.post(self.url, {'file': f}, format='multipart')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res.data['imported'], 2)
        self.assertEqual(res.data['failed'], 0)

    def test_xlsx_bad_amount_row(self):
        today = str(datetime.date.today())
        rows = [
            [today, 'Valid', 1000, 'expense', 'food', ''],
            [today, 'Invalid', -500, 'expense', 'food', ''],  # negative amount
        ]
        f = self._make_xlsx(rows)
        res = self.client.post(self.url, {'file': f}, format='multipart')
        self.assertEqual(res.status_code, status.HTTP_201_CREATED)
        self.assertEqual(res.data['imported'], 1)
        self.assertEqual(res.data['failed'], 1)

    def test_no_file_returns_error(self):
        res = self.client.post(self.url, {}, format='multipart')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)

    def test_unsupported_file_type(self):
        f = io.BytesIO(b'fake pdf content')
        f.name = 'data.pdf'
        res = self.client.post(self.url, {'file': f}, format='multipart')
        self.assertEqual(res.status_code, status.HTTP_400_BAD_REQUEST)
