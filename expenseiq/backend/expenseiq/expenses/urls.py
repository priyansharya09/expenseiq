# expenses/urls.py
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from .views import RegisterView, LogoutView, CategoryViewSet, TransactionViewSet, ContactViewSet, DebtRecordViewSet, debt_summary

router = DefaultRouter()
router.register(r'categories', CategoryViewSet, basename='category')
router.register(r'transactions', TransactionViewSet, basename='transaction')
router.register(r'contacts', ContactViewSet, basename='contact')
router.register(r'debts', DebtRecordViewSet, basename='debt')

urlpatterns = [
    # Auth
    path('auth/register/', RegisterView.as_view(), name='register'),
    path('auth/login/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('auth/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('auth/logout/', LogoutView.as_view(), name='logout'),

    # Resources
    path('debts/summary/', debt_summary, name='debt-summary'),
    path('', include(router.urls)),
]
