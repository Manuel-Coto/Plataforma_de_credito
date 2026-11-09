import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/theme/credito_theme.dart';
import '../../../models/financiamiento.dart';
import '../../../services/credito_service.dart';
import '../../../services/inversion_service.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/page_header.dart';
import '../../creditos/providers/operaciones_provider.dart';
import '../../usuarios/providers/sesion_provider.dart';
import '../providers/inversiones_provider.dart';
import '../widgets/aporte_dialog.dart';
import 'publicar_oferta_screen.dart';

/// Se integra directamente en el shell; sus listas y cursores son locales.
class InversionesScreen extends StatelessWidget {
  const InversionesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final sesion = context.watch<SesionProvider>();
    return ChangeNotifierProvider(
      key: ValueKey('${sesion.version}:${sesion.usuario?["rol"]}'),
      create: (_) => InversionesProvider(
          InversionService(sesion.api), CreditoService(sesion.api),
          rol: sesion.usuario!['rol'] as String,
          usuarioId: sesion.usuario!['id'] as String),
      child: const _InversionesView(),
    );
  }
}

class _InversionesView extends StatefulWidget {
  const _InversionesView();
  @override
  State<_InversionesView> createState() => _InversionesViewState();
}

class _InversionesViewState extends State<_InversionesView> {
  bool _historial = false, _consultando = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<InversionesProvider>().cargar();
    });
  }

  void _mensaje(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _publicar() async {
    final provider = context.read<InversionesProvider>();
    final oferta = await Navigator.push<Oferta>(
        context,
        MaterialPageRoute(
            builder: (_) => PublicarOfertaScreen(api: provider.servicio.api)));
    if (mounted && oferta != null) {
      await provider.cargarOfertas();
      _mensaje('Oferta publicada correctamente.');
    }
  }

  Future<void> _aportar(Oferta oferta) async {
    if (_consultando) return;
    final provider = context.read<InversionesProvider>();
    setState(() => _consultando = true);
    try {
      final pendiente = provider.intentoPendiente(oferta.id);
      final actual = pendiente?.oferta ??
          await provider.servicio.actualizarOferta(oferta.id);
      if (!mounted) return;
      if (pendiente == null && !actual.aceptaAportes) {
        _mensaje('Esta oferta ya no admite aportes. Actualiza el catálogo.');
        return;
      }
      final inversion = await showDialog<Inversion>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AporteDialog(oferta: actual, provider: provider));
      if (inversion != null) {
        _mensaje(
            'Aporte registrado. Confirma su pago simulado desde el historial.');
      }
    } catch (error) {
      _mensaje(mensajeFinanciero(error));
    } finally {
      if (mounted) setState(() => _consultando = false);
    }
  }

  Future<void> _confirmar(Inversion inversion) async {
    final provider = context.read<InversionesProvider>();
    final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Confirmar pago simulado del aporte'),
                content: Text(
                    'Confirmarás el aporte de ${money(inversion.montoCentavos, inversion.moneda)}. Esta operación es simulada y no mueve dinero real.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Volver')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Confirmar pago del aporte'))
                ]));
    if (!mounted || confirmar != true) return;
    try {
      final result = await provider.confirmar(inversion);
      _mensaje(result.sincronizacionPendiente
          ? 'Aporte confirmado. Su registro de auditoría está pendiente de sincronización.'
          : 'Aporte confirmado correctamente.');
    } catch (error) {
      _mensaje(mensajeFinanciero(error));
    }
  }

  Future<void> _crearCredito(Oferta oferta) async {
    final provider = context.read<InversionesProvider>();
    final confirmar = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Crear crédito'),
                content: Text(
                    'Se comprobarán los aportes confirmados de la oferta de ${money(oferta.objetivoCentavos, oferta.moneda)}. El servidor calculará el interés y el saldo del crédito.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Volver')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Confirmar creación'))
                ]));
    if (!mounted || confirmar != true) return;
    try {
      final result = await provider.crearCredito(oferta);
      if (!mounted) return;
      context.read<OperacionesProvider?>()?.incorporar(result);
      _mensaje(result.sincronizacionPendiente
          ? 'Crédito guardado. Quedan actualizaciones relacionadas por sincronizar.'
          : 'Crédito creado. Puedes consultarlo en Créditos y pagos.');
    } catch (error) {
      _mensaje(mensajeFinanciero(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InversionesProvider>();
    final cargando =
        _historial ? provider.cargandoInversiones : provider.cargandoOfertas;
    final error =
        _historial ? provider.errorInversiones : provider.errorOfertas;
    return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: RefreshIndicator(
                onRefresh: provider.cargar,
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: [
                      PageHeader(
                          eyebrow: 'CONECTA Y CRECE',
                          title: 'Ofertas e inversiones',
                          subtitle:
                              'Financiamiento colaborativo con aportes y pagos simulados.',
                          action: Wrap(spacing: 10, runSpacing: 10, children: [
                            if (provider.rol == 'pyme' ||
                                provider.rol == 'administrador')
                              FilledButton.icon(
                                  onPressed: _publicar,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Publicar oferta')),
                            OutlinedButton.icon(
                                onPressed: cargando ? null : provider.cargar,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Actualizar'))
                          ])),
                      const SizedBox(height: 26),
                      if (provider.veHistorial) ...[
                        Wrap(spacing: 10, runSpacing: 10, children: [
                          ChoiceChip(
                              label: const Text('Catálogo de ofertas'),
                              selected: !_historial,
                              onSelected: (_) =>
                                  setState(() => _historial = false)),
                          ChoiceChip(
                              label: Text(provider.rol == 'administrador'
                                  ? 'Inversiones de la plataforma'
                                  : 'Mis inversiones'),
                              selected: _historial,
                              onSelected: (_) =>
                                  setState(() => _historial = true))
                        ]),
                        const SizedBox(height: 20)
                      ],
                      if (provider.aportesPendientes.isNotEmpty) ...[
                        Card(
                            color: AppColors.softPrimary,
                            child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                          'Aportes sin respuesta confirmada',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 7),
                                      const Text(
                                          'Reintenta el mismo registro para comprobar su resultado sin duplicarlo.'),
                                      for (final intento
                                          in provider.aportesPendientes)
                                        TextButton.icon(
                                            onPressed: _consultando ||
                                                    provider.ocupado(
                                                        intento.oferta.id)
                                                ? null
                                                : () =>
                                                    _aportar(intento.oferta),
                                            icon: const Icon(Icons.replay),
                                            label: Text(
                                                'Resolver aporte de ${money(intento.montoCentavos, intento.oferta.moneda)}')),
                                    ]))),
                        const SizedBox(height: 16)
                      ],
                      if (!_historial) ...[
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final entry in const <String?, String>{
                            null: 'Todas',
                            'abierta': 'Abiertas',
                            'objetivo_alcanzado': 'Objetivo alcanzado',
                            'financiada': 'Financiadas'
                          }.entries)
                            ChoiceChip(
                                label: Text(entry.value),
                                selected: provider.estadoOferta == entry.key,
                                onSelected: (_) =>
                                    provider.filtrarOfertas(entry.key))
                        ]),
                        const SizedBox(height: 18)
                      ],
                      if (cargando || _consultando)
                        const Padding(
                            padding: EdgeInsets.only(bottom: 18),
                            child: LinearProgressIndicator()),
                      if (error != null) ...[
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(error,
                                          style: const TextStyle(
                                              color: AppColors.error)),
                                      TextButton(
                                          onPressed:
                                              cargando ? null : provider.cargar,
                                          child: const Text('Reintentar'))
                                    ]))),
                        const SizedBox(height: 14)
                      ],
                      if (_historial) ...[
                        Card(
                            color: AppColors.softPrimary,
                            child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                          '¿Un aporte quedó sin aparecer?',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 7),
                                      const Text(
                                          'Recupera registros pendientes sin reservar fondos nuevos. Esta acción no confirma el pago de tus aportes.'),
                                      const SizedBox(height: 12),
                                      OutlinedButton.icon(
                                          onPressed: provider.recuperando
                                              ? null
                                              : () async {
                                                  try {
                                                    final result =
                                                        await provider
                                                            .recuperar();
                                                    _mensaje(
                                                        'Recuperadas: ${result.recuperadas}. Pendientes: ${result.pendientes}.');
                                                  } catch (error) {
                                                    _mensaje(mensajeFinanciero(
                                                        error));
                                                  }
                                                },
                                          icon:
                                              const Icon(Icons.restore_rounded),
                                          label: Text(provider.recuperando
                                              ? 'Recuperando...'
                                              : provider.cursorRecuperacion !=
                                                      null
                                                  ? 'Continuar recuperación'
                                                  : 'Recuperar aportes pendientes')),
                                      if (provider.recuperacion != null) ...[
                                        const SizedBox(height: 10),
                                        Text(
                                            'Última página: ${provider.recuperacion!.recuperadas} recuperadas · ${provider.recuperacion!.pendientes} pendientes.'),
                                        if (provider.cursorRecuperacion != null)
                                          const Text(
                                              'Hay más registros por revisar. Continúa para recorrer la siguiente página.')
                                      ],
                                    ]))),
                        const SizedBox(height: 16),
                        if (!cargando && provider.inversiones.isEmpty)
                          const EmptyState(
                              icon: Icons.savings_outlined,
                              title: 'Tus aportes empiezan aquí',
                              message:
                                  'Cuando registres una inversión, podrás consultar su estado y confirmar su pago simulado.'),
                        for (final inversion in provider.inversiones)
                          _inversion(provider, inversion),
                        if (provider.masInversiones)
                          OutlinedButton(
                              onPressed: cargando
                                  ? null
                                  : () => provider.cargarInversiones(mas: true),
                              child: const Text('Cargar más inversiones')),
                      ] else ...[
                        if (!cargando && provider.ofertas.isEmpty)
                          const EmptyState(
                              icon: Icons.trending_up_rounded,
                              title: 'Nuevas posibilidades, próximamente',
                              message:
                                  'No hay ofertas en este estado. Prueba otro filtro o vuelve más tarde.'),
                        for (final oferta in provider.ofertas)
                          _oferta(provider, oferta),
                        if (provider.masOfertas)
                          OutlinedButton(
                              onPressed: cargando
                                  ? null
                                  : () => provider.cargarOfertas(mas: true),
                              child: const Text('Cargar más ofertas')),
                      ],
                    ]))));
  }

  Widget _oferta(InversionesProvider provider, Oferta oferta) => Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
          padding: const EdgeInsets.all(22),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _cabecera('Factura ${oferta.facturaId}', _estado(oferta.estado),
                Icons.trending_up_rounded),
            const SizedBox(height: 18),
            Wrap(spacing: 28, runSpacing: 14, children: [
              _dato('Objetivo', money(oferta.objetivoCentavos, oferta.moneda)),
              _dato(
                  'Recaudado', money(oferta.recaudadoCentavos, oferta.moneda)),
              _dato('Tasa anual', '${oferta.tasaAnual.toStringAsFixed(2)}%'),
              _dato('Cierre', fecha(oferta.fechaCierre.toLocal())),
            ]),
            const SizedBox(height: 20),
            ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                    value: oferta.progreso,
                    minHeight: 7,
                    backgroundColor: AppColors.softPrimary)),
            const SizedBox(height: 12),
            Text(
                'Disponible: ${money(oferta.disponibleCentavos, oferta.moneda)}',
                style: const TextStyle(color: AppColors.muted)),
            if (provider.rol == 'inversionista' &&
                oferta.creadoPor != provider.usuarioId &&
                (oferta.aceptaAportes ||
                    provider.intentoPendiente(oferta.id) != null)) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                  onPressed: _consultando || provider.ocupado(oferta.id)
                      ? null
                      : () => _aportar(oferta),
                  icon: const Icon(Icons.add_card_outlined),
                  label: const Text('Aportar'))
            ],
            if (provider.rol == 'administrador' &&
                oferta.estado == 'objetivo_alcanzado') ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                  onPressed: provider.ocupado(oferta.id)
                      ? null
                      : () => _crearCredito(oferta),
                  icon: const Icon(Icons.account_balance_outlined),
                  label: const Text('Crear crédito'))
            ],
          ])));

  Widget _inversion(InversionesProvider provider, Inversion inversion) => Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
          padding: const EdgeInsets.all(22),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _cabecera('Factura ${inversion.facturaId}',
                _estado(inversion.estado), Icons.savings_outlined),
            const SizedBox(height: 18),
            Wrap(spacing: 28, runSpacing: 14, children: [
              _dato('Aporte', money(inversion.montoCentavos, inversion.moneda)),
              _dato('Registrado', fecha(inversion.fechaCreacion.toLocal())),
              if (inversion.rendimientoCentavos != null)
                _dato('Rendimiento',
                    money(inversion.rendimientoCentavos!, inversion.moneda)),
              if (inversion.fechaLiquidacion != null)
                _dato('Liquidación',
                    fecha(inversion.fechaLiquidacion!.toLocal())),
            ]),
            if (provider.rol == 'administrador') ...[
              const SizedBox(height: 12),
              Text('Inversionista: ${inversion.inversionistaId}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12))
            ],
            if (provider.sincronizacionesPendientes.contains(inversion.id)) ...[
              const SizedBox(height: 12),
              const Text(
                  'Aporte confirmado; auditoría pendiente de sincronización.',
                  style: TextStyle(color: AppColors.muted))
            ],
            if (inversion.puedeConfirmarse ||
                provider.sincronizacionesPendientes.contains(inversion.id)) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                  onPressed: provider.ocupado(inversion.id)
                      ? null
                      : () => _confirmar(inversion),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                      provider.sincronizacionesPendientes.contains(inversion.id)
                          ? 'Reintentar sincronización del aporte'
                          : 'Confirmar pago simulado'))
            ],
          ])));

  Widget _cabecera(String titulo, String estado, IconData icon) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: AppColors.primary, size: 25),
        const SizedBox(width: 12),
        Expanded(
            child:
                Text(titulo, style: Theme.of(context).textTheme.titleMedium)),
        const SizedBox(width: 10),
        Flexible(
            child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: AppColors.softPrimary,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(estado,
                    style: const TextStyle(
                        color: AppColors.primary, fontSize: 12))))
      ]);
  Widget _dato(String titulo, String valor) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo,
            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        const SizedBox(height: 5),
        Text(valor,
            style: const TextStyle(
                color: AppColors.ink, fontWeight: FontWeight.w600))
      ]);
  String _estado(String estado) =>
      const {
        'abierta': 'Abierta',
        'objetivo_alcanzado': 'Objetivo alcanzado',
        'financiada': 'Financiada',
        'cerrada': 'Cerrada',
        'cancelada': 'Cancelada',
        'registrada': 'Registrada',
        'pago_pendiente': 'Pago pendiente',
        'confirmada': 'Confirmada',
        'liquidada': 'Liquidada',
        'reembolsada': 'Reembolsada',
        'fallida': 'Fallida'
      }[estado] ??
      estado;
}
