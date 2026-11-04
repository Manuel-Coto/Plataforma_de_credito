enum Rol { pyme, inversionista, administrador }

Rol rolDesdeString(String? s) => switch (s?.toLowerCase()) {
  'administrador' => Rol.administrador,
  'inversionista' => Rol.inversionista,
  _ => Rol.pyme,
};

enum Seccion { usuarios, empresas, facturas, creditos, administracion, auditoria }

const permisos = <Rol, List<Seccion>>{
  Rol.pyme: [Seccion.usuarios, Seccion.empresas, Seccion.facturas, Seccion.creditos],
  Rol.inversionista: [Seccion.usuarios, Seccion.facturas, Seccion.creditos],
  Rol.administrador: [Seccion.usuarios, Seccion.empresas, Seccion.facturas,
    Seccion.creditos, Seccion.administracion, Seccion.auditoria],
};