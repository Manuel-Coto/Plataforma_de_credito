class EmpresaOpcion {
  const EmpresaOpcion({
    required this.id,
    required this.nombre,
    required this.estado,
  });

  final String id;
  final String nombre;
  final String estado;

  bool get activa => estado == 'activa';

  factory EmpresaOpcion.fromJson(Map<String, dynamic> json) {
    return EmpresaOpcion(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
      estado: json['estado'] as String? ?? 'pendiente',
    );
  }
}