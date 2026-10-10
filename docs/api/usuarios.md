# Usuarios

El módulo utiliza la base CouchDB `usuarios` y el índice Mango `usuarios-correo/por-correo`.

La estructura de las cuentas, los campos obligatorios y opcionales y un ejemplo están en [la documentación de la base usuarios](../../database/usuarios/README.md).

El backend Rust crea la base y el índice automáticamente al iniciar.