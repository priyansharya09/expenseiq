from rest_framework import viewsets, status, generics
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.exceptions import PermissionDenied
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken
from django.contrib.auth.models import User
from django.db.models import Sum, Q, Count
from django.db.models.functions import TruncMonth
from django.http import HttpResponse
import openpyxl
import xlrd
import csv
import io
from datetime import date, datetime

from .models import Transaction, Category, Contact, DebtRecord, Budget, RecurringTransaction
from .serializers import (
    UserSerializer, TransactionSerializer, CategorySerializer,
    BulkTransactionSerializer, MonthlySummarySerializer,
    ContactSerializer, DebtRecordSerializer,
    BudgetSerializer, RecurringTransactionSerializer,
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

class CategoryViewSet(viewsets.ModelViewSet):
    serializer_class = CategorySerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = Category.objects.filter(Q(user__isnull=True) | Q(user=self.request.user))
        kind = self.request.query_params.get('kind')
        if kind in ('income', 'expense'):
            # 'both' categories are always relevant to either side
            qs = qs.filter(Q(kind=kind) | Q(kind='both'))
        return qs.order_by('kind', 'name')

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

    def _guard_system(self, instance):
        if instance.user_id is None:
            raise PermissionDenied('System default categories cannot be modified.')

    def perform_update(self, serializer):
        self._guard_system(serializer.instance)
        serializer.save(user=self.request.user)

    def perform_destroy(self, instance):
        self._guard_system(instance)
        instance.delete()


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
        """Report summary.

        Month mode:  GET /api/transactions/summary/?month=4&year=2026
        Range mode:  GET /api/transactions/summary/?start_date=2026-07-01&end_date=2026-07-24
        """
        import calendar
        from django.db.models.functions import ExtractDay

        start_raw = request.query_params.get('start_date')
        end_raw = request.query_params.get('end_date')
        range_mode = bool(start_raw and end_raw)

        base = Transaction.objects.filter(user=request.user)

        if range_mode:
            try:
                start = datetime.strptime(start_raw, '%Y-%m-%d').date()
                end = datetime.strptime(end_raw, '%Y-%m-%d').date()
            except (ValueError, TypeError):
                return Response({'error': 'Invalid date format, expected YYYY-MM-DD.'},
                                status=status.HTTP_400_BAD_REQUEST)
            if end < start:
                start, end = end, start
            qs = base.filter(date__range=(start, end))
            span_days = (end - start).days + 1
            period = {
                'mode': 'range',
                'label': f'{start.strftime("%d %b %Y")} – {end.strftime("%d %b %Y")}',
                'start_date': start.isoformat(),
                'end_date': end.isoformat(),
            }
            month = year = None
        else:
            month = int(request.query_params.get('month', date.today().month))
            year = int(request.query_params.get('year', date.today().year))
            qs = base.filter(date__month=month, date__year=year)
            span_days = calendar.monthrange(year, month)[1]
            period = {
                'mode': 'month',
                'label': f'{calendar.month_name[month]} {year}',
                'start_date': date(year, month, 1).isoformat(),
                'end_date': date(year, month, span_days).isoformat(),
            }

        income = qs.filter(type='income').aggregate(total=Sum('amount'))['total'] or 0
        expense = qs.filter(type='expense').aggregate(total=Sum('amount'))['total'] or 0

        cat_breakdown = list(
            qs.filter(type='expense')
            .values('category__name', 'category__icon')
            .annotate(total=Sum('amount'))
            .order_by('-total')
        )
        income_cat_breakdown = list(
            qs.filter(type='income')
            .values('category__name', 'category__icon')
            .annotate(total=Sum('amount'))
            .order_by('-total')
        )

        total_shared = qs.filter(type='expense').aggregate(total=Sum('shared_amount'))['total'] or 0
        payment_mode_breakdown = list(
            qs.filter(type='expense', payment_mode__isnull=False)
            .values('payment_mode')
            .annotate(total=Sum('amount'))
            .order_by('-total')
        )

        avg_daily_expense = float(expense) / span_days if span_days else 0

        # Month-over-month comparison (only meaningful in month mode)
        income_change_pct = expense_change_pct = 0
        if not range_mode:
            prev_month, prev_year = month - 1, year
            if prev_month == 0:
                prev_month, prev_year = 12, year - 1
            prev_qs = base.filter(date__month=prev_month, date__year=prev_year)
            prev_income = prev_qs.filter(type='income').aggregate(total=Sum('amount'))['total'] or 0
            prev_expense = prev_qs.filter(type='expense').aggregate(total=Sum('amount'))['total'] or 0
            income_change_pct = ((float(income) - float(prev_income)) / float(prev_income) * 100) if prev_income else 0
            expense_change_pct = ((float(expense) - float(prev_expense)) / float(prev_expense) * 100) if prev_expense else 0

        # Spending trend: by day-of-month for a single month, by full date for a range
        if range_mode:
            daily_spending = [
                {'date': row['date'].isoformat(), 'amount': row['amount']}
                for row in qs.filter(type='expense')
                .values('date')
                .annotate(amount=Sum('amount')).order_by('date')
            ]
        else:
            daily_spending = list(
                qs.filter(type='expense')
                .annotate(day=ExtractDay('date'))
                .values('day')
                .annotate(amount=Sum('amount'))
                .order_by('day')
            )

        return Response({
            'month': month,
            'year': year,
            'period': period,
            'total_income': income,
            'total_expense': expense,
            'balance': income - expense,
            'transaction_count': qs.count(),
            'category_breakdown': cat_breakdown,
            'income_category_breakdown': income_cat_breakdown,
            'total_shared': total_shared,
            'payment_mode_breakdown': payment_mode_breakdown,
            'avg_daily_expense': avg_daily_expense,
            'comparison': {
                'income_change_pct': income_change_pct,
                'expense_change_pct': expense_change_pct,
            },
            'daily_spending': daily_spending,
        })

    @action(detail=False, methods=['get'])
    def suggest(self, request):
        """GET /api/transactions/suggest/?name=<>&type=<> — learned category + payment mode."""
        name = (request.query_params.get('name') or '').strip()
        tx_type = request.query_params.get('type')
        if not name:
            return Response({})

        qs = Transaction.objects.filter(user=request.user, name__iexact=name)
        if tx_type in ('income', 'expense'):
            qs = qs.filter(type=tx_type)

        top_cat = (
            qs.filter(category__isnull=False)
            .values('category', 'category__name', 'category__icon')
            .annotate(c=Count('id')).order_by('-c').first()
        )
        top_mode = (
            qs.filter(payment_mode__isnull=False)
            .values('payment_mode')
            .annotate(c=Count('id')).order_by('-c').first()
        )
        if not top_cat and not top_mode:
            return Response({})
        return Response({
            'category': top_cat['category'] if top_cat else None,
            'category_name': top_cat['category__name'] if top_cat else None,
            'category_icon': top_cat['category__icon'] if top_cat else None,
            'payment_mode': top_mode['payment_mode'] if top_mode else None,
        })

    @action(detail=False, methods=['get'], url_path='name-suggestions')
    def name_suggestions(self, request):
        """GET /api/transactions/name-suggestions/?q=<> — distinct past names for autocomplete."""
        q = (request.query_params.get('q') or '').strip()
        qs = Transaction.objects.filter(user=request.user)
        if q:
            qs = qs.filter(name__istartswith=q)
        names = list(qs.values_list('name', flat=True).distinct()[:8])
        return Response(names)

    @action(detail=False, methods=['get'])
    def export(self, request):
        """GET /api/transactions/export/ — CSV of the (filtered) transactions."""
        qs = self.get_queryset()
        response = HttpResponse(content_type='text/csv')
        response['Content-Disposition'] = 'attachment; filename="transactions.csv"'
        writer = csv.writer(response)
        writer.writerow(['Date', 'Name', 'Type', 'Category', 'Amount',
                         'Shared', 'Payment Mode', 'Note'])
        for tx in qs:
            writer.writerow([
                tx.date, tx.name, tx.type,
                tx.category.name if tx.category else '',
                tx.amount, tx.shared_amount, tx.payment_mode or '', tx.note,
            ])
        return response

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


# ─── Contact and Debt ViewSets ──────────────────────────────────────────────────

class ContactViewSet(viewsets.ModelViewSet):
    serializer_class = ContactSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return Contact.objects.filter(user=self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

    @action(detail=True, methods=['get'])
    def balance(self, request, pk=None):
        contact = self.get_object()
        serializer = self.get_serializer(contact)
        records = contact.debt_records.filter(is_settled=False)
        records_data = DebtRecordSerializer(records, many=True).data
        return Response({
            'contact': serializer.data,
            'records': records_data
        })


class DebtRecordViewSet(viewsets.ModelViewSet):
    serializer_class = DebtRecordSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = DebtRecord.objects.filter(user=self.request.user)
        contact_id = self.request.query_params.get('contact')
        settled = self.request.query_params.get('settled')
        if contact_id:
            qs = qs.filter(contact_id=contact_id)
        if settled is not None:
            qs = qs.filter(is_settled=settled.lower() == 'true')
        return qs

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

    @action(detail=True, methods=['post'])
    def settle(self, request, pk=None):
        record = self.get_object()
        record.is_settled = True
        record.settled_date = date.today()
        record.save()
        return Response(self.get_serializer(record).data)

    @action(detail=False, methods=['post'])
    def settle_all(self, request):
        contact_id = request.data.get('contact_id')
        if not contact_id:
            return Response({'error': 'contact_id is required'}, status=status.HTTP_400_BAD_REQUEST)
        records = DebtRecord.objects.filter(user=request.user, contact_id=contact_id, is_settled=False)
        count = records.count()
        records.update(is_settled=True, settled_date=date.today())
        return Response({'settled_count': count})


from rest_framework.decorators import api_view, permission_classes
@api_view(['GET'])
@permission_classes([IsAuthenticated])
def debt_summary(request):
    records = DebtRecord.objects.filter(user=request.user, is_settled=False)
    total_lent = records.filter(type='lend').aggregate(total=Sum('amount'))['total'] or 0
    total_borrowed = records.filter(type='borrow').aggregate(total=Sum('amount'))['total'] or 0
    return Response({
        'total_lent': total_lent,
        'total_borrowed': total_borrowed,
        'net_balance': total_lent - total_borrowed,
        'active_debts_count': records.count()
    })


# ─── Budget ViewSet ───────────────────────────────────────────────────────────

class BudgetViewSet(viewsets.ModelViewSet):
    serializer_class = BudgetSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        qs = Budget.objects.filter(user=self.request.user).select_related('category')
        month = self.request.query_params.get('month')
        year = self.request.query_params.get('year')
        if month:
            qs = qs.filter(month=month)
        if year:
            qs = qs.filter(year=year)
        return qs

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

    @action(detail=False, methods=['get'])
    def status(self, request):
        """GET /api/budgets/status/?month=&year= — budgets with spent/remaining/pct."""
        month = request.query_params.get('month', date.today().month)
        year = request.query_params.get('year', date.today().year)
        qs = Budget.objects.filter(
            user=request.user, month=month, year=year
        ).select_related('category')
        return Response(self.get_serializer(qs, many=True).data)


# ─── Recurring Transaction ViewSet ────────────────────────────────────────────

class RecurringTransactionViewSet(viewsets.ModelViewSet):
    serializer_class = RecurringTransactionSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        return RecurringTransaction.objects.filter(
            user=self.request.user).select_related('category')

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)

    @action(detail=False, methods=['post'], url_path='run-due')
    def run_due(self, request):
        """POST /api/recurring/run-due/ — post any active rules due on/before today."""
        today = date.today()
        rules = RecurringTransaction.objects.filter(
            user=request.user, active=True, next_run__lte=today)
        posted = []
        for rule in rules:
            # A rule may be overdue by several periods; catch up each one.
            guard = 0
            while rule.next_run <= today and guard < 60:
                tx = Transaction.objects.create(
                    user=request.user,
                    name=rule.name,
                    amount=rule.amount,
                    type=rule.type,
                    category=rule.category,
                    date=rule.next_run,
                    note=rule.note or 'Auto-posted (recurring)',
                    payment_mode=rule.payment_mode,
                )
                posted.append(tx.id)
                rule.advance()
                guard += 1
            rule.save()
        return Response({'posted': len(posted), 'transaction_ids': posted})


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
