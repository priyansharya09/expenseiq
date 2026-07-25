import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:expenseiq/config/theme.dart';
import 'package:expenseiq/services/api_service.dart';
import 'package:expenseiq/screens/auth/login_screen.dart';
import 'package:expenseiq/screens/auth/register_screen.dart';
import 'package:expenseiq/screens/dashboard_screen.dart';
import 'package:expenseiq/screens/transactions_screen.dart';
import 'package:expenseiq/screens/add_transaction_screen.dart';
import 'package:expenseiq/screens/bulk_upload_screen.dart';
import 'package:expenseiq/screens/splits_screen.dart';
import 'package:expenseiq/screens/add_debt_screen.dart';
import 'package:expenseiq/screens/reports_screen.dart';
import 'package:expenseiq/screens/budgets_screen.dart';
import 'package:expenseiq/screens/recurring_screen.dart';
import 'package:expenseiq/widgets/calculator_sheet.dart';

/// Global theme provider instance accessible from anywhere.
final themeProvider = ThemeProvider();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.surface,
    ),
  );
  runApp(const ExpenseIQApp());
}

class ExpenseIQApp extends StatefulWidget {
  const ExpenseIQApp({super.key});

  @override
  State<ExpenseIQApp> createState() => _ExpenseIQAppState();
}

class _ExpenseIQAppState extends State<ExpenseIQApp> {
  @override
  void initState() {
    super.initState();
    themeProvider.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    themeProvider.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
    // Update system UI overlay when theme changes
    final isDark = themeProvider.isDarkMode;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ExpenseIQ',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      home: const AuthGate(),
    );
  }
}

/// Decides whether to show Auth screens or the Main app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isChecking = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final loggedIn = await ApiService().isLoggedIn();
    if (mounted) setState(() { _isLoggedIn = loggedIn; _isChecking = false; });
  }

  void _onLoginSuccess() {
    setState(() => _isLoggedIn = true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    if (_isChecking) {
      return Scaffold(
        backgroundColor: colors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 20),
              const CircularProgressIndicator(color: AppColors.primary),
            ],
          ),
        ),
      );
    }

    if (_isLoggedIn) {
      return MainShell(onLogout: () => setState(() => _isLoggedIn = false));
    }

    return AuthScreens(onLoginSuccess: _onLoginSuccess);
  }
}

/// Auth flow: Login ↔ Register
class AuthScreens extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const AuthScreens({super.key, required this.onLoginSuccess});

  @override
  State<AuthScreens> createState() => _AuthScreensState();
}

class _AuthScreensState extends State<AuthScreens> {
  bool _showLogin = true;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _showLogin
          ? LoginScreen(
              key: const ValueKey('login'),
              onLoginSuccess: widget.onLoginSuccess,
              onSwitchToRegister: () => setState(() => _showLogin = false),
            )
          : RegisterScreen(
              key: const ValueKey('register'),
              onRegisterSuccess: widget.onLoginSuccess,
              onSwitchToLogin: () => setState(() => _showLogin = true),
            ),
    );
  }
}

/// Main app shell with bottom navigation.
class MainShell extends StatefulWidget {
  final VoidCallback onLogout;
  const MainShell({super.key, required this.onLogout});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final _dashboardKey = GlobalKey<State>();
  final _transactionsKey = GlobalKey<State>();
  final _splitsKey = GlobalKey<State>();

  @override
  void initState() {
    super.initState();
    // Post any recurring rules that came due while the app was closed, so the
    // dashboard shows an up-to-date picture on first paint.
    _postDueRecurring();
  }

