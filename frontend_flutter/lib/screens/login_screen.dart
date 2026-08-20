import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'main_screen.dart';
import 'flashscore_home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final user = _usernameController.text.trim();
    final pass = _passwordController.text.trim();
    Map<String, dynamic> result;
    try {
      result = await ApiService.login(username: user, password: pass);
    } catch (_) {
      if (user == 'tiago' && pass == 'jessica2024@') {
        result = {
          'success': true,
          'token': 'mock-local-token',
          'fallback': true,
          'message': 'Modo offline: conecte o backend para dados reais.'
        };
      } else {
        result = {
          'success': false,
          'error': 'Backend offline. Credenciais corretas: tiago / jessica2024@'
        };
      }
    }
    if (result['success'] == true && mounted) {
      final msg = result['fallback'] == true
          ? 'Login MOCK: conecte backend p/ dados reais'
          : 'Login realizado com sucesso!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor:
              result['fallback'] == true ? AppTheme.yellow : AppTheme.neonGreen,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const MainScreen()));
      }
    } else if (mounted) {
      final err = result['error'] ?? 'Credenciais inválidas';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err.toString()),
          backgroundColor: AppTheme.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.flashBg,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Column(
              children: <Widget>[
                if (Navigator.canPop(context))
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_back_ios,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppTheme.flashCard,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppTheme.flashLine, width: 1.2),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppTheme.neonGreen.withValues(alpha: 0.22),
                        blurRadius: 40,
                        spreadRadius: 1,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: <Widget>[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: <Color>[
                                AppTheme.neonGreen.withValues(alpha: 0.22),
                                AppTheme.yellow.withValues(alpha: 0.12),
                              ],
                            ),
                            border: Border.all(
                              color: AppTheme.neonGreen.withValues(alpha: 0.45),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.sports_soccer,
                            size: 70,
                            color: AppTheme.neonGreen,
                          ),
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'TIAGO IA',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.yellow,
                            fontFamily: 'Georgia',
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Sua IA de análise esportiva e cripto',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.flashSub,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 40),
                        TextFormField(
                          controller: _usernameController,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(
                              Icons.person,
                              color: AppTheme.neonGreen,
                            ),
                            hintText: 'Usuário',
                            hintStyle:
                                const TextStyle(color: AppTheme.flashSub),
                            filled: true,
                            fillColor: AppTheme.flashBg,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppTheme.flashLine,
                                width: 1.2,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppTheme.neonGreen,
                                width: 1.5,
                              ),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppTheme.red,
                                width: 1.5,
                              ),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppTheme.red,
                                width: 1.5,
                              ),
                            ),
                          ),
                          validator: (String? value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Informe o usuário';
                            }
                            return null;
                          },
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(
                              Icons.lock,
                              color: AppTheme.neonGreen,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: AppTheme.flashSub,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            hintText: 'Senha',
                            hintStyle:
                                const TextStyle(color: AppTheme.flashSub),
                            filled: true,
                            fillColor: AppTheme.flashBg,
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppTheme.flashLine,
                                width: 1.2,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppTheme.neonGreen,
                                width: 1.5,
                              ),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppTheme.red,
                                width: 1.5,
                              ),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: AppTheme.red,
                                width: 1.5,
                              ),
                            ),
                          ),
                          validator: (String? value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Informe a senha';
                            }
                            return null;
                          },
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                        ),
                        const SizedBox(height: 40),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.neonGreen,
                              foregroundColor: AppTheme.flashBg,
                              padding: const EdgeInsets.symmetric(
                                vertical: 16,
                                horizontal: 60,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              elevation: 8,
                              shadowColor:
                                  AppTheme.neonGreen.withValues(alpha: 0.5),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        AppTheme.flashBg,
                                      ),
                                    ),
                                  )
                                : const Text('ENTRAR'),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text('Login padrão: tiago / jessica2024@',
                            style: TextStyle(
                                color: AppTheme.flashSub, fontSize: 11.5)),
                        const SizedBox(height: 22),
                        SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context)
                                    .push(MaterialPageRoute<dynamic>(
                                  builder: (_) => const FlashScoreHomeScreen(),
                                ));
                              },
                              icon: const Icon(Icons.flash_on_rounded,
                                  color: AppTheme.flashLiveRed, size: 18),
                              label: const Text('ABRIR FLASHSCORE (DEMO)',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8)),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(22)),
                                side: BorderSide(
                                    color: AppTheme.flashLiveRed
                                        .withValues(alpha: 0.85),
                                    width: 1.2),
                                backgroundColor: AppTheme.flashLiveRed
                                    .withValues(alpha: 0.06),
                              ),
                            )),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
