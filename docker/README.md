# Docker

## Iniciar la aplicación

Con Docker Desktop en ejecución, abre PowerShell en la raíz del repositorio.
Prepara `Backend/credito_backend/.env` según el
[README principal](../README.md#preparar-el-entorno-local): completa
`COUCHDB_USERNAME`, `COUCHDB_PASSWORD` y una clave `JWT_SECRET` válida.
Se usan las mismas credenciales para CouchDB y el backend.

```powershell
docker compose --env-file Backend/credito_backend/.env -f docker/docker-compose.yml up -d --build --wait
```

El argumento `--env-file` es necesario: Compose no busca automáticamente el
`.env` dentro de `Backend/credito_backend`. Si falta una variable obligatoria,
el comando muestra cuál debes completar antes de crear los contenedores.
La URL interna de CouchDB se configura como `http://couchdb:5984`, y el backend
espera a que CouchDB esté listo antes de iniciar.

Comprueba el estado y los registros desde la raíz:

```powershell
docker compose --env-file Backend/credito_backend/.env -f docker/docker-compose.yml ps
docker compose --env-file Backend/credito_backend/.env -f docker/docker-compose.yml logs --tail 100 backend
Invoke-RestMethod http://127.0.0.1:3000/api/health
```

La API responde en [localhost:3000](http://127.0.0.1:3000/api/health) y Fauxton en
[localhost:5984](http://127.0.0.1:5984/_utils/). El endpoint de salud solo confirma
que la API responde; revisa los registros para comprobar la inicialización de
las bases y sus índices.

Para detener los contenedores y conservar los datos:

```powershell
docker compose --env-file Backend/credito_backend/.env -f docker/docker-compose.yml down
```

## Replicación de CouchDB

La demo copia un documento ficticio del origen a la réplica y luego copia una
actualización. Usa la [API nativa de CouchDB](https://docs.couchdb.org/en/stable/api/server/common.html#post--_replicate):
cada llamada termina al completar la copia. La segunda conserva la nueva
revisión sin crear otro documento. Es un flujo de un solo sentido; no queda una
tarea continua y no es el modo sin conexión de Flutter.

## Probar entre dos instancias con Docker Compose

1. Con Docker Desktop en ejecución, abre PowerShell 7 en la raíz del repositorio.
2. Usa una cuenta y contraseña exclusivas del laboratorio. No uses las
   credenciales de la aplicación.

```powershell
$credencial = Get-Credential -Message 'Elige usuario y contrasena para el laboratorio'
$env:COUCHDB_REPL_USER = $credencial.UserName
$env:COUCHDB_REPL_PASSWORD = $credencial.GetNetworkCredential().Password
docker compose -f docker/compose.replicacion.yml up -d --wait
```

Cuando ambos contenedores estén listos, ejecuta:

```powershell
.\docker\probar-replicacion.ps1 -Credencial $credencial
```

La salida confirma que son dos instancias distintas, que el documento inicial
llegó a la réplica y que la segunda copia conservó la nueva revisión. El guion
crea dos bases con nombres aleatorios y elimina solo las que creó. Para verlas
después de la prueba, agrega `-ConservarBases` y abre Fauxton en el
[origen](http://127.0.0.1:15984/_utils/) o en la
[réplica](http://127.0.0.1:25984/_utils/).

Los puertos del laboratorio solo escuchan en loopback y los nodos tienen
volúmenes separados. La prueba comprueba que sus identificadores sean distintos
antes de crear bases. El origen se comunica con la réplica por la red de
Compose. Las credenciales del laboratorio no se escriben en el repositorio:
Docker las conserva como configuración de los contenedores mientras existan.
Para detener el laboratorio sin borrar los volúmenes:

```powershell
docker compose -f docker/compose.replicacion.yml down
Remove-Item Env:COUCHDB_REPL_USER, Env:COUCHDB_REPL_PASSWORD
Remove-Variable credencial
```

La prueba no lee ni replica las seis bases de la aplicación, y no requiere
cambiar el `.env` del backend. El Compose principal se mantiene separado.

## Comprobación sin Docker

Si solo tienes un CouchDB local en el puerto 5984, puedes comprobar la misma
copia entre dos bases del servidor con este comando. Esto no verifica la red
entre dos instancias:

```powershell
.\docker\probar-replicacion.ps1 -CouchDbLocal
```
