from rest_framework import viewsets, status, generics
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from django.contrib.auth.models import User
from django.db.models import Sum, Q
from django.db.models.functions import TruncMonth
import openpyxl
import xlrd
import csv
import io
from datetime import date

from .models import Transaction, Category
from .serializers import (
    UserSerializer, TransactionSerializer, CategorySerializer,
    BulkTransactionSerializer, MonthlySummarySerializer
)


# ─── Auth Views ────────────────────────────────────────────────────────────────

class RegisterView(generics.CreateAPIView):
    queryset = User.objects.all()
    serializer_class = UserSerializer
    permission_classes = [AllowAny]

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        refresh = RefreshToken.for_user(user)
        return Response({
            'user': UserSerializer(user).data,
            'access': str(refresh.access_token),
            'refresh': str(refresh),
        }, status=status.HTTP_201_CREATED)


class LogoutView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        try:
            refresh_token = request.data.get('refresh')
            token = RefreshToken(refresh_token)
            token.blacklist()
            return Response({'detail': 'Successfully logged out.'}, status=status.HTTP_205_RESET_CONTENT)
        except Exception:
            return Response({'detail': 'Invalid token.'}, status=status.HTTP_400_BAD_REQUEST)


# ─── Category ViewSet ───────────────────────────────────────────────────────────

class CategoryViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Category.objects.all()
    serializer_class = CategorySerializer
    permission_classes = [IsAuthenticated]


# ─── Transaction ViewSet ────────────────────────────────────────────────────────

class TransactionViewSet(viewsets.ModelViewSet):
    serializer_class = TransactionSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = Transaction.objects.filter(user=self.request.user).select_related('category')
        month = self.request.query_params.get('month')
        year = self.request.query_params.get('year')
        tx_type = self.request.query_params.get('type')
        category = self.request.query_params.get('category')
        search = self.request.query_params.get('search')

        if month:
            qs = qs.filter(date__month=month)
        if year:
            qs = qs.filter(date__year=year)
        if tx_type in ['income', 'expense']:
            qs = qs.filter(type=tx_type)
        if category:
            qs = qs.filter(category__name=category)
        if search:
            qs = qs.filter(Q(name__icontains=search) | Q(note__icontains=search))
        return qs

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

    @action(detail=False, methods=['get'])
    def summary(self, request):
        """GET /api/transactions/summary/?month=4&year=2026"""
        month = request.query_params.get('month', date.today().month)
        year = request.query_params.get('year', date.today().year)

        qs = Transaction.objects.filter(
            user=request.user,
            date__month=month,
            date__year=year
        )
        income = qs.filter(type='income').aggregate(total=Sum('amount'))['total'] or 0
        expense = qs.filter(type='expense').aggregate(total=Sum('amount'))['total'] or 0

        # Category breakdown for expenses
        cat_breakdown = (
            qs.filter(type='expense')
            .values('category__name', 'category__icon')
            .annotate(total=Sum('amount'))
            .order_by('-total')
        )

        return Response({
            'month': int(month),
            'year': int(year),
            'total_income': income,
            'total_expense': expense,
            'balance': income - expense,
            'transaction_count': qs.count(),
            'category_breakdown': list(cat_breakdown),
        })

    @action(detail=False, methods=['get'])
    def monthly_trend(self, request):
        """GET /api/transactions/monthly_trend/ — last 6 months"""
        qs = (
            Transaction.objects.filter(user=request.user)
            .annotate(month=TruncMonth('date'))
            .values('month', 'type')
            .annotate(total=Sum('amount'))
            .order_by('month')
        )
        return Response(list(qs))

    @action(detail=False, methods=['post'], url_path='bulk-upload')
    def bulk_upload(self, request):
        """POST /api/transactions/bulk-upload/  (multipart file)"""
        file = request.FILES.get('file')
        if not file:
            return Response({'error': 'No file provided.'}, status=status.HTTP_400_BAD_REQUEST)

        filename = file.name.lower()
        rows = []
        errors = []

        try:
            if filename.endswith('.csv'):
                rows = _parse_csv(file)
            elif filename.endswith('.xlsx'):
                rows = _parse_xlsx(file)
            elif filename.endswith('.xls'):
                rows = _parse_xls(file)
            else:
                return Response({'error': 'Unsupported file type. Use CSV, XLS, or XLSX.'}, status=status.HTTP_400_BAD_REQUEST)
        except Exception as e:
            return Response({'error': f'File parsing failed: {str(e)}'}, status=status.HTTP_400_BAD_REQUEST)

        created = []
        for i, row in enumerate(rows, start=1):
            ser = BulkTransactionSerializer(data=row)
            if ser.is_valid():
                data = ser.validated_data
                cat_name = data.pop('category', 'other')
                category, _ = Category.objects.get_or_create(name=cat_name, defaults={'icon': '📦'})
                tx = Transaction.objects.create(user=request.user, category=category, **data)
                created.append(tx.id)
            else:
                errors.append({'row': i, 'errors': ser.errors})

        return Response({
            'imported': len(created),
            'failed': len(errors),
            'errors': errors[:10],  # return first 10 errors only
        }, status=status.HTTP_201_CREATED)


# ─── Helpers ────────────────────────────────────────────────────────────────────

HEADER_MAP = {
    'date': ['date', 'transaction date', 'txn date'],
    'name': ['name', 'description', 'desc', 'particulars', 'narration', 'title'],
    'amount': ['amount', 'amt', 'value', 'sum', 'price'],
    'type': ['type', 'txn_type', 'transaction type', 'dr/cr'],
    'category': ['category', 'cat'],
    'note': ['note', 'notes', 'remarks', 'comment'],
}


def _normalize_headers(headers):
    """Map actual file headers to canonical field names."""
    mapping = {}
    for col_idx, h in enumerate(headers):
        h_lower = h.strip().lower()
        for field, aliases in HEADER_MAP.items():
            if h_lower in aliases:
                mapping[field] = col_idx
                break
    return mapping


def _row_to_dict(mapping, values):
    row = {}
    for field, idx in mapping.items():
        if idx < len(values):
            val = values[idx]
            if val is None:
                row[field] = ''
            elif hasattr(val, 'strftime'):
                row[field] = val.strftime('%Y-%m-%d')
            else:
                row[field] = str(val).strip()
    return row


def _parse_csv(file):
    text = file.read().decode('utf-8-sig')
    reader = csv.reader(io.StringIO(text))
    headers = next(reader)
    mapping = _normalize_headers(headers)
    return [_row_to_dict(mapping, row) for row in reader if any(row)]


def _parse_xlsx(file):
    wb = openpyxl.load_workbook(file, read_only=True, data_only=True)
    ws = wb.active
    rows = list(ws.iter_rows(values_only=True))
    if not rows:
        return []
    headers = [str(h) if h is not None else '' for h in rows[0]]
    mapping = _normalize_headers(headers)
    return [_row_to_dict(mapping, list(row)) for row in rows[1:] if any(v is not None for v in row)]


def _parse_xls(file):
    wb = xlrd.open_workbook(file_contents=file.read())
    ws = wb.sheet_by_index(0)
    headers = [str(ws.cell_value(0, c)) for c in range(ws.ncols)]
    mapping = _normalize_headers(headers)
    result = []
    for r in range(1, ws.nrows):
        row_vals = [ws.cell_value(r, c) for c in range(ws.ncols)]
        result.append(_row_to_dict(mapping, row_vals))
    return result