  Future<void> _postDueRecurring() async {
    final posted = await ApiService().runDueRecurring();
    if (posted > 0 && mounted) {
      _refreshScreens();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Posted $posted recurring transaction${posted == 1 ? '' : 's'}'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _refreshScreens() {
    setState(() {
      // Force rebuild of screens to refresh data
      _currentIndex = _currentIndex;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          DashboardScreen(key: _dashboardKey),
          TransactionsScreen(
            key: _transactionsKey,
            onEditTransaction: (tx) async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => AddTransactionScreen(existingTransaction: tx)),
              );
              if (result == true) _refreshScreens();
            },
          ),
          const ReportsScreen(),
          SplitsScreen(
            key: _splitsKey,
            onRefresh: _refreshScreens,
          ),
          _buildProfileTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddOptions(context),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
    final colors = AppColors.of(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border.withValues(alpha: 0.5), width: 0.5)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.dashboard_rounded, 'Home'),
              _buildNavItem(1, Icons.receipt_long_rounded, 'History'),
              const SizedBox(width: 40), // Space for FAB
              _buildNavItem(2, Icons.pie_chart_rounded, 'Reports'),
              _buildNavItem(3, Icons.people_rounded, 'Splits'),
              _buildNavItem(4, Icons.person_outline_rounded, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    final colors = AppColors.of(context);

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? AppColors.primary : colors.textMuted, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? AppColors.primary : colors.textMuted,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddOptions(BuildContext context) {
    final colors = AppColors.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final sheetColors = AppColors.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4, decoration: BoxDecoration(color: sheetColors.textMuted, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 20),
                _buildBottomSheetOption(
                  icon: Icons.add_circle_outline_rounded,
                  title: 'Add Transaction',
                  subtitle: 'Add a new income or expense',
                  color: AppColors.primary,
                  onTap: () async {
                    Navigator.pop(context);
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddTransactionScreen()),
                    );
                    if (result == true) _refreshScreens();
                  },
                ),
                const SizedBox(height: 12),
                _buildBottomSheetOption(
                  icon: Icons.people_outline_rounded,
                  title: 'Add Split',
                  subtitle: 'Add a borrow or lend record',
                  color: AppColors.secondary,
                  onTap: () async {
                    Navigator.pop(context);
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddDebtScreen()),
                    );
                    if (result == true) _refreshScreens();
                  },
                ),
                const SizedBox(height: 12),
                _buildBottomSheetOption(
                  icon: Icons.upload_file_rounded,
                  title: 'Bulk Upload',
                  subtitle: 'Import from CSV or Excel file',
                  color: AppColors.income,
                  onTap: () async {
                    Navigator.pop(context);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BulkUploadScreen()),
                    );
                    _refreshScreens();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomSheetOption({
    required IconData icon, required String title, required String subtitle,
    required Color color, required VoidCallback onTap,
  }) {
    final colors = AppColors.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: colors.textMuted, fontSize: 12)),
              ],
            ),
            const Spacer(),
            Icon(Icons.arrow_forward_ios_rounded, color: colors.textMuted, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    final colors = AppColors.of(context);
    final isDark = themeProvider.isDarkMode;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Profile', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: colors.textPrimary)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.person_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ExpenseIQ User', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                        SizedBox(height: 4),
                        Text('Smart Money Manager', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ─── Theme toggle ──────────────────────────────────────
            GestureDetector(
              onTap: () => themeProvider.toggleTheme(),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    Icon(
                      isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                      color: colors.textSecondary,
                      size: 22,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('App Theme', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500, fontSize: 15)),
                          Text(
                            isDark ? 'Dark Mode' : 'Light Mode',
                            style: TextStyle(color: colors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    // Animated toggle switch
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      width: 52,
                      height: 28,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: isDark ? AppColors.primaryGradient : null,
                        color: isDark ? null : const Color(0xFFE0E0E0),
                      ),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(11),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              isDark ? Icons.nightlight_round : Icons.wb_sunny_rounded,
                              size: 14,
                              color: isDark ? AppColors.primary : const Color(0xFFFFA726),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            _buildProfileOption(
              Icons.savings_outlined, 'Budgets', 'Set monthly spending limits',
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BudgetsScreen()),
                );
                _refreshScreens();
              },
            ),
            _buildProfileOption(
              Icons.autorenew_rounded, 'Recurring', 'Rent, salary and subscriptions',
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RecurringScreen()),
                );
                _refreshScreens();
              },
            ),
            _buildProfileOption(
              Icons.calculate_outlined, 'Calculator', 'Quick math without leaving the app',
              onTap: () => showCalculatorSheet(context),
            ),
            _buildProfileOption(Icons.info_outline, 'About', 'Version 1.0.0', onTap: () {}),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await ApiService().logout();
                  widget.onLogout();
                },
                icon: const Icon(Icons.logout_rounded, color: AppColors.expense),
                label: const Text('Sign Out', style: TextStyle(color: AppColors.expense, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.expense.withValues(alpha: 0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileOption(IconData icon, String title, String subtitle, {VoidCallback? onTap}) {
    final colors = AppColors.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: colors.textSecondary, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w500, fontSize: 15)),
                  Text(subtitle, style: TextStyle(color: colors.textMuted, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: colors.textMuted, size: 14),
          ],
        ),
      ),
    );
  }
}
