
use super::connection::CouchDb;

pub async fn inicializar_bases(
    db: &CouchDb,
) -> Result<(), Box<dyn std::error::Error>> {

    let bases = [
        "usuarios",
        "empresas",
        "facturas",
        "ofertas",
        "operaciones",
        "auditoria",
    ];

    println!("Inicializando Apache CouchDB...");

    for base in bases {
        let url = format!("{}/{}", db.url, base);

        let respuesta = db.client
            .put(&url)
            .basic_auth(
                &db.username,
                Some(&db.password)
            )
            .send()
            .await?;

        match respuesta.status().as_u16() {
            201 | 202 => {
                println!("Base creada: {}", base);
            }

            412 => {
                println!("La base {} ya existe", base);
            }

            codigo => {
                let detalle = respuesta.text().await?;

                return Err(format!(
                    "Error en {}: HTTP {} - {}",
                    base, codigo, detalle
                ).into());
            }
        }
    }

    println!("Inicializacion completada.");

    Ok(())
}
