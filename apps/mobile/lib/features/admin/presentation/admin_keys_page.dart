import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/web_frame.dart';

final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

/// Painel "Chaves & integrações" (super admin): grava credenciais no cofre
/// (secure_config, trancado). Os valores são write-only — o painel só mostra
/// se cada chave está preenchida (mascarada), nunca o valor completo.
class AdminKeysPage extends StatefulWidget {
  const AdminKeysPage({super.key});

  @override
  State<AdminKeysPage> createState() => _AdminKeysPageState();
}

class _AdminKeysPageState extends State<AdminKeysPage> {
  Map<String, dynamic> _status = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _loading = true);
    try {
      final res =
          await _functions.httpsCallable('adminGetSecretStatus').call();
      setState(() => _status = Map<String, dynamic>.from(res.data as Map));
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('[${e.code}] ${e.message ?? 'Erro'}')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(String key, String value) async {
    try {
      await _functions
          .httpsCallable('adminSetSecret')
          .call({'key': key, 'value': value});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chave salva com segurança ✅')));
      }
      await _loadStatus();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('[${e.code}] ${e.message ?? 'Erro'}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin — Chaves & integrações')),
      body: WebFrame(
        maxWidth: 720,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadStatus,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _intro(),
                    const SizedBox(height: 14),

                    // ── Mercado Pago (Brasil / Pix) ──────────────────
                    _KeyCard(
                      title: 'Mercado Pago (Pix — Brasil)',
                      icon: Icons.pix,
                      color: const Color(0xFF00A6E0),
                      status: _status['MERCADOPAGO_ACCESS_TOKEN'],
                      fields: [
                        _FieldSpec(
                          key: 'MERCADOPAGO_ACCESS_TOKEN',
                          label: 'Access Token (produção)',
                          hint: 'APP_USR-...',
                        ),
                      ],
                      guide: const [
                        'Acesse mercadopago.com.br → entre na sua conta.',
                        'Vá em "Seu negócio" → "Configurações" → '
                            '"Gestão e administração" → "Credenciais".',
                        'Escolha "Credenciais de produção".',
                        'Copie o "Access Token" (começa com APP_USR-) e cole '
                            'aqui.',
                        'Dica: use a conta EMPRESA para o Pix mostrar o nome '
                            'da empresa no comprovante.',
                      ],
                      onSave: _save,
                    ),

                    // ── Webhook secret (opcional, MP) ────────────────
                    _KeyCard(
                      title: 'Mercado Pago — segredo do webhook (opcional)',
                      icon: Icons.verified_user_outlined,
                      color: const Color(0xFF0079C1),
                      status: _status['MP_WEBHOOK_SECRET'],
                      fields: [
                        _FieldSpec(
                          key: 'MP_WEBHOOK_SECRET',
                          label: 'Assinatura secreta do webhook',
                          hint: 'opcional — reforça a segurança',
                        ),
                      ],
                      guide: const [
                        'No painel do Mercado Pago: "Suas integrações" → sua '
                            'aplicação → "Webhooks".',
                        'Configure a URL de notificação e copie a "chave '
                            'secreta" gerada.',
                        'Cole aqui para validar a assinatura das notificações '
                            '(deixe vazio para desativar).',
                      ],
                      onSave: _save,
                    ),

                    // ── PayPal (internacional) ───────────────────────
                    _KeyCard(
                      title: 'PayPal (depósito — internacional)',
                      icon: Icons.account_balance_wallet,
                      color: const Color(0xFF003087),
                      status: _status['PAYPAL_CLIENT_ID'],
                      status2: _status['PAYPAL_SECRET'],
                      fields: [
                        _FieldSpec(
                          key: 'PAYPAL_CLIENT_ID',
                          label: 'Client ID',
                          hint: 'começa com A...',
                        ),
                        _FieldSpec(
                          key: 'PAYPAL_SECRET',
                          label: 'Secret',
                          hint: 'segredo da app',
                        ),
                        _FieldSpec(
                          key: 'PAYPAL_MODE',
                          label: 'Modo: live ou sandbox',
                          hint: 'live (produção) ou sandbox (testes)',
                        ),
                      ],
                      guide: const [
                        'Acesse developer.paypal.com e entre com sua conta '
                            'EMPRESA.',
                        'Vá em "Apps & Credentials" → aba "Live" (produção).',
                        'Clique em "Create App", dê um nome (ex.: TrialsPaid).',
                        'Copie o "Client ID" e o "Secret" (clique em Show) e '
                            'cole aqui.',
                        'Em "Modo" escreva "live" para valer de verdade '
                            '(ou "sandbox" para testar sem dinheiro real).',
                      ],
                      onSave: _save,
                    ),

                    // ── IA de conteúdo (SEO) ─────────────────────────
                    _KeyCard(
                      title: 'IA de conteúdo (SEO / Novidades)',
                      icon: Icons.auto_awesome,
                      color: const Color(0xFF1565C0),
                      status: _status['GEMINI_API_KEY'],
                      status2: _status['OPENAI_API_KEY'],
                      fields: [
                        _FieldSpec(
                          key: 'GEMINI_API_KEY',
                          label: 'Google Gemini API Key (grátis)',
                          hint: 'recomendado — cota gratuita',
                        ),
                        _FieldSpec(
                          key: 'OPENAI_API_KEY',
                          label: 'OpenAI API Key (alternativa)',
                          hint: 'opcional, se preferir a OpenAI',
                        ),
                      ],
                      guide: const [
                        'RECOMENDADO (grátis): acesse aistudio.google.com/'
                            'apikey e entre com sua conta Google.',
                        'Clique em "Create API key" e copie a chave gerada.',
                        'Cole no campo Gemini. Pronto: os artigos passam a '
                            'ser gerados sozinhos (1 por dia) e você pode '
                            'gerar na hora em Admin → SEO/Novidades.',
                        'Alternativa: platform.openai.com/api-keys (paga por '
                            'uso) → cole no campo OpenAI.',
                      ],
                      onSave: _save,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _intro() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF3FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCADCF6)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock, color: Color(0xFF003b8a), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cole aqui suas chaves — elas ficam guardadas de forma trancada '
              'e são usadas só pelo servidor. Por segurança, o valor nunca é '
              'mostrado de volta: você vê apenas se está preenchida. Trocar '
              'uma chave passa a valer na hora, sem precisar republicar.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldSpec {
  final String key;
  final String label;
  final String hint;
  const _FieldSpec({
    required this.key,
    required this.label,
    required this.hint,
  });
}

class _KeyCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final Map<String, dynamic>? status;
  final Map<String, dynamic>? status2;
  final List<_FieldSpec> fields;
  final List<String> guide;
  final Future<void> Function(String key, String value) onSave;

  const _KeyCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.status,
    required this.fields,
    required this.guide,
    required this.onSave,
    this.status2,
  });

  @override
  State<_KeyCard> createState() => _KeyCardState();
}

