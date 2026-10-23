/// Los cuatro momentos posibles al cargar datos del servidor.
enum EstadoCarga {
  inicial, // todavía no se ha pedido nada
  cargando, // petición en curso
  listo, // llegaron los datos
  error, // algo falló
}