class _KeyCardState extends State<_KeyCard> {
  final Map<String, TextEditingController> _ctrls = {};
  bool _saving = false;
  bool _showGuide = false;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      _ctrls[f.key] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveAll() async {
    setState(() => _saving = true);
    for (final f in widget.fields) {
      final v = _ctrls[f.key]!.text.trim();
      if (v.isNotEmpty) await widget.onSave(f.key, v);
    }
    for (final c in _ctrls.values) {
      c.clear();
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.status;
    final configured = s != null && s['set'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.icon, color: widget.color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14.5)),
                ),
                _statusChip(configured, s),
              ],
            ),
            if (widget.status2 != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: _statusChip(widget.status2!['set'] == true,
                    widget.status2, small: true),
              ),
            ],
            const SizedBox(height: 12),
            for (final f in widget.fields) ...[
              TextField(
                controller: _ctrls[f.key],
                obscureText: false,
                decoration: InputDecoration(
                  labelText: f.label,
                  hintText: f.hint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _showGuide = !_showGuide),
                  icon: Icon(
                      _showGuide
                          ? Icons.help
                          : Icons.help_outline,
                      size: 16),
                  label: Text(_showGuide
                      ? 'Ocultar instruções'
                      : 'Onde consigo essa chave?'),
                  style: TextButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(fontSize: 12.5)),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _saveAll,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Salvar'),
                ),
              ],
            ),
            if (_showGuide) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F8FC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE3E9F4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < widget.guide.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${i + 1}. ',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: widget.color,
                                    fontSize: 12.5)),
                            Expanded(
                              child: Text(widget.guide[i],
                                  style: const TextStyle(
                                      fontSize: 12.5, height: 1.4)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusChip(bool configured, Map<String, dynamic>? s,
      {bool small = false}) {
    final source = s?['source'] as String?;
    final masked = s?['masked'] as String? ?? '';
    final label = configured
        ? (source == 'env'
            ? 'Configurada (.env)'
            : 'Configurada $masked')
        : 'Não configurada';
    final color = configured ? const Color(0xFF00875A) : Colors.orange;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 7 : 9, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(configured ? Icons.check_circle : Icons.error_outline,
              size: small ? 11 : 13, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: small ? 10.5 : 11.5,
                  fontWeight: FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}
